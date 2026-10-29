import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'binary.dart';

/// Byte-exact encoder port of a0.e/a/b, g0.g/h/i and r0.c/d.
/// Uses 2048-byte blocks, the first occurrence of each three-byte key, fixed
/// Huffman codes and a zero timestamp/OS byte. It is not zlib's compressor.
class LegacyGzip {
  static const _lengths = <int>[
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    523,
    525,
    527,
    529,
    1043,
    1047,
    1051,
    1055,
    1571,
    1579,
    1587,
    1595,
    2115,
    2131,
    2147,
    2163,
    2691,
    2723,
    2755,
    2787,
    258,
  ];
  static const _distances = <int>[
    1,
    2,
    3,
    4,
    65541,
    65543,
    131081,
    131085,
    196625,
    196633,
    262177,
    262193,
    327745,
    327777,
    393345,
    393409,
    459009,
    459137,
    524801,
    525057,
    590849,
    591361,
    657409,
    658433,
    724993,
    727041,
    794625,
    798721,
    868353,
    876545,
  ];

  static Uint8List encode(List<int> input) {
    final bytes = Uint8List.fromList(input);
    final bits = _BitWriter();
    var start = 0;
    while (true) {
      final count = math.min(2048, bytes.length - start);
      final last = count < 2048;
      bits.write(last ? 1 : 0, 1);
      bits.write(1, 2);
      final chunk = Uint8List.sublistView(bytes, start, start + count);
      _block(chunk, bits);
      _literal(256, bits);
      start += count;
      if (last) break;
    }
    final writer = BinaryWriter();
    writer.writeBytes(const [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0]);
    writer.writeBytes(bits.finish());
    writer.writeInt32(crc32(bytes));
    writer.writeInt32(bytes.length);
    return writer.toBytes();
  }

  static void _block(Uint8List bytes, _BitWriter bits) {
    final firstPositions = <int, int>{};
    var rolling = 0;
    var position = 0;
    while (position < bytes.length) {
      int? previous;
      if (bytes.length - position > 2) {
        final key =
            (bytes[position] << 16) |
            (bytes[position + 1] << 8) |
            bytes[position + 2];
        previous = firstPositions[key];
      }
      var matched = 0;
      if (previous != null) {
        final distance = position - previous;
        while (position + matched < bytes.length &&
            bytes[position + matched] == bytes[previous + matched] &&
            matched + 1 < 256 &&
            distance + matched + 1 < 2048) {
          matched++;
        }
        if (matched > 2) {
          final lengthCode = _floorCode(matched, _lengths, 511);
          _literal(lengthCode + 257, bits);
          final lengthEntry = _lengths[lengthCode];
          bits.write(matched - (lengthEntry & 511), lengthEntry >>> 9);
          final distanceCode = _floorCode(distance, _distances, 65535);
          bits.write(_reverse(distanceCode, 5), 5);
          final distanceEntry = _distances[distanceCode];
          bits.write(distance - (distanceEntry & 65535), distanceEntry >>> 16);
          position += matched;
          continue;
        }
      }
      final byte = bytes[position];
      rolling = ((rolling & 65535) << 8) | byte;
      if (position >= 2) {
        firstPositions.putIfAbsent(rolling, () => position - 2);
      }
      _literal(byte, bits);
      position++;
    }
  }

  static int _floorCode(int value, List<int> table, int mask) {
    var code = 0;
    while (code + 1 < table.length && (table[code + 1] & mask) <= value) {
      code++;
    }
    return code;
  }

  static void _literal(int value, _BitWriter bits) {
    final (code, count) = switch (value) {
      < 144 => (value + 48, 8),
      < 256 => (value - 144 + 400, 9),
      < 280 => (value - 256, 7),
      _ => (value - 280 + 192, 8),
    };
    bits.write(_reverse(code, count), count);
  }

  static int _reverse(int value, int count) {
    var result = 0;
    for (var i = 0; i < count; i++) {
      result = (result << 1) | ((value >>> i) & 1);
    }
    return result;
  }

  /// Standard gzip decoder accepts the original fixed-Huffman stream and
  /// validates its trailer. Output is bounded for corrupt/imported save files.
  static Uint8List decode(
    List<int> input, {
    int maxOutputBytes = 64 * 1024 * 1024,
  }) {
    if (maxOutputBytes < 0) throw ArgumentError.value(maxOutputBytes);
    final output = _BoundedSink(maxOutputBytes);
    final decoder = gzip.decoder.startChunkedConversion(output);
    try {
      decoder.add(input);
      decoder.close();
    } on FormatException {
      rethrow;
    } on IOException catch (error) {
      throw FormatException('Invalid gzip save data: $error');
    }
    return output.bytes.takeBytes();
  }
}

class _BitWriter {
  final _bytes = BytesBuilder(copy: false);
  int _value = 0;
  int _count = 0;

  void write(int value, int count) {
    _value |= (value & ((1 << count) - 1)) << _count;
    _count += count;
    while (_count >= 8) {
      _bytes.addByte(_value & 0xff);
      _value >>>= 8;
      _count -= 8;
    }
  }

  Uint8List finish() {
    if (_count > 0) _bytes.addByte(_value & 0xff);
    return _bytes.takeBytes();
  }
}

class _BoundedSink extends ByteConversionSink {
  _BoundedSink(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (chunk.length > limit - bytes.length) {
      throw const FormatException('Decompressed save exceeds the size limit');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
