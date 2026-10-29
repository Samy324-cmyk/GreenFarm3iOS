import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/compat/java_numbers.dart';
import 'package:green_farm_port/engine/compat/java_random.dart';

void main() {
  final vectors = jsonDecode(
    File('test/fixtures/compat/java_random.json').readAsStringSync(),
  ) as List<dynamic>;
  for (final raw in vectors) {
    final vector = raw as Map<String, dynamic>;
    final seed = vector['seed'] as int;
    group('JDK oracle seed=$seed', () {
      test('unbounded int sequence', () {
        final random = JavaRandom(seed);
        expect(List.generate(20, (_) => random.nextInt()), vector['ints']);
      });
      test('bounded sequence with rejection sampling', () {
        final random = JavaRandom(seed);
        final bounds = (vector['bounds'] as List).cast<int>();
        expect(
          List.generate(60, (i) => random.nextInt(bounds[i % bounds.length])),
          vector['bounded'],
        );
      });
      test('64-bit signed draws', () {
        final random = JavaRandom(seed);
        expect(List.generate(20, (_) => random.nextLong()), vector['longs']);
      });
      test('bytes preserve Java batching and sign shifts', () {
        final actual = JavaRandom(seed).nextBytes(37);
        expect(
          actual.map((n) => n.toRadixString(16).padLeft(2, '0')).join(),
          vector['bytes'],
        );
      });
      test('double and float exact IEEE-754 bit patterns', () {
        final random = JavaRandom(seed);
        expect(
          List.generate(20, (_) {
            final bytes = ByteData(8)
              ..setFloat64(0, random.nextDouble(), Endian.little);
            return bytes.getInt64(0, Endian.little);
          }),
          vector['doubleBits'],
        );
        random.setSeed(seed);
        expect(
          List.generate(20, (_) => JavaNumbers.floatBits(random.nextFloat())),
          vector['floatBits'],
        );
      });
      test('original GLLib.i3 sequence', () {
        final random = JavaRandom(seed);
        expect(
          List.generate(20, (_) => random.gameRange(-30, 200)),
          vector['gameRange'],
        );
      });
    });
  }

  test('game range equal bounds does not consume entropy', () {
    final random = JavaRandom(0);
    expect(random.gameRange(7, 7), 7);
    expect(random.nextInt(), JavaRandom(0).nextInt());
  });
  test('invalid bounds and byte lengths fail', () {
    expect(() => JavaRandom(0).nextInt(0), throwsArgumentError);
    expect(() => JavaRandom(0).nextInt(-1), throwsArgumentError);
    expect(() => JavaRandom(0).nextInt(0x80000000), throwsArgumentError);
    expect(() => JavaRandom(0).nextBytes(-1), throwsRangeError);
  });
}
