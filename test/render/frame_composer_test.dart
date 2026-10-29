import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/assets/sprite.dart';
import 'package:green_farm_port/engine/render/frame_composer.dart';

// Minimal valid synthetic ASprite binary. No source-art replacement is shipped.
GameSprite fixture({
  List<SpriteModule> modules = const [
    SpriteModule(type: 0, width: 10, height: 20),
  ],
  List<SpriteFrameModule> entries = const [
    SpriteFrameModule(rawIndex: 0, index: 0, x: 3, y: 5, flags: 0),
  ],
  List<SpriteFrame> frames = const [SpriteFrame(count: 1, start: 0)],
  List<SpriteAnimationFrame> animationFrames = const [],
  List<SpriteAnimation> animations = const [],
  bool framePalettes = false,
}) {
  final data = BytesBuilder();
  void u8(int value) => data.add([value & 255]);
  void u16(int value) {
    final b = ByteData(2)..setUint16(0, value & 65535, Endian.little);
    data.add(b.buffer.asUint8List());
  }

  void u32(int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    data.add(b.buffer.asUint8List());
  }

  u8(2);
  u16(0x05df);
  u32(0x400000 | 0x1000 | 0x400 | 0x20 | 0x10 | (framePalettes ? 0x4000 : 0));
  u32(0x100000);
  u16(modules.length);
  for (final m in modules) {
    u8(m.type);
    if (m.type == 0) {
      u16(m.x);
      u16(m.y);
    } else if (m.type != 253) {
      u32(m.color ?? 0xffffffff);
    }
    if (const [0, 255, 254, 253, 252, 251, 248].contains(m.type)) {
      u16(m.width);
      u16(m.height);
    }
    for (final value in m.extra) {
      u16(value);
    }
  }
  u16(entries.length);
  for (final entry in entries) {
    u8(entry.index);
    u16(entry.x);
    u16(entry.y);
    if (framePalettes) u8(entry.palette);
    u8(entry.flags);
  }
  u16(frames.length);
  for (final frame in frames) {
    u8(frame.count);
    u16(frame.start);
  }
  u16(animationFrames.length);
  for (final entry in animationFrames) {
    u8(entry.frame);
    u8(entry.time);
    u8(entry.x);
    u8(entry.y);
    u8(entry.flags);
  }
  u16(animations.length);
  for (final animation in animations) {
    u8(animation.count);
    u16(animation.start);
  }
  u16(0x8808);
  u16(0x5602);
  u8(1);
  u8(2);
  u8(1);
  data.add([255, 255, 255, 0, 0, 0]);
  u16(64);
  u16(64);
  u32(0);
  return GameSprite.parse(data.toBytes());
}

void main() {
  const composer = FrameComposer();
  test('eight parent transforms preserve l1 offsets and transform lookup', () {
    final instance = SpriteInstance(fixture());
    const positions = [
      [103, 205],
      [87, 205],
      [103, 175],
      [87, 175],
      [75, 203],
      [75, 187],
      [105, 203],
      [105, 187],
    ];
    const j2me = [0, 2, 1, 3, 5, 7, 4, 6];
    for (var flags = 0; flags < 8; flags++) {
      final command = composer
          .composeFrame(instance, 0, x: 100, y: 200, flags: flags)
          .single;
      expect([command.x, command.y], positions[flags]);
      expect(command.flags, flags);
      expect(command.j2meTransform, j2me[flags]);
      expect([
        command.width,
        command.height,
      ], flags & 4 == 0 ? [10, 20] : [20, 10]);
    }
  });

  test('parent reflection composes with already-rotated frame module', () {
    final instance = SpriteInstance(
      fixture(
        entries: const [
          SpriteFrameModule(rawIndex: 0, index: 0, x: 3, y: 5, flags: 4),
        ],
      ),
    );
    final command = composer
        .composeFrame(instance, 0, x: 100, y: 200, flags: 1)
        .single;
    expect([command.x, command.y, command.flags], [77, 205, 6]);
  });

  test(
    'k1 animation offsets are transformed as points before frame extent',
    () {
      final instance = SpriteInstance(
        fixture(
          animationFrames: const [
            SpriteAnimationFrame(frame: 0, time: 2, x: 7, y: 11, flags: 2),
          ],
          animations: const [SpriteAnimation(1, 0)],
        ),
      );
      final command = composer
          .composeAnimationFrame(instance, 0, 0, x: 10, y: 20, flags: 1)
          .single;
      expect([command.x, command.y, command.flags], [-10, 6, 3]);
    },
  );

  test('hyperframes recurse with zero extents and module painter order', () {
    const recursive = FrameComposer(
      config: SpriteCompositionConfig(hyperFrames: true),
    );
    final instance = SpriteInstance(
      fixture(
        entries: const [
          SpriteFrameModule(rawIndex: 1, index: 1, x: 7, y: 9, flags: 16),
          SpriteFrameModule(rawIndex: 0, index: 0, x: 3, y: 5, flags: 0),
        ],
        frames: const [
          SpriteFrame(count: 1, start: 0),
          SpriteFrame(count: 1, start: 1),
        ],
      ),
    );
    final command = recursive
        .composeFrame(instance, 0, x: 100, y: 200, flags: 1)
        .single;
    expect([command.x, command.y, command.flags], [80, 214, 1]);
    instance.paintMode = 2;
    expect(recursive.composeFrame(instance, 0), hasLength(1));
    instance.paintMode = 1;
    expect(recursive.composeFrame(instance, 0), isEmpty);
  });

  test('cycles and invalid frame references fail, no sentinel is invented', () {
    const recursive = FrameComposer(
      config: SpriteCompositionConfig(hyperFrames: true),
    );
    final instance = SpriteInstance(
      fixture(
        entries: const [
          SpriteFrameModule(rawIndex: 0, index: 0, x: 0, y: 0, flags: 16),
        ],
      ),
    );
    expect(() => recursive.composeFrame(instance, 0), throwsStateError);
    final original = SpriteInstance(
      GameSprite.parse(
        File('test/assets/fixtures/11_028.bin').readAsBytesSync(),
      ),
    );
    expect(() => composer.composeFrame(original, 255), throwsRangeError);
    expect(
      () => composer.composeAnimationFrame(original, 1, 0),
      throwsRangeError,
    );
  });

  test('palette default is global; enabled module palettes mutate image0', () {
    final instance = SpriteInstance(
      fixture(
        framePalettes: true,
        entries: const [
          SpriteFrameModule(
            rawIndex: 0,
            index: 0,
            x: 0,
            y: 0,
            flags: 0,
            palette: 1,
          ),
        ],
      ),
    );
    expect(composer.composeFrame(instance, 0).single.palette, 0);
    const paletted = FrameComposer(
      config: SpriteCompositionConfig(frameModulePalettes: true),
    );
    expect(paletted.composeFrame(instance, 0).single.palette, 1);
    expect(instance.palettes, [1]);
    instance.setPaletteAll(0);
    instance.loadFlags = 16;
    expect(paletted.composeFrame(instance, 0).single.palette, 0);
    instance.setPaletteAll(999);
    expect(instance.palettes, [0]);
  });

  test(
    'module and cross-sprite frame mappings retain target palette and offset',
    () {
      final source = SpriteInstance(fixture());
      final target = SpriteInstance(
        fixture(
          modules: const [
            SpriteModule(type: 0, width: 10, height: 20),
            SpriteModule(type: 0, x: 20, width: 30, height: 12),
          ],
        ),
      );
      target.moduleMappings[0] = const SpriteModuleMapping(1, x: 4, y: -2);
      source.frameMappings[0] = SpriteFrameMapping(
        target: target,
        frameOffset: 0,
        palette: 1,
      );
      const mapped = FrameComposer(
        config: SpriteCompositionConfig(
          moduleMapping: true,
          frameMapping: true,
        ),
      );
      final command = mapped.composeFrame(source, 0, flags: 1).single;
      expect(command.instance, same(target));
      expect(
        [command.moduleIndex, command.palette, command.x, command.y],
        [1, 1, -37, 3],
      );
    },
  );

  test(
    'vector and marker commands retain source identity instead of placeholders',
    () {
      final instance = SpriteInstance(
        fixture(
          modules: const [
            SpriteModule(type: 254, width: 12, height: 8, color: 0x80445566),
            SpriteModule(type: 253, width: 2, height: 4),
          ],
          entries: const [
            SpriteFrameModule(rawIndex: 0, index: 0, x: 0, y: 0, flags: 0),
            SpriteFrameModule(rawIndex: 1, index: 1, x: 0, y: 0, flags: 0),
          ],
          frames: const [SpriteFrame(count: 2, start: 0)],
        ),
      );
      final commands = composer.composeFrame(instance, 0);
      expect(commands.map((c) => c.kind), [
        SpriteCommandKind.vector,
        SpriteCommandKind.marker,
      ]);
      expect(commands.first.module.color, 0x80445566);
    },
  );

  test('unported GLLib effects are explicit failures', () {
    final instance = SpriteInstance(fixture());
    expect(
      () => composer.composeFrame(instance, 0, effectMask: 0x40000),
      throwsUnsupportedError,
    );
  });

  for (final file
      in Directory('test/assets/fixtures')
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'[/\\](9|11)_\d+\.bin$').hasMatch(f.path))) {
    test(
      'all original frames in ${file.uri.pathSegments.last} compose in painter order',
      () {
        final instance = SpriteInstance(
          GameSprite.parse(file.readAsBytesSync()),
        );
        for (var i = 0; i < instance.sprite.frames.length; i++) {
          final commands = composer.composeFrame(instance, i);
          expect(commands.length, instance.sprite.frames[i].count);
          expect(
            commands.map((c) => c.moduleIndex),
            instance.sprite.frameModules
                .skip(instance.sprite.frames[i].start)
                .take(instance.sprite.frames[i].count)
                .map((m) => m.index),
          );
        }
      },
    );
  }
}
