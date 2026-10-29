import 'dart:typed_data';

import 'binary.dart';
import 'legacy_gzip.dart';
import 'xxtea.dart';

/// Defensive byte copy matching SaveData (d1.java).
class SaveData {
  SaveData(List<int> bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uint8List bytes;
}

class SaveBlock {
  SaveBlock(this.type, List<int> bytes) : data = SaveData(bytes);
  final int type;
  final SaveData data;
}

/// The local binary envelope written by e1.A and completed by e1.h.
/// This codec does not invent game-state fields, a GLUID, or cloud behavior.
class SaveGameCodec {
  static Uint8List encode(List<SaveBlock> blocks, {required List<int> key}) {
    final output = BinaryWriter();
    for (final block in blocks) {
      if (block.data.bytes.isEmpty) {
        throw ArgumentError('SaveGameManager cannot reload an empty block');
      }
      final encrypted = LegacyXxtea.encrypt(
        LegacyGzip.encode(block.data.bytes),
        key,
      );
      output.writeInt32(block.type);
      output.writeInt32(crc32(block.data.bytes));
      output.writeInt32(encrypted.length);
      output.writeBytes(encrypted);
    }
    output.writeInt32(blocks.length);
    return output.toBytes();
  }

  static List<SaveBlock> decode(
    List<int> bytes, {
    required List<int> key,
    int maxDecodedBytes = 64 * 1024 * 1024,
  }) {
    if (maxDecodedBytes < 0) throw ArgumentError.value(maxDecodedBytes);
    if (bytes.length < 4) {
      throw const FormatException('Missing save block count');
    }
    final countReader = BinaryReader(bytes.sublist(bytes.length - 4));
    final count = countReader.readInt32();
    final reader = BinaryReader(bytes.sublist(0, bytes.length - 4));
    if (count < 0 || count > reader.remaining ~/ 20) {
      throw const FormatException('Invalid save block count');
    }
    final blocks = <SaveBlock>[];
    var decodedSize = 0;
    for (var i = 0; i < count; i++) {
      final type = reader.readInt32();
      final checksum = reader.readUint32();
      final encryptedLength = reader.readInt32();
      if (encryptedLength < 8 || encryptedLength % 4 != 0) {
        throw FormatException('Invalid encrypted length for save block $i');
      }
      final decrypted = LegacyXxtea.decrypt(
        reader.readBytes(encryptedLength),
        key,
      );
      final data = LegacyGzip.decode(
        decrypted,
        maxOutputBytes: maxDecodedBytes - decodedSize,
      );
      if (data.isEmpty) throw FormatException('Empty save block $i');
      if (crc32(data) != checksum) {
        throw FormatException('Save block $i CRC mismatch');
      }
      decodedSize += data.length;
      blocks.add(SaveBlock(type, data));
    }
    if (reader.remaining != 0) {
      throw const FormatException('Save block count does not consume the data');
    }
    return List<SaveBlock>.unmodifiable(blocks);
  }
}
