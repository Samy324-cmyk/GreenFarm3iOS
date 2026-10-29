import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_io.dart';
import 'package:green_farm_port/engine/dalvik/numbers.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/generated/c0171.dart';

const input = 'Ljava/io/InputStream;';
const output = 'Ljava/io/OutputStream;';
const byteInput = 'Ljava/io/ByteArrayInputStream;';
const byteOutput = 'Ljava/io/ByteArrayOutputStream;';
const dataInput = 'Ljava/io/DataInputStream;';
const dataOutput = 'Ljava/io/DataOutputStream;';

void main() {
  late DalvikRuntime vm;
  final oracle = jsonDecode(
    File('test/dalvik/fixtures/java_io_oracle.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaIo(vm);
  });
  DalvikArray bytes(List<int> values) {
    final b = vm.array('[B', values.length);
    for (var n = 0; n < values.length; n++) {
      b.values[n] = values[n].toSigned(8);
    }
    return b;
  }

  DalvikObject make(
    String type,
    String signature, [
    List<Object?> args = const [],
  ]) {
    final object = vm.allocate(type);
    vm.call('$type-><init>$signature', [object, ...args], kind: 'direct');
    return object;
  }

  Object? call(
    DalvikObject object,
    String owner,
    String signature, [
    List<Object?> args = const [],
  ]) => vm.call('$owner->$signature', [object, ...args], kind: 'virtual');
  List<Object?> wide(int value) {
    final r = <Object?>[0, 0];
    JBits.setWide(r, 0, value);
    return r;
  }

  Matcher javaError(String type) => throwsA(
    isA<DalvikThrown>().having(
      (e) => e.object.className,
      'Java exception type',
      type,
    ),
  );

  test(
    'byte array input shares array, retains mark, and close is specified no-op',
    () {
      final array = bytes([10, 20, 30, 40]);
      final s = make(byteInput, '([BII)V', [array, 1, 2]);
      final results = <Object?>[
        call(s, input, 'read()I'),
        call(s, input, 'available()I'),
      ];
      call(s, input, 'reset()V');
      results.add(call(s, input, 'read()I'));
      call(s, input, 'close()V');
      results.add(call(s, input, 'read()I'));
      results.add(call(s, input, 'read([B)I', [bytes([])]));
      results.add(call(s, input, 'available()I'));
      expect(results, oracle['byteInput']);
      call(s, input, 'reset()V');
      array.values[1] = -1;
      expect(call(s, input, 'read()I'), 255);
      expect(call(s, input, 'skip(J)J', wide(-2)), 0);
      expect(call(s, input, 'skip(J)J', wide(999)), 1);
      expect(
        () => call(s, input, 'read([BII)I', [array, -1, 0]),
        javaError('Ljava/lang/IndexOutOfBoundsException;'),
      );
    },
  );

  test(
    'data output exactly matches JVM big-endian, NaN and modified UTF-8 bytes',
    () {
      final sink = make(byteOutput, '()V');
      final s = make(dataOutput, '(Ljava/io/OutputStream;)V', [sink]);
      call(s, dataOutput, 'writeBoolean(Z)V', [1]);
      call(s, dataOutput, 'writeBoolean(Z)V', [0]);
      call(s, dataOutput, 'writeByte(I)V', [255]);
      call(s, dataOutput, 'writeShort(I)V', [-12345]);
      call(s, dataOutput, 'writeChar(I)V', [0xd834]);
      call(s, dataOutput, 'writeInt(I)V', [0x89abcdef.toSigned(32)]);
      call(s, dataOutput, 'writeLong(J)V', wide(0x8123456789abcdef));
      call(s, dataOutput, 'writeFloat(F)V', [0x80000000.toSigned(32)]);
      call(s, dataOutput, 'writeDouble(D)V', wide(-0x8000000000000000));
      call(s, dataOutput, 'writeFloat(F)V', [0xffa12345.toSigned(32)]);
      call(s, dataOutput, 'writeDouble(D)V', wide(0xfff123456789abcd));
      call(s, dataOutput, 'writeUTF(Ljava/lang/String;)V', [
        vm.newString('A\u0000é東😀\ud800'),
      ]);
      call(s, output, 'flush()V');
      final actual = call(sink, byteOutput, 'toByteArray()[B') as DalvikArray;
      expect(actual.values, oracle['data']);
      expect(call(s, dataOutput, 'size()I'), actual.values.length);
      actual.values[0] = 77;
      expect(
        (call(sink, byteOutput, 'toByteArray()[B') as DalvikArray).values[0],
        1,
      );
    },
  );

  test('data input reads JVM stream, signed widths, UTF-16 units, and EOF exceptions', () {
    final source = javaByteArrayInputStream(
      vm,
      (oracle['data'] as List<dynamic>).cast<int>(),
    );
    final s = make(dataInput, '(Ljava/io/InputStream;)V', [source]);
    expect(call(s, dataInput, 'readBoolean()Z'), 1);
    expect(call(s, dataInput, 'readBoolean()Z'), 0);
    expect(call(s, dataInput, 'readByte()B'), -1);
    expect(call(s, dataInput, 'readShort()S'), -12345);
    expect(call(s, dataInput, 'readChar()C'), 0xd834);
    expect(call(s, dataInput, 'readInt()I'), 0x89abcdef.toSigned(32));
    expect(call(s, dataInput, 'readLong()J'), 0x8123456789abcdef);
    expect(call(s, dataInput, 'readFloat()F'), -0x80000000);
    expect(call(s, dataInput, 'readDouble()D'), -0x8000000000000000);
    expect(call(s, dataInput, 'readFloat()F'), 0x7fc00000);
    expect(call(s, dataInput, 'readDouble()D'), 0x7ff8000000000000);
    expect(
      vm.string(call(s, dataInput, 'readUTF()Ljava/lang/String;')).codeUnits,
      'A\u0000é東😀\ud800'.codeUnits,
    );
    expect(
      () => call(s, dataInput, 'readUnsignedByte()I'),
      javaError('Ljava/io/EOFException;'),
    );
    expect(
      () => call(s, dataInput, 'readFully([B)V', [
        bytes([0]),
      ]),
      javaError('Ljava/io/EOFException;'),
    );
  });

  test(
    'buffered input expands a valid mark and invalidates an exhausted limit',
    () {
      final source = javaByteArrayInputStream(vm, List.generate(12, (i) => i));
      final s = make(
        'Ljava/io/BufferedInputStream;',
        '(Ljava/io/InputStream;I)V',
        [source, 2],
      );
      call(s, input, 'mark(I)V', [5]);
      expect(List.generate(5, (_) => call(s, input, 'read()I')), [
        0,
        1,
        2,
        3,
        4,
      ]);
      call(s, input, 'reset()V');
      expect(call(s, input, 'read()I'), 0);
      expect(call(s, input, 'skip(J)J', wide(4)), 4);
      expect(call(s, input, 'read()I'), 5);
      expect(
        () => call(s, input, 'reset()V'),
        javaError('Ljava/io/IOException;'),
      );
      call(s, input, 'close()V');
      expect(
        () => call(s, input, 'read()I'),
        javaError('Ljava/io/IOException;'),
      );
    },
  );

  test(
    'buffered output only exposes pending bytes on flush and preserves order',
    () {
      final sink = make(byteOutput, '()V');
      final s = make(
        'Ljava/io/BufferedOutputStream;',
        '(Ljava/io/OutputStream;I)V',
        [sink, 3],
      );
      call(s, output, 'write(I)V', [255]);
      call(s, output, 'write([B)V', [
        bytes([1]),
      ]);
      expect(call(sink, byteOutput, 'size()I'), 0);
      call(s, output, 'flush()V');
      expect(
        (call(sink, byteOutput, 'toByteArray()[B') as DalvikArray).values,
        [-1, 1],
      );
      call(s, output, 'write([B)V', [
        bytes([2, 3, 4, 5]),
      ]);
      call(s, output, 'close()V');
      expect(
        (call(sink, byteOutput, 'toByteArray()[B') as DalvikArray).values,
        [-1, 1, 2, 3, 4, 5],
      );
    },
  );

  test('CRC32 agrees with JVM and reset returns its initial value', () {
    final crc = make('Ljava/util/zip/CRC32;', '()V');
    call(crc, crc.className, 'update([B)V', [
      bytes((oracle['data'] as List<dynamic>).cast<int>()),
    ]);
    expect(call(crc, crc.className, 'getValue()J'), oracle['crc32']);
    call(crc, crc.className, 'reset()V');
    expect(call(crc, crc.className, 'getValue()J'), 0);
    for (final byte in utf8.encode('123456789')) {
      call(crc, crc.className, 'update(I)V', [byte]);
    }
    expect(call(crc, crc.className, 'getValue()J'), 0xcbf43926);
  });

  test('gzip constructor consumes only header; read validates and decodes JVM gzip', () {
    final compressed = (oracle['gzip'] as List<dynamic>).cast<int>();
    final source = javaByteArrayInputStream(vm, compressed);
    final s = make(
      'Ljava/util/zip/GZIPInputStream;',
      '(Ljava/io/InputStream;I)V',
      [source, 7],
    );
    expect(call(source, input, 'available()I'), compressed.length - 10);
    final actual = <int>[];
    while (true) {
      final n = call(s, input, 'read()I') as int;
      if (n < 0) break;
      actual.add(n);
    }
    expect(utf8.decode(actual), 'Granja original: maíz 🌽');
    expect(call(s, input, 'available()I'), 0);
    call(s, input, 'close()V');
    expect(() => call(s, input, 'read()I'), javaError('Ljava/io/IOException;'));
  });

  test(
    'original generated DEX gzip method executes through real stream bridges',
    () {
      registerClass171(vm);
      final result = vm.call('Lc/c/b/b/f/e;->a([B)Ljava/lang/String;', [
        bytes((oracle['gzip'] as List<dynamic>).cast<int>()),
      ], kind: 'static');
      expect(vm.string(result), 'Granja original: maíz 🌽');
      expect(vm.executedInstructions, 29);
    },
  );

  test('gzip rejects corrupt trailers and truncated streams instead of returning blanks', () {
    final compressed = (oracle['gzip'] as List<dynamic>)
        .cast<int>()
        .map((n) => n & 255)
        .toList();
    final corrupt = [...compressed]..[compressed.length - 8] ^= 1;
    void drain(List<int> bytes) {
      final source = javaByteArrayInputStream(vm, bytes);
      final s = make(
        'Ljava/util/zip/GZIPInputStream;',
        '(Ljava/io/InputStream;I)V',
        [source, 7],
      );
      final target = vm.array('[B', 3);
      while ((call(s, input, 'read([B)I', [target]) as int) >= 0) {}
    }

    expect(() => drain(corrupt), javaError('Ljava/util/zip/ZipException;'));
    expect(
      () => drain(compressed.sublist(0, compressed.length - 3)),
      javaError('Ljava/io/EOFException;'),
    );
  });

  test('InputStream default bulk read catches later IOException after a first byte', () {
    const type = 'Ltest/FailingInput;';
    vm.registerExternalClass(type, superclass: input);
    var index = 0;
    vm.registerNative('$type->read()I', (v, a) {
      if (index++ == 0) return 123;
      v.throwJava('Ljava/io/IOException;', 'source failure');
    });
    final s = vm.allocate(type), target = vm.array('[B', 8);
    expect(call(s, input, 'read([B)I', [target]), 1);
    expect(target.values[0], 123);
    expect(
      () => call(s, input, 'read([B)I', [target]),
      javaError('Ljava/io/IOException;'),
    );
  });

  test(
    'gzip validates stored/dynamic Huffman blocks and concatenated members',
    () {
      final first = List.generate(80000, (n) => (n * n + 17 * n) & 255);
      final second = List.generate(1000, (n) => n & 255);
      for (final level in [0, 1, 9]) {
        final compressed = [
          ...ZLibEncoder(gzip: true, level: level).convert(first),
          ...gzip.encode(second),
        ];
        expect(ZLibDecoder(gzip: true).convert(compressed), [
          ...first,
          ...second,
        ], reason: 'native decoder level $level');
        final s = make(
          'Ljava/util/zip/GZIPInputStream;',
          '(Ljava/io/InputStream;I)V',
          [javaByteArrayInputStream(vm, compressed), 31],
        );
        final target = vm.array('[B', 8192), actual = <int>[];
        while (true) {
          final n = call(s, input, 'read([B)I', [target]) as int;
          if (n < 0) break;
          actual.addAll(target.values.take(n).map((v) => (v as int) & 255));
        }
        expect(actual, [...first, ...second]);
      }
    },
  );

  test('resource loader applies Class-relative and absolute lookup with missing null', () {
    final paths = <String>[];
    vm.resourceLoader = (path) {
      paths.add(path);
      return path.endsWith('missing') ? null : [3, 4];
    };
    final clazz = vm.typeObject('Lcom/example/Game;');
    final relative = call(
      clazz,
      'Ljava/lang/Class;',
      'getResourceAsStream(Ljava/lang/String;)Ljava/io/InputStream;',
      [vm.newString('data')],
    ) as DalvikObject;
    expect(call(relative, input, 'read()I'), 3);
    call(
      clazz,
      'Ljava/lang/Class;',
      'getResourceAsStream(Ljava/lang/String;)Ljava/io/InputStream;',
      [vm.newString('/assets/map')],
    );
    expect(
      call(
        clazz,
        'Ljava/lang/Class;',
        'getResourceAsStream(Ljava/lang/String;)Ljava/io/InputStream;',
        [vm.newString('/missing')],
      ),
      isNull,
    );
    expect(paths, ['com/example/data', 'assets/map', 'missing']);
    vm.resourceLoader = null;
    expect(
      () => call(
        clazz,
        'Ljava/lang/Class;',
        'getResourceAsStream(Ljava/lang/String;)Ljava/io/InputStream;',
        [vm.newString('/data')],
      ),
      throwsA(isA<MissingDalvikBridge>()),
    );
  });
}
