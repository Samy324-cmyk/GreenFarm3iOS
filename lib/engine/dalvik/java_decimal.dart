/*
 * Copyright (c) 1996, 2013, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation. Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */
// Dart adaptation of OpenJDK 8 FloatingDecimal's binary-to-decimal algorithm.
// BigInt replaces FDBigInteger. The fixed-width overflow and integer fast path
// are deliberately retained: changing these alters Java 8's printed decimals.
// Source: openjdk/jdk8u/jdk/src/share/classes/sun/misc/FloatingDecimal.java
import 'dart:math' as math;
import 'dart:typed_data';

String javaFloatingText(double value, bool single) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value.isNegative ? '-Infinity' : 'Infinity';
  if (value == 0) return value.isNegative ? '-0.0' : '0.0';
  final negative = value.isNegative;
  final raw = ByteData(8);
  final int bits, fracWidth, bias, exponentMask;
  if (single) {
    raw.setFloat32(0, value.abs());
    bits = raw.getUint32(0);
    fracWidth = 23;
    bias = 127;
    exponentMask = 255;
  } else {
    raw.setFloat64(0, value.abs());
    bits = raw.getInt64(0);
    fracWidth = 52;
    bias = 1023;
    exponentMask = 2047;
  }
  var binaryExponent = (bits >> fracWidth) & exponentMask;
  var fraction = bits & ((1 << fracWidth) - 1);
  int significant;
  if (binaryExponent == 0) {
    significant = fraction.bitLength;
    final shift = fracWidth + 1 - significant;
    fraction <<= shift;
    binaryExponent = 1 - shift;
  } else {
    fraction |= 1 << fracWidth;
    significant = fracWidth + 1;
  }
  binaryExponent -= bias;
  fraction <<= 52 - fracWidth;
  var trailing = 0;
  while (((fraction >> trailing) & 1) == 0) {
    trailing++;
  }
  final fractionBits = 53 - trailing;
  final tiny = math.max(0, fractionBits - binaryExponent - 1);
  if (tiny == 0 && binaryExponent >= -21 && binaryExponent <= 62) {
    var integer = binaryExponent >= 52
        ? BigInt.from(fraction) << (binaryExponent - 52)
        : BigInt.from(fraction) >> (52 - binaryExponent);
    final p = binaryExponent - significant - 1;
    final insignificant = binaryExponent > significant && p > 1 && p < 64
        ? (BigInt.one << p).toString().length - 1
        : 0;
    var scale = insignificant;
    if (insignificant > 0) {
      final power = BigInt.from(10).pow(insignificant);
      final residue = integer % power;
      integer ~/= power;
      if (residue >= (power >> 1)) integer += BigInt.one;
    }
    var digits = integer.toString();
    final place = digits.length + scale;
    while (digits.length > 1 && digits.endsWith('0')) {
      digits = digits.substring(0, digits.length - 1);
    }
    return _render(digits, place, negative);
  }
  final normalized = fraction / (1 << 52);
  var exponent =
      ((normalized - 1.5) * 0.289529654 +
              0.176091259 +
              binaryExponent * 0.301029995663981)
          .floor();
  final b5 = math.max(0, -exponent), s5 = math.max(0, exponent);
  var b2 = b5 + tiny + binaryExponent;
  var s2 = s5 + tiny, m2 = b2 - significant;
  fraction >>= trailing;
  b2 -= fractionBits - 1;
  final common = math.min(b2, s2);
  b2 -= common;
  s2 -= common;
  m2 -= common;
  if (fractionBits == 1) m2--;
  if (m2 < 0) {
    b2 -= m2;
    s2 -= m2;
    m2 = 0;
  }
  BigInt power5(int n) => BigInt.from(5).pow(n);
  int fiveBits(int n) => n == 0
      ? 0
      : n < 27
      ? power5(n).bitLength
      : n * 3;
  final bBits = fractionBits + b2 + fiveBits(b5),
      tenBits = s2 + 1 + fiveBits(s5 + 1);
  final width = bBits < 64 && tenBits < 64
      ? (bBits < 32 && tenBits < 32 ? 32 : 64)
      : 0;
  BigInt wrap(BigInt x) => width == 0 ? x : x.toSigned(width);
  var b = wrap(BigInt.from(fraction) * power5(b5) << b2);
  final s = wrap(power5(s5) << s2),
      ten = wrap((power5(s5) << s2) * BigInt.from(10));
  var margin = wrap(power5(b5) << m2);
  final digits = <int>[];
  var low = false, high = false;
  void step() {
    final digit = (b ~/ s).toInt();
    b = wrap((b % s) * BigInt.from(10));
    margin = wrap(margin * BigInt.from(10));
    if (margin > BigInt.zero) {
      low = b < margin;
      high = width == 0 ? b + margin >= ten : wrap(b + margin) > ten;
    } else {
      low = true;
      high = true;
    }
    if (digits.isEmpty && digit == 0 && !high) {
      exponent--;
    } else {
      digits.add(digit);
    }
  }

  step();
  if (exponent < -3 || exponent >= 8) {
    high = false;
    low = false;
  }
  while (!low && !high) {
    step();
  }
  final difference = wrap(wrap(b << 1) - ten);
  if (high &&
      (!low ||
          difference > BigInt.zero ||
          (difference == BigInt.zero && digits.last.isOdd))) {
    var at = digits.length - 1;
    while (at > 0 && digits[at] == 9) {
      digits[at] = 0;
      at--;
    }
    if (digits[at] == 9) {
      digits[0] = 1;
      exponent++;
    } else {
      digits[at]++;
    }
  }
  return _render(digits.join(), exponent + 1, negative);
}

String _render(String digits, int place, bool negative) {
  final String value;
  if (place > 0 && place < 8) {
    value = place >= digits.length
        ? '$digits${'0' * (place - digits.length)}.0'
        : '${digits.substring(0, place)}.${digits.substring(place)}';
  } else if (place <= 0 && place > -3) {
    value = '0.${'0' * (-place)}$digits';
  } else {
    value =
        '${digits[0]}.${digits.length == 1 ? '0' : digits.substring(1)}E${place - 1}';
  }
  return negative ? '-$value' : value;
}
