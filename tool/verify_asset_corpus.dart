// Usage: dart run tool/verify_asset_corpus.dart <original/assets/800x480>
// Compares the real binary packs with RGBA checksums of independently exported
// reference PNGs. No emulator, native binaries or network services are invoked.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:green_farm_port/engine/assets/assets.dart';

final _crcTable = List.generate(256, (value) {
  var crc = value;
  for (var i = 0; i < 8; i++) {
    crc = crc & 1 != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
  }
  return crc;
});
int crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 255] ^ (crc >> 8);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

void require(bool condition, String error) {
  if (!condition) throw StateError(error);
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/verify_asset_corpus.dart <original/assets/800x480>',
    );
    exitCode = 64;
    return;
  }
  final directory = Directory(arguments.single);
  final manifest = jsonDecode(
    File('test/assets/fixtures/corpus_manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final packs = <String, GameAssetPack>{};
  GameAssetPack pack(String name) => packs.putIfAbsent(name, () {
    final first = File('${directory.path}/$name').readAsBytesSync();
    final count = ByteData.sublistView(first).getUint16(2, Endian.little);
    final shards = <int, Uint8List>{};
    for (var i = 1; i < count; i++) {
      shards[i] = File('${directory.path}/$name.$i').readAsBytesSync();
    }
    return GameAssetPack.parse(first, shards: shards);
  });
  var sprites = 0, images = 0, rgbaBytes = 0;
  for (final expected in manifest['sprites'] as List<dynamic>) {
    final id = (expected['id'] as String).split(':');
    final sprite = GameSprite.parse(pack(id[0])[int.parse(id[1])]);
    final actual = {
      'modules': sprite.modules.length,
      'frame_modules': sprite.frameModules.length,
      'frames': sprite.frames.length,
      'animation_frames': sprite.animationFrames.length,
      'animations': sprite.animations.length,
      'flags': sprite.flags,
      'extra_flags': sprite.extraFlags,
      'pixel_format': sprite.pixelFormat,
      'encoding': sprite.encoding,
    };
    for (final entry in actual.entries) {
      require(
        entry.value == expected[entry.key],
        '${expected['id']} ${entry.key} differs',
      );
    }
    for (final image in expected['images'] as List<dynamic>) {
      final pixels = SpriteCodec.decodeAtlas(
        sprite,
        image['image'] as int,
        palette: image['palette'] as int,
      );
      require(
        pixels.width == image['w'] && pixels.height == image['h'],
        '${expected['id']} image bounds differ',
      );
      require(
        pixels.rgba.length == image['rgba_bytes'] &&
            crc32(pixels.rgba) == image['crc32'],
        '${expected['id']} image ${image['image']} palette ${image['palette']} RGBA mismatch',
      );
      images++;
      rgbaBytes += pixels.rgba.length;
    }
    sprites++;
  }
  var strings = 0;
  const languages = [
    'BR',
    'DE',
    'EN',
    'ES',
    'FR',
    'IT',
    'JP',
    'KR',
    'LATAM',
    'PL',
    'RU',
    'TH',
    'TR',
    'VI',
  ];
  for (final language in languages) {
    final catalog = GameTextCatalog.fromPack(pack(language));
    require(
      catalog.groups.length == 13 && catalog.length == 4480,
      '$language text count differs',
    );
    strings += catalog.length;
  }
  require(sprites == 352 && images == 516, 'Corpus is incomplete');
  stdout.writeln(
    jsonEncode({
      'sprites': sprites,
      'atlasPalettes': images,
      'rgbaBytesCompared': rgbaBytes,
      'languages': languages.length,
      'strings': strings,
      'status': 'passed',
    }),
  );
}
