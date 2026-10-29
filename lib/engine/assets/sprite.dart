import 'dart:typed_data';

import 'byte_reader.dart';

final class SpriteRect {
  const SpriteRect(this.x, this.y, this.width, this.height);
  final int x, y, width, height;
}

final class SpriteModule {
  const SpriteModule({
    required this.type,
    this.image = 0,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.color,
    this.extra = const [],
  });
  final int type, image, x, y, width, height;

  /// Original ARGB integer for vector modules; absent for bitmap modules.
  final int? color;
  final List<int> extra;
  bool get isBitmap => type == 0;
}

final class SpriteFrameModule {
  const SpriteFrameModule({
    required this.rawIndex,
    required this.index,
    required this.x,
    required this.y,
    required this.flags,
    this.palette = 0,
    this.extra = const [],
  });
  final int rawIndex, index, x, y, flags, palette;
  final List<int> extra;
  bool get isHyperFrame => flags & 16 != 0;
}

final class SpriteFrame {
  const SpriteFrame({
    required this.count,
    required this.start,
    this.extraRectStart = 0,
    this.extraRectCount = 0,
    this.bounds,
    this.collision,
  });
  final int count, start, extraRectStart, extraRectCount;
  final SpriteRect? bounds, collision;
}

final class SpriteAnimationFrame {
  const SpriteAnimationFrame({
    required this.frame,
    required this.time,
    required this.x,
    required this.y,
    required this.flags,
  });
  final int frame, time, x, y, flags;
}

final class SpriteAnimation {
  const SpriteAnimation(this.count, this.start);
  final int count, start;
}

final class SpriteAtlas {
  const SpriteAtlas({
    required this.paletteCount,
    required this.colorCount,
    required this.paletteData,
    required this.width,
    required this.height,
    required this.encodedPixels,
  });
  final int paletteCount, colorCount, width, height;
  final Uint8List paletteData, encodedPixels;
}

/// ASprite 0x05df, preserving original resource, module, frame and animation IDs.
/// This implements every sprite variant present in the supplied 4.4.4 APK.
final class GameSprite {
  const GameSprite._({
    required this.flags,
    required this.extraFlags,
    required this.modules,
    required this.frameModules,
    required this.frames,
    required this.extraRectangles,
    required this.animationFrames,
    required this.animations,
    required this.pixelFormat,
    required this.encoding,
    required this.atlases,
  });
  final int flags, extraFlags, pixelFormat, encoding;
  final List<SpriteModule> modules;
  final List<SpriteFrameModule> frameModules;
  final List<SpriteFrame> frames;
  final List<SpriteRect> extraRectangles;
  final List<SpriteAnimationFrame> animationFrames;
  final List<SpriteAnimation> animations;
  final List<SpriteAtlas> atlases;

  factory GameSprite.parse(
    Uint8List bytes, {
    bool extendModuleIndices = false,
    bool extendAnimationIndices = false,
  }) {
    final r = AssetReader(bytes);
    if (r.u8() != 2 || r.u16() != 0x05df) r.fail('Unsupported sprite version');
    final flags = r.u32();
    final extraFlags = flags & 0x400000 != 0 ? r.u32() : 0;
    // All original sprites use palette-encoded atlas images (ASprite.W0).
    // Fail explicitly rather than misreading a different BSprite exporter.
    if (extraFlags & 0x100000 == 0 ||
        flags & 0x20000000 != 0 ||
        extraFlags & ~0x100010 != 0) {
      r.fail('Unsupported sprite image layout');
    }
    final modules = <SpriteModule>[];
    final moduleCount = r.u16();
    for (var i = 0; i < moduleCount; i++) {
      final type = r.u8();
      var image = 0, x = 0, y = 0, width = 0, height = 0;
      int? color;
      final extra = <int>[];
      if (type == 0) {
        image = flags & 4 != 0 ? r.u8() : 0;
        if (flags & 32 != 0) {
          x = r.u16();
          y = r.u16();
        } else if (flags & 2 != 0) {
          x = r.u8();
          y = r.u8();
        }
      } else if (const [255, 254, 252, 251, 250, 249, 248].contains(type)) {
        color = r.u32();
      } else if (type != 253) {
        r.fail('Unsupported module type $type');
      }
      if (const [0, 255, 254, 253, 252, 251, 248].contains(type)) {
        width = flags & 16 != 0 ? r.u16() : r.u8();
        height = flags & 16 != 0 ? r.u16() : r.u8();
      }
      if (type == 252 || type == 251) extra.addAll([r.i16(), r.i16()]);
      if (type == 250 || type == 249) {
        extra.addAll([r.i16(), r.i16(), r.i16(), r.i16()]);
      }
      modules.add(
        SpriteModule(
          type: type,
          image: image,
          x: x,
          y: y,
          width: width,
          height: height,
          color: color,
          extra: List.unmodifiable(extra),
        ),
      );
    }
    final frameModules = <SpriteFrameModule>[];
    final frameModuleCount = r.u16();
    for (var i = 0; i < frameModuleCount; i++) {
      final rawIndex = flags & 0x100000 != 0 ? r.u16() : r.u8();
      final x = flags & 0x400 != 0 ? r.i16() : r.i8();
      final y = flags & 0x400 != 0 ? r.i16() : r.i8();
      final palette = flags & 0x4000 != 0 ? r.u8() : 0;
      final fmFlags = r.u8();
      final extra = extraFlags & 16 != 0 ? [r.u8(), r.u8()] : <int>[];
      // ASprite.Z extends an 8-bit module ID with the flag byte's high bits.
      final index = !extendModuleIndices || flags & 0x100000 != 0
          ? rawIndex
          : rawIndex | ((fmFlags & 192) << 2);
      frameModules.add(
        SpriteFrameModule(
          rawIndex: rawIndex,
          index: index,
          x: x,
          y: y,
          flags: fmFlags,
          palette: palette,
          extra: List.unmodifiable(extra),
        ),
      );
    }
    SpriteRect rect() {
      if (flags & 0x400 != 0) {
        return SpriteRect(r.i16(), r.i16(), r.u16(), r.u16());
      }
      return SpriteRect(r.i8(), r.i8(), r.u8(), r.u8());
    }

    final extraRects = <SpriteRect>[];
    if (flags & 0x8000 != 0) {
      final count = r.u16();
      for (var i = 0; i < count; i++) {
        extraRects.add(rect());
      }
    }
    final frameCount = r.u16();
    final counts = <int>[], starts = <int>[], rectCounts = <int>[];
    for (var i = 0; i < frameCount; i++) {
      counts.add(flags & 0x800 != 0 ? r.u16() : r.u8());
      starts.add(r.u16());
      rectCounts.add(flags & 0x8000 != 0 ? r.u8() : 0);
    }
    final bounds = <SpriteRect?>[], collisions = <SpriteRect?>[];
    for (var i = 0; i < frameCount; i++) {
      bounds.add(flags & 0x1000 == 0 ? rect() : null);
    }
    for (var i = 0; i < frameCount; i++) {
      collisions.add(flags & 0x2000 != 0 ? rect() : null);
    }
    final frames = <SpriteFrame>[];
    var rectStart = 0;
    for (var i = 0; i < frameCount; i++) {
      if (starts[i] + counts[i] > frameModules.length) {
        r.fail('Frame points outside module table');
      }
      if (rectStart + rectCounts[i] > extraRects.length) {
        r.fail('Frame points outside rectangle table');
      }
      frames.add(
        SpriteFrame(
          count: counts[i],
          start: starts[i],
          extraRectStart: rectStart,
          extraRectCount: rectCounts[i],
          bounds: bounds[i],
          collision: collisions[i],
        ),
      );
      rectStart += rectCounts[i];
    }
    final animationFrames = <SpriteAnimationFrame>[];
    final animationFrameCount = r.u16();
    for (var i = 0; i < animationFrameCount; i++) {
      final rawFrame = flags & 0x200000 != 0 ? r.u16() : r.u8();
      final time = r.u8();
      final x = flags & 0x40000 != 0 ? r.i16() : r.i8();
      final y = flags & 0x40000 != 0 ? r.i16() : r.i8();
      final afFlags = r.u8();
      final frame = !extendAnimationIndices || flags & 0x200000 != 0
          ? rawFrame
          : rawFrame | ((afFlags & 192) << 2);
      // Original sprite 11:28 contains frame 255 with six visual frames.
      // Preserve these references without inferring their runtime semantics.
      // A caller must resolve them using the original game logic before paint.
      animationFrames.add(
        SpriteAnimationFrame(
          frame: frame,
          time: time,
          x: x,
          y: y,
          flags: afFlags,
        ),
      );
    }
    final animations = <SpriteAnimation>[];
    final animationCount = r.u16();
    for (var i = 0; i < animationCount; i++) {
      final count = flags & 0x80000 != 0 ? r.u16() : r.u8();
      final start = r.u16();
      if (start + count > animationFrames.length) {
        r.fail('Animation points outside frame table');
      }
      animations.add(SpriteAnimation(count, start));
    }
    final pixelFormat = r.u16(), encoding = r.u16(), imageCount = r.u8();
    final colorBytes = switch (pixelFormat) {
      0x8888 => 4,
      0x8808 => 3,
      0x4444 || 0x5515 => 2,
      _ => 0,
    };
    if (colorBytes == 0) {
      r.fail('Unknown palette pixel format 0x${pixelFormat.toRadixString(16)}');
    }
    final paletteCounts = <int>[], colorCounts = <int>[];
    final paletteData = <Uint8List>[];
    for (var i = 0; i < imageCount; i++) {
      final palettes = r.u8();
      final colorsByte = r.u8();
      final colors = colorsByte == 0 ? 256 : colorsByte;
      if (palettes == 0) r.fail('An atlas requires at least one palette');
      paletteCounts.add(palettes);
      colorCounts.add(colors);
      paletteData.add(r.take(palettes * colors * colorBytes));
    }
    final atlases = <SpriteAtlas>[];
    for (var i = 0; i < imageCount; i++) {
      final width = r.u16(), height = r.u16(), bytes = r.u32();
      if (width == 0 || height == 0 || width * height > 16777216) {
        r.fail('Invalid atlas dimensions');
      }
      atlases.add(
        SpriteAtlas(
          paletteCount: paletteCounts[i],
          colorCount: colorCounts[i],
          paletteData: paletteData[i],
          width: width,
          height: height,
          encodedPixels: r.take(bytes),
        ),
      );
    }
    r.end();
    for (final module in modules) {
      if (module.isBitmap) {
        if (module.image >= atlases.length) {
          r.fail('Module refers to missing atlas');
        }
        final atlas = atlases[module.image];
        if (module.x + module.width > atlas.width ||
            module.y + module.height > atlas.height) {
          r.fail('Module lies outside atlas');
        }
      }
    }
    for (final module in frameModules) {
      if (module.index >=
          (module.isHyperFrame ? frames.length : modules.length)) {
        r.fail('Invalid frame module reference');
      }
    }
    return GameSprite._(
      flags: flags,
      extraFlags: extraFlags,
      modules: List.unmodifiable(modules),
      frameModules: List.unmodifiable(frameModules),
      frames: List.unmodifiable(frames),
      extraRectangles: List.unmodifiable(extraRects),
      animationFrames: List.unmodifiable(animationFrames),
      animations: List.unmodifiable(animations),
      pixelFormat: pixelFormat,
      encoding: encoding,
      atlases: List.unmodifiable(atlases),
    );
  }
}
