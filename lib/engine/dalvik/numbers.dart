import 'dart:typed_data';

import '../compat/java_numbers.dart';

/// Dalvik registers hold raw 32-bit words, including IEEE-754 float bits.
/// Wide values occupy adjacent low/high words, without alignment constraints.
/// Opcode numbers follow https://source.android.com/docs/core/runtime/dalvik-bytecode.
abstract final class JBits {
  static int int32(Object? value) => (value as int).toSigned(32);

  static int wide(List<Object?> r, int index) =>
      (int32(r[index]) & 0xffffffff) | (int32(r[index + 1]) << 32);

  static void setWide(List<Object?> r, int index, int value) {
    r[index] = value.toSigned(32);
    r[index + 1] = (value >> 32).toSigned(32);
  }

  static double float(List<Object?> r, int index) =>
      JavaNumbers.floatFromBits(int32(r[index]));

  static void setFloat(List<Object?> r, int index, double value) {
    r[index] = JavaNumbers.floatBits(value);
  }

  static double doubleValue(List<Object?> r, int index) {
    final data = ByteData(8)
      ..setInt32(0, int32(r[index]), Endian.little)
      ..setInt32(4, int32(r[index + 1]), Endian.little);
    return data.getFloat64(0, Endian.little);
  }

  static void setDouble(List<Object?> r, int index, double value) {
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    r[index] = data.getInt32(0, Endian.little);
    r[index + 1] = data.getInt32(4, Endian.little);
  }

  static int _doubleToLong(double value) {
    if (value.isNaN) return 0;
    if (value >= 9223372036854775808.0) return 0x7fffffffffffffff;
    if (value <= -9223372036854775808.0) return -0x8000000000000000;
    return value.truncate();
  }

  // Casting int64 via double can double-round at float midpoints. Perform the
  // one required round-to-nearest/even directly on the exact integer instead.
  static int _longToFloatBits(int value) {
    if (value == 0) return 0;
    final magnitude = BigInt.from(value).abs();
    var exponent = magnitude.bitLength - 1;
    final shift = exponent - 23;
    var significand = shift <= 0 ? magnitude << -shift : magnitude >> shift;
    if (shift > 0) {
      final remainder = magnitude - (significand << shift);
      final half = BigInt.one << (shift - 1);
      if (remainder > half || (remainder == half && significand.isOdd)) {
        significand += BigInt.one;
        if (significand.bitLength > 24) {
          significand >>= 1;
          exponent++;
        }
      }
    }
    return ((value < 0 ? 0x80000000 : 0) |
            ((exponent + 127) << 23) |
            (significand.toInt() & 0x7fffff))
        .toSigned(32);
  }

  static int _longDivide(int a, int b) {
    if (b == 0) throw const JavaArithmeticException('/ by zero');
    if (a == -0x8000000000000000 && b == -1) return a;
    return a ~/ b;
  }

  static int _longRemainder(int a, int b) {
    if (b == 0) throw const JavaArithmeticException('/ by zero');
    if (a == -0x8000000000000000 && b == -1) return 0;
    return a - (a ~/ b) * b;
  }

  static void unary(int opcode, List<Object?> r, int dst, int src) {
    // Read both source words before writing when source/destination overlap.
    switch (opcode) {
      case 0x7b:
        r[dst] = JavaNumbers.negate(int32(r[src]));
      case 0x7c:
        r[dst] = (~int32(r[src])).toSigned(32);
      case 0x7d:
        setWide(r, dst, -wide(r, src));
      case 0x7e:
        setWide(r, dst, ~wide(r, src));
      case 0x7f:
        r[dst] = (int32(r[src]) ^ 0x80000000).toSigned(32);
      case 0x80:
        setWide(r, dst, wide(r, src) ^ -0x8000000000000000);
      case 0x81:
        setWide(r, dst, int32(r[src]));
      case 0x82:
        setFloat(r, dst, int32(r[src]).toDouble());
      case 0x83:
        setDouble(r, dst, int32(r[src]).toDouble());
      case 0x84:
        r[dst] = wide(r, src).toSigned(32);
      case 0x85:
        r[dst] = _longToFloatBits(wide(r, src));
      case 0x86:
        setDouble(r, dst, wide(r, src).toDouble());
      case 0x87:
        r[dst] = JavaNumbers.doubleToInt(float(r, src));
      case 0x88:
        setWide(r, dst, _doubleToLong(float(r, src)));
      case 0x89:
        setDouble(r, dst, float(r, src));
      case 0x8a:
        r[dst] = JavaNumbers.doubleToInt(doubleValue(r, src));
      case 0x8b:
        setWide(r, dst, _doubleToLong(doubleValue(r, src)));
      case 0x8c:
        setFloat(r, dst, doubleValue(r, src));
      case 0x8d:
        r[dst] = int32(r[src]).toSigned(8);
      case 0x8e:
        r[dst] = int32(r[src]).toUnsigned(16);
      case 0x8f:
        r[dst] = int32(r[src]).toSigned(16);
      default:
        throw UnsupportedError(
          'Dalvik unary opcode 0x${opcode.toRadixString(16)}',
        );
    }
  }

  /// Operands are register indices. /2addr and /lit forms must be normalized by
  /// the emitter; long shifts read an int distance, not a wide right operand.
  static void binary(
    int opcode,
    List<Object?> r,
    int dst,
    int left,
    int right,
  ) {
    if (opcode >= 0x90 && opcode <= 0x9a) {
      final a = int32(r[left]);
      final b = int32(r[right]);
      r[dst] = switch (opcode) {
        0x90 => JavaNumbers.add(a, b),
        0x91 => JavaNumbers.subtract(a, b),
        0x92 => JavaNumbers.multiply(a, b),
        0x93 => JavaNumbers.divide(a, b),
        0x94 => JavaNumbers.remainder(a, b),
        0x95 => a & b,
        0x96 => a | b,
        0x97 => a ^ b,
        0x98 => JavaNumbers.shiftLeft(a, b),
        0x99 => JavaNumbers.shiftRight(a, b),
        0x9a => JavaNumbers.unsignedShiftRight(a, b),
        _ => throw StateError('Unreachable int opcode'),
      };
    } else if (opcode >= 0x9b && opcode <= 0xa5) {
      final a = wide(r, left);
      final b = opcode >= 0xa3 ? int32(r[right]) : wide(r, right);
      setWide(r, dst, switch (opcode) {
        0x9b => a + b,
        0x9c => a - b,
        0x9d => a * b,
        0x9e => _longDivide(a, b),
        0x9f => _longRemainder(a, b),
        0xa0 => a & b,
        0xa1 => a | b,
        0xa2 => a ^ b,
        0xa3 => a << (b & 63),
        0xa4 => a >> (b & 63),
        0xa5 => a >>> (b & 63),
        _ => throw StateError('Unreachable long opcode'),
      });
    } else if (opcode >= 0xa6 && opcode <= 0xaf) {
      final isFloat = opcode <= 0xaa;
      final a = isFloat ? float(r, left) : doubleValue(r, left);
      final b = isFloat ? float(r, right) : doubleValue(r, right);
      final result = switch (opcode) {
        0xa6 || 0xab => a + b,
        0xa7 || 0xac => a - b,
        0xa8 || 0xad => a * b,
        0xa9 || 0xae => a / b,
        0xaa || 0xaf => a.remainder(b),
        _ => throw StateError('Unreachable floating opcode'),
      };
      if (isFloat) {
        setFloat(r, dst, result);
      } else {
        setDouble(r, dst, result);
      }
    } else {
      throw UnsupportedError(
        'Dalvik binary opcode 0x${opcode.toRadixString(16)}',
      );
    }
  }

  static int compare(int opcode, List<Object?> r, int left, int right) {
    if (opcode == 0x31) {
      final a = wide(r, left), b = wide(r, right);
      return a == b ? 0 : (a < b ? -1 : 1);
    }
    if (opcode < 0x2d || opcode > 0x30) {
      throw UnsupportedError(
        'Dalvik compare opcode 0x${opcode.toRadixString(16)}',
      );
    }
    final a = opcode <= 0x2e ? float(r, left) : doubleValue(r, left);
    final b = opcode <= 0x2e ? float(r, right) : doubleValue(r, right);
    if (a.isNaN || b.isNaN) return opcode == 0x2d || opcode == 0x2f ? -1 : 1;
    return a == b ? 0 : (a < b ? -1 : 1);
  }
}
