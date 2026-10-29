/// Parses Java decimal/hexadecimal literals directly to IEEE bits. Using a
/// binary64 intermediate for Float.parseFloat incorrectly double-rounds values
/// extremely close to a binary32 midpoint.
int? javaParseFloatingBits(String text, {required bool single}) {
  final p = single ? 24 : 53, bias = single ? 127 : 1023;
  final width = single ? 32 : 64;
  var s = text, negative = false;
  if (s.startsWith('+') || s.startsWith('-')) {
    negative = s[0] == '-';
    s = s.substring(1);
  }
  final sign = negative ? BigInt.one << (width - 1) : BigInt.zero;
  int exceptional(int fraction) =>
      (sign | BigInt.from(fraction)).toSigned(width).toInt();
  if (s == 'NaN') return single ? 0x7fc00000 : 0x7ff8000000000000;
  if (s == 'Infinity') {
    return exceptional(single ? 0x7f800000 : 0x7ff0000000000000);
  }
  if (s.endsWith('f') ||
      s.endsWith('F') ||
      s.endsWith('d') ||
      s.endsWith('D')) {
    s = s.substring(0, s.length - 1);
  }
  BigInt numerator, denominator;
  if (s.startsWith('0x') || s.startsWith('0X')) {
    final match = RegExp(
      r'^0[xX]([0-9a-fA-F]+(?:\.[0-9a-fA-F]*)?|\.[0-9a-fA-F]+)[pP]([+-]?\d+)$',
    ).firstMatch(s);
    if (match == null) return null;
    final mantissa = match[1]!, point = mantissa.indexOf('.');
    final digits = mantissa.replaceAll('.', '');
    numerator = BigInt.parse(digits, radix: 16);
    if (numerator == BigInt.zero) return sign.toSigned(width).toInt();
    final exp =
        BigInt.parse(match[2]!) -
        BigInt.from(point < 0 ? 0 : (mantissa.length - point - 1) * 4);
    final magnitude = exp + BigInt.from(numerator.bitLength);
    if (magnitude > BigInt.from(1100)) {
      return exceptional(single ? 0x7f800000 : 0x7ff0000000000000);
    }
    if (magnitude < BigInt.from(-1200)) return sign.toSigned(width).toInt();
    final scale = exp.toInt();
    denominator = BigInt.one;
    if (scale >= 0) {
      numerator <<= scale;
    } else {
      denominator <<= -scale;
    }
  } else {
    final match = RegExp(r'^(\d+(?:\.\d*)?|\.\d+)(?:[eE]([+-]?\d+))?$')
        .firstMatch(s);
    if (match == null) return null;
    final mantissa = match[1]!, point = mantissa.indexOf('.');
    final digits = mantissa
        .replaceAll('.', '')
        .replaceFirst(RegExp(r'^0+'), '');
    if (digits.isEmpty) return sign.toSigned(width).toInt();
    final exp =
        BigInt.parse(match[2] ?? '0') -
        BigInt.from(point < 0 ? 0 : mantissa.length - point - 1);
    final magnitude = exp + BigInt.from(digits.length);
    if (magnitude > BigInt.from(400)) {
      return exceptional(single ? 0x7f800000 : 0x7ff0000000000000);
    }
    if (magnitude < BigInt.from(-400)) return sign.toSigned(width).toInt();
    numerator = BigInt.parse(digits);
    denominator = BigInt.one;
    final scale = exp.toInt();
    if (scale >= 0) {
      numerator *= BigInt.from(10).pow(scale);
    } else {
      denominator = BigInt.from(10).pow(-scale);
    }
  }
  var exponent = numerator.bitLength - denominator.bitLength;
  if (exponent >= 0) {
    if (numerator < (denominator << exponent)) exponent--;
  } else {
    if ((numerator << -exponent) < denominator) exponent--;
  }
  if (exponent > bias) {
    return exceptional(single ? 0x7f800000 : 0x7ff0000000000000);
  }
  final effective = exponent < 1 - bias ? 1 - bias : exponent;
  final shift = p - 1 - effective;
  final n = shift >= 0 ? numerator << shift : numerator;
  final d = shift >= 0 ? denominator : denominator << -shift;
  var rounded = n ~/ d;
  final remainder = n % d;
  if ((remainder << 1) > d || ((remainder << 1) == d && rounded.isOdd)) {
    rounded += BigInt.one;
  }
  var encodedExponent = effective + bias;
  if (rounded.bitLength > p) {
    rounded >>= 1;
    encodedExponent++;
  }
  if (encodedExponent >= 2 * bias + 1) {
    return exceptional(single ? 0x7f800000 : 0x7ff0000000000000);
  }
  if (rounded < (BigInt.one << (p - 1))) encodedExponent = 0;
  final fraction = rounded & ((BigInt.one << (p - 1)) - BigInt.one);
  return (sign | (BigInt.from(encodedExponent) << (p - 1)) | fraction)
      .toSigned(width)
      .toInt();
}
