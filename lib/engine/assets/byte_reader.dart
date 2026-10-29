import 'dart:typed_data';

/// Bounded little-endian reads used by the original Gameloft data formats.
final class AssetReader {
  AssetReader(this.bytes) : _view = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData _view;
  int offset = 0;
  int get remaining => bytes.length - offset;

  Never fail(String reason) => throw FormatException(reason, bytes, offset);

  void require(int count) {
    if (count < 0 || count > remaining) {
      fail('Truncated asset: need $count bytes');
    }
  }

  int u8() {
    require(1);
    return bytes[offset++];
  }

  int i8() {
    final v = u8();
    return v < 128 ? v : v - 256;
  }

  int u16() {
    require(2);
    final v = _view.getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int i16() {
    require(2);
    final v = _view.getInt16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int u32() {
    require(4);
    final v = _view.getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int i32() {
    require(4);
    final v = _view.getInt32(offset, Endian.little);
    offset += 4;
    return v;
  }

  Uint8List take(int count) {
    require(count);
    final result = Uint8List.fromList(bytes.sublist(offset, offset + count));
    offset += count;
    return result;
  }

  void end() {
    if (remaining != 0) fail('Trailing asset data: $remaining bytes');
  }
}
