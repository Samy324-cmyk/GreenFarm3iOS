import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/compat/java_numbers.dart';
import 'package:green_farm_port/engine/dalvik/numbers.dart';

void main() {
  test('Dalvik arithmetic, casts and comparisons match independent JVM vectors', () {
    final oracle = jsonDecode(
      File('test/dalvik/fixtures/numbers_oracle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final vectors = oracle['vectors'] as List<dynamic>;
    expect(vectors.length, greaterThan(40000));
    for (final item in vectors) {
      final v = item as List<dynamic>;
      final r = <Object?>[0, 0, v[2], v[3], v[4], v[5]];
      final opcode = v[1] as int;
      void execute() {
        switch (v[0]) {
          case 'u':
            JBits.unary(opcode, r, 0, 2);
          case 'b':
            JBits.binary(opcode, r, 0, 2, 4);
          case 'c':
            r[0] = JBits.compare(opcode, r, 2, 4);
        }
      }

      final context =
          'opcode=${opcode.toRadixString(16)} a=${v[2]},${v[3]} b=${v[4]},${v[5]}';
      if (v[6] == 'exception') {
        expect(
          execute,
          throwsA(isA<JavaArithmeticException>()),
          reason: context,
        );
        continue;
      }
      execute();
      if (v[9] == true) {
        expect(
          v[6] == 'f' ? JBits.float(r, 0).isNaN : JBits.doubleValue(r, 0).isNaN,
          isTrue,
          reason: context,
        );
      } else {
        expect(r[0], v[7], reason: context);
        if (v[6] == 'j' || v[6] == 'd') expect(r[1], v[8], reason: context);
      }
    }
  });

  test(
    'wide values permit unaligned and overlapping register destinations',
    () {
      final r = List<Object?>.filled(6, 0);
      JBits.setWide(r, 1, 0x123456789abcdef);
      expect(JBits.wide(r, 1), 0x123456789abcdef);
      JBits.unary(0x7d, r, 2, 1);
      expect(JBits.wide(r, 2), -0x123456789abcdef);
      JBits.setDouble(r, 1, -0.0);
      expect(JBits.wide(r, 1), -0x8000000000000000);
      JBits.unary(0x80, r, 2, 1);
      expect(JBits.wide(r, 2), 0);
    },
  );

  test('unknown arithmetic opcodes throw explicit errors', () {
    final r = List<Object?>.filled(6, 0);
    expect(() => JBits.unary(0x90, r, 0, 2), throwsUnsupportedError);
    expect(() => JBits.binary(0xb0, r, 0, 2, 4), throwsUnsupportedError);
    expect(() => JBits.compare(0x32, r, 2, 4), throwsUnsupportedError);
  });
}
