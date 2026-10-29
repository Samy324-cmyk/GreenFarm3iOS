import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/engine/dalvik/java_parse_decimal.dart';

void main() {
  late DalvikRuntime vm;
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
  });
  Object? call(
    String owner,
    String method,
    List<Object?> args, {
    String kind = 'virtual',
  }) => vm.call('$owner->$method', args, kind: kind);
  Object? stat(String owner, String method, List<Object?> args) =>
      call(owner, method, args, kind: 'static');
  const s = 'Ljava/lang/String;',
      o = 'Ljava/lang/Object;',
      integer = 'Ljava/lang/Integer;',
      system = 'Ljava/lang/System;';
  Matcher javaError(String name) => isA<DalvikThrown>().having(
    (e) => e.object.className,
    'Java exception',
    'Ljava/lang/$name;',
  );
  List<Object?> wide(int value) => <Object?>[
    value.toSigned(32),
    (value >> 32).toSigned(32),
  ];
  DalvikObject construct(String owner, String signature, List<Object?> args) {
    final value = vm.allocate(owner);
    call(owner, '<init>$signature', [value, ...args], kind: 'direct');
    return value;
  }

  DalvikArray array(String descriptor, List<Object?> values) =>
      vm.array(descriptor, values.length)..values.setAll(0, values);
  test(
    'String identity, intern, UTF-16 indexing, hashing and range errors',
    () {
      final value = vm.newString('A😀é'), twin = vm.newString('A😀é');
      expect(call(s, 'length()I', [value]), 4);
      expect(call(s, 'charAt(I)C', [value, 1]), 0xd83d);
      expect(call(s, 'charAt(I)C', [value, 2]), 0xde00);
      expect(call(s, 'equals(Ljava/lang/Object;)Z', [value, twin]), 1);
      expect(
        call(o, 'equals(Ljava/lang/Object;)Z', [value, twin], kind: 'direct'),
        0,
      );
      expect(call(s, 'hashCode()I', [value]), 56896517);
      expect(call(s, 'toString()Ljava/lang/String;', [value]), same(value));
      expect(
        call(s, 'substring(II)Ljava/lang/String;', [value, 0, 4]),
        same(value),
      );
      expect(
        call(s, 'intern()Ljava/lang/String;', [value]),
        same(call(s, 'intern()Ljava/lang/String;', [twin])),
      );
      expect(
        () => call(s, 'charAt(I)C', [value, 4]),
        throwsA(javaError('StringIndexOutOfBoundsException')),
      );
      expect(
        vm
            .string(call(s, 'substring(II)Ljava/lang/String;', [value, 1, 2]))
            .codeUnits,
        [0xd83d],
      );
    },
  );
  test('String searches respect Java negative and oversized indices', () {
    final value = vm.newString('abcabc😀');
    expect(
      call(s, 'indexOf(Ljava/lang/String;I)I', [
        value,
        vm.newString('abc'),
        -8,
      ]),
      0,
    );
    expect(
      call(s, 'indexOf(Ljava/lang/String;I)I', [value, vm.newString(''), 99]),
      8,
    );
    expect(
      call(s, 'lastIndexOf(Ljava/lang/String;I)I', [
        value,
        vm.newString(''),
        -1,
      ]),
      -1,
    );
    expect(call(s, 'indexOf(I)I', [value, 0x1f600]), 6);
    expect(call(s, 'indexOf(I)I', [value, 0x110000]), -1);
    expect(
      vm.string(
        call(s, 'trim()Ljava/lang/String;', [
          vm.newString('\u0000\t x \n\u0020'),
        ]),
      ),
      'x',
    );
    expect(
      vm.string(
        call(s, 'trim()Ljava/lang/String;', [vm.newString('\u00a0x\u00a0')]),
      ),
      '\u00a0x\u00a0',
    );
  });
  test('Case mapping and comparison use Java Unicode data and locale', () {
    final value = vm.newString('Iİıi Straße ΟΣ');
    expect(
      () => call(s, 'toLowerCase()Ljava/lang/String;', [value]),
      throwsA(isA<MissingDalvikBridge>()),
    );
    vm.defaultLocaleLanguage = 'en';
    expect(
      vm.string(call(s, 'toLowerCase()Ljava/lang/String;', [value])),
      'ii\u0307ıi straße ος',
    );
    expect(
      vm.string(call(s, 'toUpperCase()Ljava/lang/String;', [value])),
      'IİII STRASSE ΟΣ',
    );
    vm.defaultLocaleLanguage = 'tr';
    expect(
      vm.string(call(s, 'toLowerCase()Ljava/lang/String;', [value])),
      'ıiıi straße ος',
    );
    for (final pair in [
      ['İ', 'i'],
      ['ı', 'I'],
      ['Σ', 'ς'],
    ]) {
      expect(
        call(s, 'equalsIgnoreCase(Ljava/lang/String;)Z', [
          vm.newString(pair[0]),
          vm.newString(pair[1]),
        ]),
        1,
      );
    }
  });
  test('Builder consumes wide registers correctly and mutates text', () {
    const owner = 'Ljava/lang/StringBuilder;';
    final b = construct(owner, '()V', []);
    call(owner, 'append(J)$owner', [b, ...wide(-9223372036854775807)]);
    call(owner, 'append(C)$owner', [b, 33]);
    call(owner, 'append(Ljava/lang/String;)$owner', [b, null]);
    expect(
      vm.string(call(owner, 'toString()Ljava/lang/String;', [b])),
      '-9223372036854775807!null',
    );
    call(owner, 'delete(II)$owner', [b, 0, 19]);
    call(owner, 'setLength(I)V', [b, 8]);
    expect(
      vm.string(call(owner, 'toString()Ljava/lang/String;', [b])),
      '7!null\u0000\u0000',
    );
  });
  test(
    'Numeric wrappers cache values, preserve signed zero and canonical NaN',
    () {
      final a = stat(integer, 'valueOf(I)$integer', [127]),
          b = stat(integer, 'valueOf(I)$integer', [127]);
      expect(a, same(b));
      expect(
        stat(integer, 'valueOf(I)$integer', [128]),
        isNot(same(stat(integer, 'valueOf(I)$integer', [128]))),
      );
      const f = 'Ljava/lang/Float;';
      final n1 = stat(f, 'valueOf(F)$f', [0x7fc00001]),
          n2 = stat(f, 'valueOf(F)$f', [0x7fc00002]);
      expect(call(f, 'equals(Ljava/lang/Object;)Z', [n1, n2]), 1);
      expect(call(f, 'hashCode()I', [n1]), call(f, 'hashCode()I', [n2]));
      final zero = stat(f, 'valueOf(F)$f', [0]),
          negZero = stat(f, 'valueOf(F)$f', [-2147483648]);
      expect(call(f, 'equals(Ljava/lang/Object;)Z', [zero, negZero]), 0);
      expect(call(f, 'compareTo(Ljava/lang/Float;)I', [negZero, zero]), -1);
    },
  );
  test(
    'Integer parsing rejects overflow, accepts Unicode digits and radices',
    () {
      expect(
        stat(integer, 'parseInt(Ljava/lang/String;)I', [
          vm.newString('-2147483648'),
        ]),
        -2147483648,
      );
      expect(
        stat(integer, 'parseInt(Ljava/lang/String;)I', [vm.newString('١٢٣')]),
        123,
      );
      expect(
        stat(integer, 'parseInt(Ljava/lang/String;I)I', [
          vm.newString('ＦＦ'),
          16,
        ]),
        255,
      );
      for (final invalid in [
        '2147483648',
        '-2147483649',
        ' 1',
        '1 ',
        '0x10',
        '+',
        '',
      ]) {
        expect(
          () => stat(integer, 'parseInt(Ljava/lang/String;)I', [
            vm.newString(invalid),
          ]),
          throwsA(javaError('NumberFormatException')),
        );
      }
      expect(
        () => stat(integer, 'parseInt(Ljava/lang/String;)I', [null]),
        throwsA(javaError('NumberFormatException')),
      );
      expect(
        stat('Ljava/lang/Long;', 'parseLong(Ljava/lang/String;)J', [
          vm.newString('-9223372036854775808'),
        ]),
        -9223372036854775808,
      );
    },
  );
  test(
    'Floating parsing rounds directly to binary32 and supports hex literals',
    () {
      expect(
        javaParseFloatingBits('1.0000000596046448', single: true),
        0x3f800001,
      );
      expect(
        javaParseFloatingBits('1.000000059604644775390625', single: true),
        0x3f800000,
      );
      expect(javaParseFloatingBits('0x1.fffffep127', single: true), 0x7f7fffff);
      expect(javaParseFloatingBits('-0x1p-150', single: true), -2147483648);
      expect(javaParseFloatingBits('0x1.0p-1074', single: false), 1);
      expect(
        javaParseFloatingBits('4.9406564584124654e-324', single: false),
        1,
      );
      for (final bad in ['NaNf', 'infinity', '1_0', '0x12', '1e', '']) {
        expect(javaParseFloatingBits(bad, single: false), null);
      }
    },
  );
  test('Java 8 oracle: 20,024 float/double strings and parse roundtrips', () {
    final data = jsonDecode(
      File('test/dalvik/fixtures/core_numbers.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final type in ['float', 'double']) {
      final single = type == 'float',
          owner = type == 'float' ? 'Ljava/lang/Float;' : 'Ljava/lang/Double;';
      for (final entry in data[type] as List) {
        final bits = BigInt.parse(
          entry[0] as String,
          radix: 16,
        ).toSigned(single ? 32 : 64).toInt();
        final text = entry[1] as String;
        expect(
          vm.string(
            stat(
              owner,
              'toString(${single ? 'F' : 'D'})Ljava/lang/String;',
              single ? [bits] : wide(bits),
            ),
          ),
          text,
          reason: '$type ${entry[0]}',
        );
        final parsed = javaParseFloatingBits(text, single: single);
        expect(
          parsed,
          text == 'NaN' ? (single ? 0x7fc00000 : 0x7ff8000000000000) : bits,
          reason: 'parse $text',
        );
      }
    }
  });
  test('Java charset oracle: encoders and malformed decoders', () {
    final data = jsonDecode(
      File('test/dalvik/fixtures/core_charsets.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final row in data['encode'] as List) {
      final value = vm.newString(
        String.fromCharCodes((row[0] as List).cast<int>()),
      );
      final result = vm.asArray(
        call(s, 'getBytes(Ljava/lang/String;)[B', [
          value,
          vm.newString(row[1] as String),
        ]),
      );
      expect(
        result.values.map((b) => (b as int) & 255).toList(),
        row[2],
        reason: 'encode ${row[0]} ${row[1]}',
      );
    }
    for (final row in data['decode'] as List) {
      final bytes = array(
        '[B',
        (row[0] as List).cast<int>().map((v) => v.toSigned(8)).toList(),
      );
      final value = construct(s, '([BLjava/lang/String;)V', [
        bytes,
        vm.newString(row[1] as String),
      ]);
      expect(
        vm.string(value).codeUnits,
        row[2],
        reason: 'decode ${row[0]} ${row[1]}',
      );
    }
  });
  test('arraycopy overlap, primitive mismatch and reference partial copy', () {
    final ints = array('[I', [1, 2, 3, 4]);
    stat(system, 'arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V', [
      ints,
      0,
      ints,
      1,
      3,
    ]);
    expect(ints.values, [1, 1, 2, 3]);
    expect(
      () => stat(
        system,
        'arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V',
        [ints, -1, vm.array('[B', 4), 0, 1],
      ),
      throwsA(javaError('ArrayStoreException')),
    );
    expect(
      () => stat(
        system,
        'arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V',
        [ints, -1, ints, 0, 1],
      ),
      throwsA(javaError('ArrayIndexOutOfBoundsException')),
    );
    final text = vm.newString('first'),
        source = array('[Ljava/lang/Object;', [text, vm.allocate(o)]),
        destination = vm.array('[Ljava/lang/String;', 2);
    expect(
      () => stat(
        system,
        'arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V',
        [source, 0, destination, 0, 2],
      ),
      throwsA(javaError('ArrayStoreException')),
    );
    expect(destination.values, [text, null]);
  });
  test('System clocks and random seed require injected platform values', () {
    expect(
      () => stat(system, 'currentTimeMillis()J', []),
      throwsA(isA<MissingDalvikBridge>()),
    );
    vm.wallClockMillis = () => 1777777777777;
    expect(stat(system, 'currentTimeMillis()J', []), 1777777777777);
    expect(
      stat(
        system,
        'setProperty(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
        [vm.newString('x'), vm.newString('a')],
      ),
      null,
    );
    expect(
      vm.string(
        stat(system, 'getProperty(Ljava/lang/String;)Ljava/lang/String;', [
          vm.newString('x'),
        ]),
      ),
      'a',
    );
    const random = 'Ljava/util/Random;';
    expect(
      () => construct(random, '()V', []),
      throwsA(isA<MissingDalvikBridge>()),
    );
    final rng = construct(random, '(J)V', wide(0));
    expect(call(random, 'nextLong()J', [rng]), -4962768465676381896);
    call(random, 'setSeed(J)V', [rng, ...wide(0)]);
    expect(call(random, 'nextInt()I', [rng]), -1155484576);
    expect(
      () => call(random, 'nextInt(I)I', [rng, 0]),
      throwsA(javaError('IllegalArgumentException')),
    );
  });
  test('Class metadata, multidimensional arrays and Throwable diagnostics', () {
    const c = 'Ljava/lang/Class;';
    expect(
      stat(c, 'forName(Ljava/lang/String;)Ljava/lang/Class;', [
        vm.newString('java.lang.String'),
      ]),
      same(vm.typeObject(s)),
    );
    expect(
      stat(c, 'forName(Ljava/lang/String;)Ljava/lang/Class;', [
        vm.newString('[[I'),
      ]),
      same(vm.typeObject('[[I')),
    );
    expect(
      () => stat(c, 'forName(Ljava/lang/String;)Ljava/lang/Class;', [
        vm.newString('missing.Type'),
      ]),
      throwsA(javaError('ClassNotFoundException')),
    );
    vm.availableClassNames.add('Lgame/Unported;');
    expect(
      () => stat(c, 'forName(Ljava/lang/String;)Ljava/lang/Class;', [
        vm.newString('game.Unported'),
      ]),
      throwsA(isA<MissingDalvikBridge>()),
    );
    expect(
      call(c, 'isAssignableFrom(Ljava/lang/Class;)Z', [
        vm.typeObject(o),
        vm.typeObject(s),
      ]),
      1,
    );
    expect(
      call(c, 'isAssignableFrom(Ljava/lang/Class;)Z', [
        vm.typeObject(o),
        vm.typeObject('I'),
      ]),
      0,
    );
    final result = vm.asArray(
      stat(
        'Ljava/lang/reflect/Array;',
        'newInstance(Ljava/lang/Class;[I)Ljava/lang/Object;',
        [
          vm.typeObject('I'),
          array('[I', [2, 3]),
        ],
      ),
    );
    expect(result.className, '[[I');
    expect(result.values.length, 2);
    expect(vm.asArray(result.values.first).values, [0, 0, 0]);
    expect(
      vm.instanceOf(
        vm.allocate('Ljava/lang/NumberFormatException;'),
        'Ljava/lang/RuntimeException;',
      ),
      true,
    );
    final error = construct('Ljava/lang/Exception;', '(Ljava/lang/String;)V', [
      vm.newString('actual failure'),
    ]);
    vm.throwableTraces[error] = ['LGame;->start()V'];
    call('Ljava/lang/Throwable;', 'printStackTrace()V', [error]);
    expect(
      vm.diagnostics.single,
      'java.lang.Exception: actual failure\n\tat LGame;->start()V',
    );
  });
}
