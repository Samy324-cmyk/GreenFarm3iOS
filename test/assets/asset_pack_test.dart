import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:green_farm_port/engine/assets/assets.dart';

void main() {
  test('actual original pack 12 resolves the original sprite entry', () {
    final pack = GameAssetPack.parse(
      File('test/assets/fixtures/pack_12.bin').readAsBytesSync(),
    );
    expect(pack.length, 1);
    final sprite = GameSprite.parse(pack[0]);
    expect(sprite.modules.length, 7);
    expect(sprite.atlases.length, 1);
  });

  test('two shards preserve global IDs and original entry bytes', () {
    // Two global entries, shard starts [0,1]; first shard header is16 bytes.
    final first = Uint8List.fromList([
      2,
      0,
      2,
      0,
      0,
      0,
      1,
      0,
      16,
      0,
      0,
      0,
      19,
      0,
      0,
      0,
      2,
      223,
      5,
    ]);
    final second = Uint8List.fromList([8, 0, 0, 0, 10, 0, 0, 0, 7, 8]);
    final pack = GameAssetPack.parse(first, shards: {1: second});
    expect(pack[0], [2, 223, 5]);
    expect(pack[1], [7, 8]);
    expect(() => GameAssetPack.parse(first), throwsFormatException);
    expect(
      () => GameAssetPack.parse(first, shards: {2: second}),
      throwsFormatException,
    );
  });

  test('pack bounds reject truncated or unordered indices', () {
    final original = File('test/assets/fixtures/pack_12.bin').readAsBytesSync();
    expect(
      () => GameAssetPack.parse(
        Uint8List.sublistView(original, 0, original.length - 1),
      ),
      throwsFormatException,
    );
    final badStart = Uint8List.fromList(original)..[6] = 0;
    expect(() => GameAssetPack.parse(badStart), throwsFormatException);
    final badSize = Uint8List.fromList(original)..[10] = 0;
    expect(() => GameAssetPack.parse(badSize), throwsFormatException);
  });
}
