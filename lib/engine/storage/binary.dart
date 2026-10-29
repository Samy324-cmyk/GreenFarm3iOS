import 'dart:typed_data';

/// Byte-exact primitives used by GLLib n3/o3/p3/q3 and t3/u3/v3/w3.
/// GLLib save buffers are little endian; RecordStore headers use big endian.
class BinaryReader {
  BinaryReader(List<int> bytes, {this.endian = Endian.little})
    : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  final Endian endian;
  int position = 0;

  int get remaining => _bytes.length - position;

  void _require(int count) {
    if (count < 0 || position < 0 || count > remaining) {
      throw FormatException('Truncated binary data at $position: need $count');
    }
  }

  int readUint8() {
    _require(1);
    return _bytes[position++];
  }

  int readInt8() => readUint8().toSigned(8);

  int readUint16() => _read(2).getUint16(0, endian);
  int readInt16() => _read(2).getInt16(0, endian);
  int readUint32() => _read(4).getUint32(0, endian);
  int readInt32() => _read(4).getInt32(0, endian);
  int readInt64() => _read(8).getInt64(0, endian);

  ByteData _read(int count) {
    _require(count);
    final data = ByteData.sublistView(_bytes, position, position + count);
    position += count;
    return data;
  }

  Uint8List readBytes(int count) {
    _require(count);
    final result = Uint8List.fromList(
      _bytes.sublist(position, position + count),
    );
    position += count;
    return result;
  }
}

class BinaryWriter {
  BinaryWriter({this.endian = Endian.little});

  final Endian endian;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  int get length => _bytes.length;

  void writeByte(int value) => _bytes.addByte(value & 0xff);

  void writeInt16(int value) {
    final data = ByteData(2)..setInt16(0, value.toSigned(16), endian);
    _bytes.add(data.buffer.asUint8List());
  }

  void writeInt32(int value) {
    final data = ByteData(4)..setInt32(0, value.toSigned(32), endian);
    _bytes.add(data.buffer.asUint8List());
  }

  void writeInt64(int value) {
    final data = ByteData(8)..setInt64(0, value.toSigned(64), endian);
    _bytes.add(data.buffer.asUint8List());
  }

  void writeBytes(List<int> bytes) => _bytes.add(bytes);
  Uint8List toBytes() => _bytes.toBytes();
}

/// Standard reflected CRC-32, matching GLLib.A2/E0 and java.util.zip.CRC32.
int crc32(List<int> bytes, {int previous = 0}) {
  var value = (previous ^ 0xffffffff) & 0xffffffff;
  for (final byte in bytes) {
    value ^= byte & 0xff;
    for (var bit = 0; bit < 8; bit++) {
      value = (value >>> 1) ^ ((value & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return (value ^ 0xffffffff) & 0xffffffff;
}
