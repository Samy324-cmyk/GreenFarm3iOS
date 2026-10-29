import 'dart:typed_data';

import '../../engine/assets/asset_pack.dart';
import '../../engine/compat/legacy_packed_arrays.dart';
import '../../engine/storage/binary.dart';
import 'class_table.dart';
import 'map_placements.dart';

enum GameResourceKind {
  fontCharacterMap,
  classTable,
  guiLayout,
  tileIndices,
  tileTransforms,
  tileDimensions,
  mapCommands,
  unknown,
}

/// Classification from original load sites, not byte-signature guesses.
GameResourceKind resourceKind(int pack, int entry) {
  if ((pack == 2 || pack == 4) && entry == 7 ||
      pack == 3 && entry == 5 ||
      (pack == 5 || pack == 6) && entry == 3) {
    return GameResourceKind.fontCharacterMap;
  }
  if (pack == 13 && entry >= 0 && entry < 34) {
    return GameResourceKind.classTable;
  }
  if (pack == 10 && entry >= 0 && entry < 50) return GameResourceKind.guiLayout;
  if ((pack == 14 || pack == 15) && entry >= 0 && entry < 21) {
    return switch (entry) {
      0 => GameResourceKind.tileIndices,
      1 => GameResourceKind.tileTransforms,
      2 => GameResourceKind.tileDimensions,
      _ => GameResourceKind.mapCommands,
    };
  }
  return GameResourceKind.unknown;
}

List<int> decodeFontCharacterMap(Uint8List rawEntry) {
  final payload = gameDataPayload(rawEntry);
  // r3 intentionally accepts scalar EOF as -1. A font resource, unlike an
  // arbitrary legacy stream, has an independently known complete boundary.
  final header = BinaryReader(payload);
  final flags = header.readUint8();
  if (flags & 7 != 2) {
    throw const FormatException('Font map must be a one-dimensional int array');
  }
  final count = flags & 8 != 0 ? header.readUint16() : header.readUint8();
  final storage = flags >> 4;
  final width = storage == 0
      ? 1
      : storage == 1
      ? 2
      : 4;
  if (header.remaining != count * width) {
    throw const FormatException(
      'Font map payload length disagrees with header',
    );
  }
  final stream = LegacyInputStream(payload);
  final diagnostics = <String>[];
  final array = readLegacyPackedArray(stream, onDiagnostic: diagnostics.add);
  if (array == null ||
      diagnostics.isNotEmpty ||
      array.dimensions != 1 ||
      array.kind != LegacyArrayKind.integer ||
      stream.available != 0) {
    throw const FormatException('Invalid font character-map array');
  }
  return List<int>.unmodifiable(array.values.cast<int>());
}

/// cGame.Jv passes entries 2, 0 and 1 to t.h0. t.j0 reads two LE shorts
/// for dimensions. The final descriptor short is preserved, not interpreted.
class OriginalTileLayer {
  OriginalTileLayer._(
    this.width,
    this.height,
    this.descriptorTail,
    this.tileIds,
    this.transforms,
  );

  factory OriginalTileLayer.fromPack(GameAssetPack pack) {
    if (pack.length < 3) {
      throw const FormatException('Missing tile-layer entries');
    }
    return OriginalTileLayer.fromEntries(pack[0], pack[1], pack[2]);
  }

  factory OriginalTileLayer.fromEntries(
    Uint8List ids,
    Uint8List transforms,
    Uint8List dimensions,
  ) {
    final input = BinaryReader(gameDataPayload(dimensions));
    final width = input.readInt16();
    final height = input.readInt16();
    final tail = input.readBytes(input.remaining);
    final tileIds = gameDataPayload(ids);
    final tileTransforms = gameDataPayload(transforms);
    if (width <= 0 ||
        height <= 0 ||
        tileIds.length != width * height ||
        tileTransforms.length != width * height) {
      throw const FormatException(
        'Tile-layer dimensions disagree with cell bytes',
      );
    }
    return OriginalTileLayer._(
      width,
      height,
      tail.asUnmodifiableView(),
      Uint8List.fromList(tileIds).asUnmodifiableView(),
      Uint8List.fromList(tileTransforms).asUnmodifiableView(),
    );
  }

  final int width;
  final int height;
  final Uint8List descriptorTail;
  final Uint8List tileIds;
  final Uint8List transforms;

  int tileAt(int x, int y) {
    RangeError.checkValueInInterval(x, 0, width - 1, 'x');
    RangeError.checkValueInInterval(y, 0, height - 1, 'y');
    return tileIds[y * width + x];
  }
}

/// Explicit holder for formats whose runtime interpreter is still unported.
/// Keeping the raw entry prevents a caller from receiving fabricated defaults.
class UnsupportedGameResource implements Exception {
  UnsupportedGameResource(this.packId, this.entryId, Uint8List bytes)
    : rawEntry = Uint8List.fromList(bytes).asUnmodifiableView();
  final int packId;
  final int entryId;
  final Uint8List rawEntry;
  GameResourceKind get kind => resourceKind(packId, entryId);
  @override
  String toString() =>
      'Unported $kind interpreter for original resource $packId:$entryId';
}

/// Decodes formats with an established wire schema. GUI and event scripts
/// deliberately throw with their unchanged source bytes.
Object decodeKnownGameResource(int pack, int entry, Uint8List bytes) {
  return switch (resourceKind(pack, entry)) {
    GameResourceKind.fontCharacterMap => decodeFontCharacterMap(bytes),
    GameResourceKind.classTable => GameClassTable.fromEntry(entry, bytes),
    GameResourceKind.mapCommands
        when entry != 15 && entry != 17 && entry != 19 =>
      MapPlacementStream.fromEntry(bytes),
    GameResourceKind.tileIndices ||
    GameResourceKind.tileTransforms ||
    GameResourceKind.tileDimensions => Uint8List.fromList(
      gameDataPayload(bytes),
    ).asUnmodifiableView(),
    _ => throw UnsupportedGameResource(pack, entry, bytes),
  };
}
