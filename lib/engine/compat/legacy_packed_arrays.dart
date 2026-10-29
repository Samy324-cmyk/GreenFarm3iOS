import 'dart:typed_data';

/// Java InputStream byte/EOF behavior used by GLLib.f7, g7, h7 and r3.
///
/// Reading EOF returns -1, leaves the cursor unchanged, and does not increment
/// [bytesRead]. This intentionally differs from a strict asset-header reader.
final class LegacyInputStream {
  LegacyInputStream(this.bytes, {int offset = 0}) : _position = offset {
    RangeError.checkValueInInterval(offset, 0, bytes.length, 'offset');
  }

  final Uint8List bytes;
  int _position;
  int bytesRead = 0;

  int get position => _position;
  int get available => bytes.length - _position;

  int read() {
    if (_position >= bytes.length) return -1;
    bytesRead++;
    return bytes[_position++];
  }

  /// GLLib.g7, preserving actual bytecode evaluation order.
  int readUint16() {
    final low = read() & 255;
    final high = read() & 255;
    return low | (high << 8);
  }

  /// GLLib.h7; the result has Java's signed 32-bit int semantics.
  int readInt32() {
    final b0 = read() & 255;
    final b1 = read() & 255;
    final b2 = read() & 255;
    final b3 = read() & 255;
    return (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)).toSigned(32);
  }
}

enum LegacyArrayKind { byte, short, integer }

/// Type information is retained so recursive writes obey Java array-store
/// rules. A mismatched nested type takes the original r3 error path.
final class LegacyPackedArray {
  LegacyPackedArray._(this.kind, this.dimensions, this.values);

  final LegacyArrayKind kind;
  final int dimensions;

  /// Int8List/Int16List/Int32List for dimensions=1; a fixed list of
  /// LegacyPackedArray? for dimensions=2 or 3.
  final List<Object?> values;

  int get length => values.length;
  Object? operator [](int index) => values[index];

  List<Object?> toLists() => <Object?>[
    for (final value in values)
      if (value is LegacyPackedArray) value.toLists() else value,
  ];
}

/// Instruction-order reconstruction of GLLib.r3 (Mem_ReadArray).
///
/// Use only at a known packed-array offset. An EOF *header* in the original is
/// 0xff, which describes a recursive array; it is not an end-of-stream sentinel.
/// Scalar EOF payload bytes retain the original signed/masked semantics.
/// [onDiagnostic] receives the original assertion text; errors return null.
LegacyPackedArray? readLegacyPackedArray(
  LegacyInputStream? stream, {
  void Function(String message)? onDiagnostic,
}) {
  if (stream == null) onDiagnostic?.call('Mem_ReadArray.is is null');
  try {
    final input = stream!;
    final flags = input.read();
    final storage = flags >> 4;
    final type = flags & 7;
    final count = flags & 8 != 0 ? input.readUint16() : input.read();
    if (type == 0) {
      final values = Int8List(count);
      for (var i = 0; i < count; i++) {
        values[i] = input.read().toSigned(8);
      }
      return LegacyPackedArray._(LegacyArrayKind.byte, 1, values);
    }
    if (type == 1) {
      final values = Int16List(count);
      for (var i = 0; i < count; i++) {
        values[i] = storage == 0
            ? input.read().toSigned(8)
            : input.readUint16().toSigned(16);
      }
      return LegacyPackedArray._(LegacyArrayKind.short, 1, values);
    }
    if (type == 2) {
      final values = Int32List(count);
      for (var i = 0; i < count; i++) {
        values[i] = storage == 0
            ? input.read().toSigned(8)
            : storage == 1
            ? input.readUint16().toSigned(16)
            : input.readInt32();
      }
      return LegacyPackedArray._(LegacyArrayKind.integer, 1, values);
    }
    final leafType = type & 3;
    final kind = leafType == 0
        ? LegacyArrayKind.byte
        : leafType == 1
        ? LegacyArrayKind.short
        : LegacyArrayKind.integer;
    final dimensions = storage == 2 ? 2 : 3;
    final values = List<LegacyPackedArray?>.filled(count, null);
    for (var i = 0; i < count; i++) {
      final child = readLegacyPackedArray(input, onDiagnostic: onDiagnostic);
      if (child != null &&
          (child.kind != kind || child.dimensions != dimensions - 1)) {
        throw const FormatException('Java ArrayStoreException equivalent');
      }
      values[i] = child;
    }
    return LegacyPackedArray._(kind, dimensions, values);
  } on Object catch (error) {
    // Java catches Exception, but not VM Errors. Dart's range/type exceptions
    // are Error subclasses, so distinguish the VM failures explicitly.
    if (error is StackOverflowError || error is OutOfMemoryError) rethrow;
    onDiagnostic?.call('Mem_ReadArray.IO error');
    return null;
  }
}
