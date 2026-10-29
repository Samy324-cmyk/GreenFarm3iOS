import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/java_collections.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_files.dart';
import 'package:green_farm_port/engine/dalvik/java_io.dart';
import 'package:green_farm_port/engine/dalvik/java_zip.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/engine/storage/binary.dart' show crc32;

const zip = 'Ljava/util/zip/ZipFile;';
const entry = 'Ljava/util/zip/ZipEntry;';
const enumeration = 'Ljava/util/Enumeration;';
const input = 'Ljava/io/InputStream;';

void main() {
  final fixture = File('test/fixtures/dalvik/zip_fixture.zip')
      .readAsBytesSync();
  final payloads = jsonDecode(
    File('test/fixtures/dalvik/zip_fixture.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final apk = File('assets/provenance/original.apk').readAsBytesSync();
  final oracle = jsonDecode(
    File('test/fixtures/dalvik/zip_original_apk.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  late DalvikRuntime vm;
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaCollections(vm);
    registerJavaIo(vm);
    registerJavaFiles(vm, workingDirectory: Directory.current.path);
    registerJavaZip(vm, workingDirectory: Directory.current.path);
  });
  DalvikObject open(String name) {
    final object = vm.allocate(zip);
    vm.call('$zip-><init>(Ljava/lang/String;)V', [
      object,
      vm.intern(name),
    ], kind: 'direct');
    return object;
  }

  Object? call(
    DalvikObject object,
    String owner,
    String signature, [
    List<Object?> args = const [],
  ]) => vm.call('$owner->$signature', [object, ...args], kind: 'virtual');
  DalvikObject? lookup(DalvikObject object, String name) => call(
    object,
    zip,
    'getEntry(Ljava/lang/String;)Ljava/util/zip/ZipEntry;',
    [vm.intern(name)],
  ) as DalvikObject?;
  Matcher javaError(String name) => throwsA(
    isA<DalvikThrown>().having(
      (e) => e.object.className,
      'Java exception',
      'Ljava/$name;',
    ),
  );
  int centralEntry(Uint8List bytes, int index) {
    var offset = JavaZipArchive.parse(bytes).centralOffset;
    final data = ByteData.sublistView(bytes);
    for (var n = 0; n < index; n++) {
      offset +=
          46 +
          data.getUint16(offset + 28, Endian.little) +
          data.getUint16(offset + 30, Endian.little) +
          data.getUint16(offset + 32, Endian.little);
    }
    return offset;
  }

  test('all 1134 original APK entries match independent Python metadata and SHA256', () {
    expect(apk.length, oracle['source_apk_bytes']);
    expect(sha256.convert(apk).toString(), oracle['source_apk_sha256']);
    final archive = JavaZipArchive.parse(apk);
    final expected = oracle['entries'] as List<dynamic>;
    expect(archive.entries.length, 1134);
    expect(archive.entries.length, expected.length);
    for (var n = 0; n < expected.length; n++) {
      final info = expected[n] as Map<String, dynamic>;
      final actual = archive.entries[n];
      expect(
        [
          actual.name,
          actual.size,
          actual.compressedSize,
          actual.crc,
          actual.method,
          actual.flags,
          actual.localOffset,
        ],
        [
          info['name'],
          info['size'],
          info['compressed_size'],
          info['crc'],
          info['method'],
          info['flags'],
          info['offset'],
        ],
        reason: info['name'] as String,
      );
      final decoded = archive.read(actual);
      expect(
        sha256.convert(decoded).toString(),
        info['sha256'],
        reason: actual.name,
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'original integrity enumeration measures all three actual DEX entries',
    () {
      final archive = open('assets/provenance/original.apk');
      expect(call(archive, zip, 'size()I'), 1134);
      final cursor = call(
        archive,
        zip,
        'entries()Ljava/util/Enumeration;',
      ) as DalvikObject;
      final sizes = <String, int>{};
      while (vm.call('$enumeration->hasMoreElements()Z', [
            cursor,
          ], kind: 'interface') ==
          1) {
        final item = vm.call('$enumeration->nextElement()Ljava/lang/Object;', [
          cursor,
        ], kind: 'interface') as DalvikObject;
        final name = vm.string(
          call(item, entry, 'getName()Ljava/lang/String;'),
        );
        if (name.endsWith('.dex')) {
          sizes[name] = call(item, entry, 'getSize()J') as int;
        }
      }
      expect(sizes, {
        'classes.dex': 9362740,
        'classes2.dex': 7620072,
        'assets/audience_network.dex': 3316236,
      });
      expect(sizes.values.reduce((a, b) => a + b), 20299048);
      final classes = lookup(archive, 'classes.dex')!;
      expect(call(classes, entry, 'getSize()J'), 9362740);
      expect(call(classes, entry, 'getCrc()J'), 2768139328);
      call(archive, zip, 'close()V');
    },
  );

  test(
    'stored, deflated, Unicode, BOM names and directory entries retain bytes',
    () {
      final archive = JavaZipArchive.parse(fixture);
      expect(archive.entries.map((e) => e.name), payloads.keys);
      expect(archive.comment, 'archive comment PK\x05\x06 false signature');
      for (final item in archive.entries) {
        expect(archive.read(item), payloads[item.name]);
      }
      expect(archive.getEntry('dir')!.name, 'dir/');
      expect(archive.getEntry('absent'), isNull);
    },
  );

  test('data descriptor entries use actual central-directory metadata', () {
    final archive = JavaZipArchive.parse(
      File('test/fixtures/dalvik/zip_descriptor_fixture.zip').readAsBytesSync(),
    );
    expect(archive.entries.single.flags & 8, 8);
    expect(
      utf8.decode(archive.read(archive.entries.single)),
      List.filled(50, 'actual data descriptor bytes').join(),
    );
  });

  test('duplicate entry names are rejected as on Android', () {
    expect(
      () => JavaZipArchive.parse(
        File('test/fixtures/dalvik/zip_duplicate_fixture.zip')
            .readAsBytesSync(),
      ),
      throwsFormatException,
    );
  });

  test(
    'truncated central directories, ZIP64 and spanned archives fail explicitly',
    () {
      expect(
        () => JavaZipArchive.parse(
          Uint8List.sublistView(fixture, 0, fixture.length - 2),
        ),
        throwsFormatException,
      );
      final zip64 = Uint8List.fromList(fixture);
      final end =
          JavaZipArchive.parse(zip64).centralOffset +
          fixture.length -
          JavaZipArchive.parse(zip64).centralOffset -
          22 -
          utf8.encode('archive comment PK\x05\x06 false signature').length;
      ByteData.sublistView(zip64).setUint16(end + 10, 65535, Endian.little);
      expect(() => JavaZipArchive.parse(zip64), throwsFormatException);
      final spanned = Uint8List.fromList(fixture);
      ByteData.sublistView(spanned).setUint16(end + 4, 1, Endian.little);
      expect(() => JavaZipArchive.parse(spanned), throwsFormatException);
    },
  );

  test('encrypted flags and NUL names are rejected', () {
    final encrypted = Uint8List.fromList(fixture);
    final central = centralEntry(encrypted, 0);
    ByteData.sublistView(encrypted).setUint16(central + 8, 1, Endian.little);
    expect(() => JavaZipArchive.parse(encrypted), throwsFormatException);
    final nul = Uint8List.fromList(fixture);
    nul[central + 46] = 0;
    expect(() => JavaZipArchive.parse(nul), throwsFormatException);
  });

  test('unsupported compression is never returned as fabricated bytes', () {
    final unsupported = Uint8List.fromList(fixture);
    ByteData.sublistView(unsupported)
        .setUint16(centralEntry(unsupported, 0) + 10, 99, Endian.little);
    final archive = JavaZipArchive.parse(unsupported);
    expect(() => archive.read(archive.entries.first), throwsFormatException);
  });

  test('bad local header, CRC, sizes and compressed bounds fail', () {
    for (final field in ['header', 'crc', 'size', 'bounds']) {
      final changed = Uint8List.fromList(fixture);
      final central = centralEntry(changed, 0);
      final data = ByteData.sublistView(changed);
      if (field == 'header') changed[0] ^= 1;
      if (field == 'crc') changed[central + 16] ^= 1;
      if (field == 'size') data.setUint32(central + 24, 1, Endian.little);
      if (field == 'bounds') {
        data.setUint32(central + 20, fixture.length, Endian.little);
      }
      expect(
        () {
          final archive = JavaZipArchive.parse(changed);
          archive.read(archive.entries.first);
        },
        throwsFormatException,
        reason: field,
      );
    }
  });

  test('raw inflate validates final block, CRC, size and trailing bytes', () {
    final plain = utf8.encode('Strict raw DEFLATE fixture ' * 20);
    final compressed = ZLibEncoder(raw: true).convert(plain);
    expect(
      javaInflateRaw(compressed, crc32: crc32(plain), size: plain.length),
      plain,
    );
    expect(
      () => javaInflateRaw(
        compressed.sublist(0, compressed.length - 1),
        crc32: crc32(plain),
        size: plain.length,
      ),
      throwsFormatException,
    );
    expect(
      () => javaInflateRaw(
        [...compressed, 0],
        crc32: crc32(plain),
        size: plain.length,
      ),
      throwsFormatException,
    );
    expect(
      () => javaInflateRaw(compressed, crc32: 0, size: plain.length),
      throwsFormatException,
    );
    expect(
      () => javaInflateRaw(
        compressed,
        crc32: crc32(plain),
        size: plain.length - 1,
      ),
      throwsFormatException,
    );
  });

  test('native input stream exposes actual bytes and handles close', () {
    final archive = open('test/fixtures/dalvik/zip_fixture.zip');
    final item = lookup(archive, 'stored.txt')!;
    final stream = call(
      archive,
      zip,
      'getInputStream(Ljava/util/zip/ZipEntry;)Ljava/io/InputStream;',
      [item],
    ) as DalvikObject;
    final expected = payloads['stored.txt'] as List<dynamic>;
    expect(call(stream, input, 'available()I'), expected.length);
    expect(call(stream, input, 'read()I'), expected.first);
    final buffer = vm.array('[B', expected.length + 3);
    expect(
      call(stream, input, 'read([BII)I', [buffer, 2, expected.length - 1]),
      expected.length - 1,
    );
    expect(
      buffer.values
          .skip(2)
          .take(expected.length - 1)
          .map((v) => (v as int) & 255),
      expected.skip(1),
    );
    expect(call(stream, input, 'read()I'), -1);
    expect(
      () => call(stream, input, 'read([BII)I', [buffer, -1, 1]),
      javaError('lang/IndexOutOfBoundsException'),
    );
    call(stream, input, 'close()V');
    expect(call(stream, input, 'available()I'), 0);
    expect(() => call(stream, input, 'read()I'), javaError('io/IOException'));
  });

  test('closing ZipFile invalidates existing enumeration and entry stream', () {
    final archive = open('test/fixtures/dalvik/zip_fixture.zip');
    final item = lookup(archive, 'stored.txt')!;
    final stream = call(
      archive,
      zip,
      'getInputStream(Ljava/util/zip/ZipEntry;)Ljava/io/InputStream;',
      [item],
    ) as DalvikObject;
    final cursor =
        call(archive, zip, 'entries()Ljava/util/Enumeration;') as DalvikObject;
    call(archive, zip, 'close()V');
    call(archive, zip, 'close()V');
    expect(
      () => call(archive, zip, 'size()I'),
      javaError('lang/IllegalStateException'),
    );
    expect(
      () => vm.call('$enumeration->hasMoreElements()Z', [
        cursor,
      ], kind: 'interface'),
      javaError('lang/IllegalStateException'),
    );
    expect(() => call(stream, input, 'read()I'), javaError('io/IOException'));
    expect(
      vm.string(call(item, entry, 'getName()Ljava/lang/String;')),
      'stored.txt',
    );
    expect(
      vm.string(call(archive, zip, 'getName()Ljava/lang/String;')),
      'test/fixtures/dalvik/zip_fixture.zip',
    );
  });

  test(
    'directory fallback, null inputs, foreign entry names and missing files',
    () {
      final archive = open('test/fixtures/dalvik/zip_fixture.zip');
      expect(call(lookup(archive, 'dir')!, entry, 'isDirectory()Z'), 1);
      expect(lookup(archive, 'absent'), isNull);
      expect(
        () => call(
          archive,
          zip,
          'getEntry(Ljava/lang/String;)Ljava/util/zip/ZipEntry;',
          [null],
        ),
        javaError('lang/NullPointerException'),
      );
      final foreign = vm.allocate(entry);
      vm.call('$entry-><init>(Ljava/lang/String;)V', [
        foreign,
        vm.intern('absent'),
      ], kind: 'direct');
      expect(call(foreign, entry, 'getSize()J'), -1);
      expect(
        call(
          archive,
          zip,
          'getInputStream(Ljava/util/zip/ZipEntry;)Ljava/io/InputStream;',
          [foreign],
        ),
        isNull,
      );
      expect(
        () => open('test/fixtures/dalvik/does-not-exist.zip'),
        javaError('io/FileNotFoundException'),
      );
    },
  );

  test(
    'all seven original ZIP references plus byte streams have native bridges',
    () {
      const signatures = [
        '$entry->getName()Ljava/lang/String;',
        '$entry->getSize()J',
        '$zip-><init>(Ljava/lang/String;)V',
        '$zip->close()V',
        '$zip->entries()Ljava/util/Enumeration;',
        '$zip->getEntry(Ljava/lang/String;)Ljava/util/zip/ZipEntry;',
        '$zip->size()I',
      ];
      // Seven direct DEX references; getInputStream is provided and tested too.
      for (final key in [
        ...signatures,
        '$zip->getInputStream(Ljava/util/zip/ZipEntry;)Ljava/io/InputStream;',
      ]) {
        expect(vm.nativeMethods.containsKey(key), isTrue, reason: key);
      }
    },
  );
}
