import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:green_farm_port/engine/assets/assets.dart';

void main() {
  const fixture = 'test/assets/fixtures';
  final cases = jsonDecode(
    File('$fixture/sprites.json').readAsStringSync(),
  ) as List<dynamic>;
  for (final value in cases) {
    final expected = value as Map<String, dynamic>;
    test(
      'original ${expected['file']} metadata and every palette match reference bytes',
      () {
        final sprite = GameSprite.parse(
          File('$fixture/${expected['file']}').readAsBytesSync(),
        );
        expect(sprite.flags, expected['flags']);
        expect(sprite.extraFlags, expected['extra_flags']);
        expect(sprite.modules.length, expected['module_count']);
        expect(sprite.frameModules.length, expected['frame_module_count']);
        expect(sprite.frames.length, expected['frame_count']);
        expect(
          sprite.animationFrames.length,
          expected['animation_frame_count'],
        );
        expect(sprite.animations.length, expected['animation_count']);
        expect(sprite.pixelFormat, expected['pixel_format']);
        expect(sprite.encoding, expected['encoding']);
        for (var i = 0; i < sprite.frames.length; i++) {
          final frame = sprite.frames[i];
          final ef = expected['frames'][i] as Map<String, dynamic>;
          expect(
            [frame.count, frame.start, frame.extraRectCount],
            [ef['count'], ef['start'], ef['extra'] ?? 0],
          );
          if (ef['bounds'] != null) {
            final b = ef['bounds'] as List<dynamic>;
            final mask = sprite.flags & 0x400 == 0 ? 255 : 65535;
            expect(
              [
                frame.bounds!.x,
                frame.bounds!.y,
                frame.bounds!.width,
                frame.bounds!.height,
              ],
              [b[0], b[1], (b[2] as int) & mask, (b[3] as int) & mask],
            );
          }
        }
        for (var i = 0; i < sprite.animationFrames.length; i++) {
          final af = sprite.animationFrames[i];
          final e = expected['animation_frames'][i];
          expect(
            [af.frame, af.time, af.x, af.y, af.flags],
            [e['frame'], e['time'], e['x'], e['y'], e['flags']],
          );
        }
        for (var i = 0; i < sprite.animations.length; i++) {
          final animation = sprite.animations[i];
          expect(
            [animation.count, animation.start],
            [
              expected['animations'][i]['count'],
              expected['animations'][i]['start'],
            ],
          );
        }
        for (final image in expected['images'] as List<dynamic>) {
          final actual = SpriteCodec.decodeAtlas(
            sprite,
            image['image'] as int,
            palette: image['palette'] as int,
          );
          expect([actual.width, actual.height], [image['w'], image['h']]);
          expect(
            actual.rgba,
            orderedEquals(
              File('$fixture/${image['golden']}').readAsBytesSync(),
            ),
          );
        }
      },
    );
  }

  test('original 11:28 frame 255 remains unchanged', () {
    final sprite = GameSprite.parse(
      File('$fixture/11_028.bin').readAsBytesSync(),
    );
    expect(sprite.frames.length, 6);
    expect(
      sprite.animationFrames.skip(8).map((frame) => frame.frame),
      everyElement(255),
    );
    expect(sprite.animationFrames[8].time, 2);
    expect(sprite.animationFrames[8].y, 1);
  });

  test(
    'sprite reader rejects truncation, trailing bytes, and unsupported version',
    () {
      final data = File('$fixture/9_187.bin').readAsBytesSync();
      for (final end in [0, 1, 2, 5, 11, data.length - 1]) {
        expect(
          () => GameSprite.parse(Uint8List.sublistView(data, 0, end)),
          throwsFormatException,
        );
      }
      expect(
        () => GameSprite.parse(Uint8List.fromList([...data, 0])),
        throwsFormatException,
      );
      final bad = Uint8List.fromList(data)..[1] = 0;
      expect(() => GameSprite.parse(bad), throwsFormatException);
    },
  );

  test('packed one-bit index order and final-byte padding follow ASprite', () {
    final image = SpriteCodec.decodeIndices(
      Uint8List.fromList([0xa6, 0x80]),
      encoding: 0x200,
      pixelCount: 9,
      colorCount: 2,
    );
    expect(image.indices, [1, 0, 1, 0, 0, 1, 1, 0, 1]);
  });

  test(
    'image decoder rejects run overflow, palette overflow and incomplete data',
    () {
      expect(
        () => SpriteCodec.decodeIndices(
          Uint8List.fromList([0xff]),
          encoding: 0x64f0,
          pixelCount: 1,
          colorCount: 2,
        ),
        throwsFormatException,
      );
      expect(
        () => SpriteCodec.decodeIndices(
          Uint8List.fromList([2]),
          encoding: 0x5602,
          pixelCount: 1,
          colorCount: 2,
        ),
        throwsFormatException,
      );
      expect(
        () => SpriteCodec.decodeIndices(
          Uint8List.fromList([255]),
          encoding: 0xa562,
          pixelCount: 1,
          colorCount: 2,
        ),
        throwsFormatException,
      );
      expect(
        () => SpriteCodec.decodeIndices(
          Uint8List.fromList([0, 0]),
          encoding: 0x5602,
          pixelCount: 1,
          colorCount: 2,
        ),
        throwsFormatException,
      );
      expect(
        () => SpriteCodec.decodeIndices(
          Uint8List(0),
          encoding: 123,
          pixelCount: 1,
          colorCount: 2,
        ),
        throwsFormatException,
      );
    },
  );

  test('RLE256 zero count follows original do/while behavior', () {
    final indices = SpriteCodec.decodeIndices(
      Uint8List.fromList([0x80, 2, 0, 1]),
      encoding: 0x56f2,
      pixelCount: 2,
      colorCount: 3,
    );
    expect(indices.indices, [2, 1]);
  });
}
