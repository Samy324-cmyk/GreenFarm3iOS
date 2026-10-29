import 'dart:typed_data';

import 'java_numbers.dart';

/// java.util.Random's 48-bit LCG, with Java integer overflow and draw order.
/// A seed is mandatory so clocks remain an explicit platform dependency.
class JavaRandom {
  JavaRandom(int seed) {
    setSeed(seed);
  }

  static const _multiplier = 0x5deece66d;
  static const _addend = 0xb;
  static const _mask = (1 << 48) - 1;
  int _seed = 0;

  void setSeed(int seed) {
    _seed = (seed ^ _multiplier) & _mask;
  }

  int _next(int bits) {
    _seed = (_seed * _multiplier + _addend) & _mask;
    return (_seed >> (48 - bits)).toSigned(32);
  }

  int nextInt([int? bound]) {
    if (bound == null) return _next(32);
    if (bound <= 0 || bound > 0x7fffffff) {
      throw ArgumentError.value(bound, 'bound', 'Must be a positive Java int');
    }
    if ((bound & -bound) == bound) {
      return (bound * _next(31)) >> 31;
    }
    int bits;
    int value;
    do {
      bits = _next(31);
      value = bits % bound;
    } while ((bits - value + bound - 1).toSigned(32) < 0);
    return value;
  }

  int nextLong() => (_next(32) << 32) + _next(32);
  bool nextBoolean() => _next(1) != 0;
  double nextFloat() => _next(24) / (1 << 24);
  double nextDouble() => ((_next(26) << 27) + _next(27)) / (1 << 53);

  Uint8List nextBytes(int length) {
    if (length < 0) throw RangeError.value(length, 'length');
    final output = Uint8List(length);
    var index = 0;
    while (index < length) {
      var random = nextInt();
      final remaining = length - index;
      final count = remaining < 4 ? remaining : 4;
      for (var n = 0; n < count; n++) {
        output[index++] = random & 0xff;
        random >>= 8;
      }
    }
    return output;
  }

  /// Exact GLLib.i3(a,b), including its original MIN_VALUE overflow edge case.
  /// This deliberately differs from Random.nextInt(bound).
  int gameRange(int minimum, int maximum) {
    if (minimum > maximum) throw ArgumentError('minimum > maximum');
    if (minimum == maximum) return maximum;
    var value = nextInt();
    if (value < 0) value = JavaNumbers.negate(value);
    return JavaNumbers.add(
      minimum,
      JavaNumbers.remainder(value, JavaNumbers.subtract(maximum, minimum)),
    );
  }
}
