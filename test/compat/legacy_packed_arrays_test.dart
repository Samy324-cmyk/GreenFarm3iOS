import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/compat/legacy_packed_arrays.dart';

LegacyPackedArray decode(List<int> bytes) {
  final stream = LegacyInputStream(Uint8List.fromList(bytes));
  final result = readLegacyPackedArray(stream)!;
  expect(stream.bytesRead, bytes.length);
  expect(stream.position, bytes.length);
  return result;
}

void main() {
  test('stream helpers retain little-endian order and signed int32', () {
    final stream = LegacyInputStream(
      Uint8List.fromList([0x34, 0x12, 0x78, 0x56, 0x34, 0x92]),
    );
    expect(stream.readUint16(), 0x1234);
    expect(stream.readInt32(), 0x92345678.toSigned(32));
    expect(stream.bytesRead, 6);
    expect(stream.read(), -1);
    expect(stream.read(), -1);
    expect(stream.bytesRead, 6);
    expect(stream.position, 6);
  });

  test('byte arrays and signed byte widening', () {
    expect(decode([0, 3, 0, 127, 255]).toLists(), [0, 127, -1]);
    final shorts = decode([1, 2, 255, 128]);
    expect(shorts.values, isA<Int16List>());
    expect(shorts.toLists(), [-1, -128]);
    final ints = decode([2, 2, 255, 128]);
    expect(ints.values, isA<Int32List>());
    expect(ints.toLists(), [-1, -128]);
  });

  test('short and int storage widths', () {
    expect(decode([0x11, 2, 0x34, 0x12, 255, 255]).toLists(), [0x1234, -1]);
    expect(decode([0x12, 2, 0, 128, 255, 127]).toLists(), [-32768, 32767]);
    expect(decode([0x22, 2, 0x78, 0x56, 0x34, 0x12, 0, 0, 0, 128]).toLists(), [
      0x12345678,
      -2147483648,
    ]);
  });

  test('2D and 3D arrays preserve scalar kind and child dimensions', () {
    final bytes = decode([0x24, 2, 0, 2, 1, 2, 0, 1, 255]);
    expect(bytes.kind, LegacyArrayKind.byte);
    expect(bytes.dimensions, 2);
    expect(bytes.toLists(), [
      [1, 2],
      [-1],
    ]);
    expect(decode([0x25, 1, 0x11, 1, 0x34, 0x12]).toLists(), [
      [0x1234],
    ]);
    expect(decode([0x36, 1, 0x26, 1, 2, 1, 255]).toLists(), [
      [
        [-1],
      ],
    ]);
  });

  test('extended little-endian lengths allow more than 255 elements', () {
    expect(decode([8, 0, 1, ...List.filled(256, 0)]).length, 256);
  });

  test('scalar EOF is preserved rather than a strict EOF exception', () {
    final stream = LegacyInputStream(Uint8List.fromList([0, 3, 17]));
    expect(readLegacyPackedArray(stream)!.toLists(), [17, -1, -1]);
    expect(stream.bytesRead, 3);
    final short = LegacyInputStream(Uint8List.fromList([0x11, 1, 0x34]));
    expect(readLegacyPackedArray(short)!.toLists(), [0xff34.toSigned(16)]);
    expect(short.bytesRead, 3);
    final wide = LegacyInputStream(Uint8List.fromList([0x22, 1, 0x34]));
    expect(readLegacyPackedArray(wide)!.toLists(), [0xffffff34.toSigned(32)]);
  });

  test(
    'invalid length, null input and nested type mismatch use error path',
    () {
      final diagnostics = <String>[];
      expect(
        readLegacyPackedArray(
          LegacyInputStream(Uint8List.fromList([0])),
          onDiagnostic: diagnostics.add,
        ),
        isNull,
      );
      expect(diagnostics, ['Mem_ReadArray.IO error']);
      diagnostics.clear();
      expect(
        readLegacyPackedArray(null, onDiagnostic: diagnostics.add),
        isNull,
      );
      expect(diagnostics, [
        'Mem_ReadArray.is is null',
        'Mem_ReadArray.IO error',
      ]);
      expect(
        readLegacyPackedArray(
          LegacyInputStream(Uint8List.fromList([0x24, 1, 2, 1, 1])),
        ),
        isNull,
      );
    },
  );
}
