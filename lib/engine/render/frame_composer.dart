import '../assets/sprite.dart';

/// ASprite's exact transform-composition lookup tables (m, n, o, l).
const _flipHorizontal = [1, 0, 3, 2, 6, 7, 4, 5];
const _flipVertical = [2, 3, 0, 1, 5, 4, 7, 6];
const _rotateClockwise = [4, 5, 6, 7, 3, 2, 1, 0];
const _j2meTransforms = [0, 2, 1, 3, 5, 7, 4, 6];

/// Feature switches default to the supplied APK's GLLibConfig values.
final class SpriteCompositionConfig {
  const SpriteCompositionConfig({
    this.hyperFrames = false,
    this.frameModulePalettes = false,
    this.moduleMapping = false,
    this.frameMapping = false,
    this.markerMasks = false,
    this.markerCallbacks = false,
  });

  final bool hyperFrames;
  final bool frameModulePalettes;
  final bool moduleMapping;
  final bool frameMapping;
  final bool markerMasks;
  final bool markerCallbacks;
}

final class SpriteModuleMapping {
  const SpriteModuleMapping(this.module, {this.x = 0, this.y = 0});
  final int module;
  final int x, y;
}

/// ASprite's O0/P0/Q0/R0 configuration, resolved by original frame index.
final class SpriteFrameMapping {
  const SpriteFrameMapping({
    required this.target,
    required this.frameOffset,
    required this.palette,
  });

  final SpriteInstance target;
  final int frameOffset, palette;
}

/// Mutable ASprite draw state, separate from immutable exported asset data.
final class SpriteInstance {
  SpriteInstance(this.sprite)
    : palettes = List.filled(sprite.atlases.length, 0);

  final GameSprite sprite;
  final List<int> palettes;
  final Map<int, SpriteModuleMapping> moduleMappings = {};
  final Map<int, SpriteFrameMapping> frameMappings = {};

  /// Original n1: 0=all, 1=modules, 2=hyperframes.
  int paintMode = 0;

  /// Original g1 load flags. Bit 16 suppresses per-frame-module palettes.
  int loadFlags = 0;

  /// ASprite.z1 ignores out-of-range palettes without changing current state.
  void setPalette(int image, int palette) {
    RangeError.checkValidIndex(image, palettes, 'image');
    if (palette >= 0 && palette < sprite.atlases[image].paletteCount) {
      palettes[image] = palette;
    }
  }

  /// ASprite.y1 applies a palette to every image that supports that palette.
  void setPaletteAll(int palette) {
    for (var image = 0; image < palettes.length; image++) {
      setPalette(image, palette);
    }
  }
}

enum SpriteCommandKind { bitmap, vector, marker }

/// A module command in original painter order. No Flutter Canvas work occurs
/// here. Vector extras and ARGB colors remain exact for the renderer's u1 hook.
final class SpriteModuleCommand {
  const SpriteModuleCommand({
    required this.instance,
    required this.frame,
    required this.moduleIndex,
    required this.module,
    required this.x,
    required this.y,
    required this.flags,
    required this.palette,
  });

  final SpriteInstance instance;
  final int frame, moduleIndex;
  final SpriteModule module;
  final double x, y;
  final int flags, palette;

  SpriteCommandKind get kind => module.type == 0
      ? SpriteCommandKind.bitmap
      : module.type == 253
      ? SpriteCommandKind.marker
      : SpriteCommandKind.vector;
  int get j2meTransform => _j2meTransforms[flags & 7];
  int get width => flags & 4 == 0 ? module.width : module.height;
  int get height => flags & 4 == 0 ? module.height : module.width;
}

/// Instruction-order port of ASprite.k1/l1/m1/o1 for neutral GLLib effects.
///
/// Unsupported global effect states fail explicitly. No frame-255 sentinel,
/// placeholder sprite or missing-resource behavior is invented here.
final class FrameComposer {
  const FrameComposer({this.config = const SpriteCompositionConfig()});

  final SpriteCompositionConfig config;

  List<SpriteModuleCommand> composeFrame(
    SpriteInstance instance,
    int frame, {
    double x = 0,
    double y = 0,
    int flags = 0,
    int effectMask = 0,
  }) {
    if (effectMask != 0) {
      throw UnsupportedError(
        'GLLib effect mask 0x${effectMask.toRadixString(16)} needs its renderer hook',
      );
    }
    final commands = <SpriteModuleCommand>[];
    _compose(instance, frame, x, y, flags, commands, {}, {});
    return List.unmodifiable(commands);
  }

  List<SpriteModuleCommand> composeAnimationFrame(
    SpriteInstance instance,
    int animation,
    int animationFrame, {
    int x = 0,
    int y = 0,
    int flags = 0,
    int effectMask = 0,
  }) {
    final sprite = instance.sprite;
    RangeError.checkValidIndex(animation, sprite.animations, 'animation');
    final sequence = sprite.animations[animation];
    RangeError.checkValueInInterval(
      animationFrame,
      0,
      sequence.count - 1,
      'animationFrame',
    );
    final entry = sprite.animationFrames[sequence.start + animationFrame];
    var ox = entry.x;
    var oy = entry.y;
    var transform = entry.flags & 15;
    if (flags & 1 != 0) {
      transform = (transform & ~7) | _flipHorizontal[transform & 7];
      ox = -ox;
    }
    if (flags & 2 != 0) {
      transform = (transform & ~7) | _flipVertical[transform & 7];
      oy = -oy;
    }
    if (flags & 4 != 0) {
      transform = (transform & ~7) | _rotateClockwise[transform & 7];
      final previousX = ox;
      ox = -oy;
      oy = previousX;
    }
    return composeFrame(
      instance,
      entry.frame,
      x: (x + ox).toDouble(),
      y: (y + oy).toDouble(),
      flags: transform,
      effectMask: effectMask,
    );
  }

  void _compose(
    SpriteInstance instance,
    int frameIndex,
    double x,
    double y,
    int parentFlags,
    List<SpriteModuleCommand> commands,
    Set<(SpriteInstance, int)> active,
    Map<SpriteInstance, int> depths,
  ) {
    final key = (instance, frameIndex);
    if (!active.add(key)) {
      throw StateError(
        'Cyclic ASprite frame mapping/hyperframe at $frameIndex',
      );
    }
    try {
      if (config.frameMapping) {
        final mapping = instance.frameMappings[frameIndex];
        if (mapping != null) {
          mapping.target.setPaletteAll(mapping.palette);
          _compose(
            mapping.target,
            frameIndex + mapping.frameOffset,
            x,
            y,
            parentFlags,
            commands,
            active,
            depths,
          );
          return;
        }
      }
      final sprite = instance.sprite;
      RangeError.checkValidIndex(frameIndex, sprite.frames, 'frame');
      if (instance.paintMode < 0 || instance.paintMode > 2) {
        throw UnsupportedError('ASprite paint mode ${instance.paintMode}');
      }
      // These original branches are disabled in this APK; do not ignore a
      // caller that turns on marker-mask/callback behavior at runtime.
      if ((config.markerMasks && instance.loadFlags & 2 != 0) ||
          (config.markerCallbacks && instance.loadFlags & 32 != 0)) {
        throw UnsupportedError(
          'ASprite marker masks/callbacks need their hook',
        );
      }
      final depth = (depths[instance] ?? 0) + 1;
      depths[instance] = depth;
      try {
        final frame = sprite.frames[frameIndex];
        for (var n = 0; n < frame.count; n++) {
          final entry = sprite.frameModules[frame.start + n];
          var transform = entry.flags;
          final hyper = config.hyperFrames && transform & 16 != 0;
          var moduleIndex = entry.index;
          var offsetX = entry.x.toDouble();
          var offsetY = entry.y.toDouble();
          if (config.frameModulePalettes &&
              sprite.flags & 0x4000 != 0 &&
              instance.loadFlags & 16 == 0) {
            if (instance.palettes.isEmpty) {
              throw StateError(
                'Frame-module palette references missing image0',
              );
            }
            // l1 assigns this directly; unlike y1/z1 it does not clamp/ignore.
            instance.palettes[0] = entry.palette;
          }
          if (!hyper && config.moduleMapping) {
            final mapping = instance.moduleMappings[moduleIndex];
            if (mapping != null) {
              moduleIndex = mapping.module;
              offsetX += mapping.x;
              offsetY += mapping.y;
            }
          }
          SpriteModule? module;
          if (!hyper) {
            RangeError.checkValidIndex(moduleIndex, sprite.modules, 'module');
            module = sprite.modules[moduleIndex];
          }
          final sourceWidth = module?.width ?? 0;
          final sourceHeight = module?.height ?? 0;
          final extentX = transform & 4 != 0 ? sourceHeight : sourceWidth;
          final extentY = transform & 4 != 0 ? sourceWidth : sourceHeight;
          if (parentFlags & 1 != 0) {
            transform = (transform & ~7) | _flipHorizontal[transform & 7];
            offsetX = -offsetX - extentX;
          }
          if (parentFlags & 2 != 0) {
            transform = (transform & ~7) | _flipVertical[transform & 7];
            offsetY = -offsetY - extentY;
          }
          if (parentFlags & 4 != 0) {
            transform = (transform & ~7) | _rotateClockwise[transform & 7];
            final previousX = offsetX;
            offsetX = -offsetY - extentY;
            offsetY = previousX;
          }
          if (hyper) {
            if (instance.paintMode == 0 || instance.paintMode == 2) {
              _compose(
                instance,
                moduleIndex,
                x + offsetX,
                y + offsetY,
                transform & 15,
                commands,
                active,
                depths,
              );
            }
          } else if (instance.paintMode == 0 ||
              instance.paintMode == 1 ||
              depth > 1) {
            final image = module!.image;
            var palette = 0;
            if (module.isBitmap) {
              RangeError.checkValidIndex(image, sprite.atlases, 'image');
              palette = instance.palettes[image];
              if (palette < 0 ||
                  palette >= sprite.atlases[image].paletteCount) {
                throw RangeError('Invalid palette $palette for image $image');
              }
            }
            commands.add(
              SpriteModuleCommand(
                instance: instance,
                frame: frameIndex,
                moduleIndex: moduleIndex,
                module: module,
                x: x + offsetX,
                y: y + offsetY,
                flags: transform & 15,
                palette: palette,
              ),
            );
          }
        }
      } finally {
        depths[instance] = depth - 1;
      }
    } finally {
      active.remove(key);
    }
  }
}
