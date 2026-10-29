import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/compat/java_numbers.dart';

void main() {
  test('signed narrowing and overflow', () {
    expect(JavaNumbers.int8(255), -1);
    expect(JavaNumbers.int16(65535), -1);
    expect(JavaNumbers.add(0x7fffffff, 1), -0x80000000);
    expect(JavaNumbers.multiply(0x40000000, 4), 0);
    expect(JavaNumbers.negate(-0x80000000), -0x80000000);
  });
  test('division and remainder follow Java, including overflow', () {
    expect(JavaNumbers.divide(-7, 3), -2);
    expect(JavaNumbers.remainder(-7, 3), -1);
    expect(JavaNumbers.remainder(7, -3), 1);
    expect(JavaNumbers.divide(-0x80000000, -1), -0x80000000);
    expect(JavaNumbers.remainder(-0x80000000, -1), 0);
    expect(
      () => JavaNumbers.divide(1, 0),
      throwsA(isA<JavaArithmeticException>()),
    );
    expect(
      () => JavaNumbers.remainder(1, 0),
      throwsA(isA<JavaArithmeticException>()),
    );
  });
  test('shift counts are masked to five bits', () {
    expect(JavaNumbers.shiftLeft(1, 32), 1);
    expect(JavaNumbers.shiftLeft(1, -1), -0x80000000);
    expect(JavaNumbers.unsignedShiftRight(-1, 1), 0x7fffffff);
    expect(JavaNumbers.unsignedShiftRight(-1, 0), -1);
    expect(JavaNumbers.shiftRight(-1, 63), -1);
  });
  test('float narrowing and JVM saturation', () {
    expect(JavaNumbers.float32(16777217), 16777216);
    expect(JavaNumbers.floatBits(-0.0), -0x80000000);
    expect(JavaNumbers.floatFromBits(0x3f800000), 1);
    expect(JavaNumbers.doubleToInt(double.nan), 0);
    expect(JavaNumbers.doubleToInt(double.infinity), 0x7fffffff);
    expect(JavaNumbers.doubleToInt(double.negativeInfinity), -0x80000000);
    expect(JavaNumbers.doubleToInt(-3.9), -3);
  });
}
