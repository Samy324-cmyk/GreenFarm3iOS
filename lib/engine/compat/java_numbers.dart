import 'dart:typed_data';

/// Explicit Dalvik/Java numeric operations used by the original game.
/// Dart's `%` is Euclidean; Java's remainder retains the dividend's sign.
abstract final class JavaNumbers {
  static int int32(int value) => value.toSigned(32);
  static int uint32(int value) => value.toUnsigned(32);
  static int int16(int value) => value.toSigned(16);
  static int uint16(int value) => value.toUnsigned(16);
  static int int8(int value) => value.toSigned(8);
  static int uint8(int value) => value.toUnsigned(8);

  static int add(int a, int b) => (a + b).toSigned(32);
  static int subtract(int a, int b) => (a - b).toSigned(32);
  static int multiply(int a, int b) => (a * b).toSigned(32);
  static int negate(int a) => (-a).toSigned(32);

  static int divide(int a, int b) {
    a = a.toSigned(32);
    b = b.toSigned(32);
    if (b == 0) throw const JavaArithmeticException('/ by zero');
    if (a == -0x80000000 && b == -1) return -0x80000000;
    return a ~/ b;
  }

  static int remainder(int a, int b) {
    a = a.toSigned(32);
    b = b.toSigned(32);
    if (b == 0) throw const JavaArithmeticException('/ by zero');
    if (a == -0x80000000 && b == -1) return 0;
    return a - (a ~/ b) * b;
  }

  static int shiftLeft(int value, int distance) =>
      (value.toSigned(32) << (distance & 31)).toSigned(32);
  static int shiftRight(int value, int distance) =>
      value.toSigned(32) >> (distance & 31);
  static int unsignedShiftRight(int value, int distance) =>
      (value.toUnsigned(32) >> (distance & 31)).toSigned(32);

  static double float32(double value) {
    final data = ByteData(4)..setFloat32(0, value, Endian.little);
    return data.getFloat32(0, Endian.little);
  }

  static int floatBits(double value) {
    final data = ByteData(4)..setFloat32(0, value, Endian.little);
    return data.getInt32(0, Endian.little);
  }

  static double floatFromBits(int bits) {
    final data = ByteData(4)..setInt32(0, bits, Endian.little);
    return data.getFloat32(0, Endian.little);
  }

  static int doubleToInt(double value) {
    if (value.isNaN) return 0;
    if (value >= 2147483647) return 2147483647;
    if (value <= -2147483648) return -2147483648;
    return value.truncate();
  }
}

class JavaArithmeticException implements Exception {
  const JavaArithmeticException(this.message);
  final String message;
  @override
  String toString() => 'JavaArithmeticException: $message';
}
