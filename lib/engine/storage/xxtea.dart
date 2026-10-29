import 'dart:typed_data';

/// GLLib V7/S7 (XXTEA), including its appended original-length word.
/// Keys are bytes: callers choose the original UTF-8 encoding explicitly.
class LegacyXxtea {
  static const int _delta = 0x9e3779b9;
  static const int _mask = 0xffffffff;

  static Uint8List encrypt(List<int> bytes, List<int> key) {
    if (bytes.isEmpty) return Uint8List(0);
    final words = _toWords(bytes, includeLength: true);
    final keys = _keyWords(key);
    var sum = 0;
    var z = words.last;
    for (var round = 0; round < 6 + 52 ~/ words.length; round++) {
      sum = (sum + _delta) & _mask;
      final e = (sum >>> 2) & 3;
      for (var p = 0; p < words.length; p++) {
        final y = words[(p + 1) % words.length];
        z = words[p] = (words[p] + _mix(z, y, sum, keys[(p & 3) ^ e])) & _mask;
      }
    }
    return _toBytes(words);
  }

  static Uint8List decrypt(List<int> bytes, List<int> key) {
    if (bytes.isEmpty) return Uint8List(0);
    if (bytes.length < 8 || bytes.length % 4 != 0) {
      throw const FormatException('Invalid XXTEA ciphertext length');
    }
    final words = _toWords(bytes);
    final keys = _keyWords(key);
    var sum = ((6 + 52 ~/ words.length) * _delta) & _mask;
    var y = words.first;
    while (sum != 0) {
      final e = (sum >>> 2) & 3;
      for (var p = words.length - 1; p >= 0; p--) {
        final z = words[(p - 1 + words.length) % words.length];
        y = words[p] = (words[p] - _mix(z, y, sum, keys[(p & 3) ^ e])) & _mask;
      }
      sum = (sum - _delta) & _mask;
    }
    final length = words.last;
    final capacity = (words.length - 1) * 4;
    // Strict bound for a V7-produced length word; wrong keys fail clearly.
    if (length > capacity || length < capacity - 3) {
      throw const FormatException('Invalid XXTEA length word or key');
    }
    return Uint8List.sublistView(_toBytes(words), 0, length);
  }

  static int _mix(int z, int y, int sum, int key) =>
      ((((z >>> 5) ^ (y << 2)) + ((y >>> 3) ^ (z << 4))) ^
          ((y ^ sum) + (z ^ key))) &
      _mask;

  static List<int> _keyWords(List<int> key) {
    final words = _toWords(key);
    while (words.length < 4) {
      words.add(0);
    }
    return words;
  }

  static List<int> _toWords(List<int> bytes, {bool includeLength = false}) {
    final count = (bytes.length + 3) ~/ 4;
    final words = List<int>.filled(
      count + (includeLength ? 1 : 0),
      0,
      growable: true,
    );
    for (var i = 0; i < bytes.length; i++) {
      words[i ~/ 4] |= (bytes[i] & 0xff) << ((i & 3) * 8);
    }
    if (includeLength) words[count] = bytes.length;
    return words;
  }

  static Uint8List _toBytes(List<int> words) {
    final result = Uint8List(words.length * 4);
    final data = ByteData.sublistView(result);
    for (var i = 0; i < words.length; i++) {
      data.setUint32(i * 4, words[i], Endian.little);
    }
    return result;
  }
}
