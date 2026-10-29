import 'dart:typed_data';
import 'dart:ui' as ui;

import '../compat/java_numbers.dart';
import '../dalvik/java_nio.dart';
import '../dalvik/numbers.dart';
import '../dalvik/runtime.dart';

const _gl = 'Landroid/opengl/GLES20;';
const _gllib = 'Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/GLLib;';
const _image = 'Lc/c/a/a/a/w/m0;';

/// Immutable snapshot of an actual GLES upload. Indexed planes retain indices
/// until the palette used by a draw is known.
class LegacyTexture {
  LegacyTexture(
    this.id,
    this.width,
    this.height,
    this.pixels, {
    this.indexed = false,
  });
  final int id, width, height;
  final Uint8List pixels;
  final bool indexed;
  Uint8List rgba([LegacyTexture? palette]) {
    if (!indexed) return pixels;
    if (palette == null ||
        palette.indexed ||
        palette.width * palette.height < 256) {
      throw MissingDalvikBridge(
        'indexed texture $id requires an uploaded 256-color palette',
      );
    }
    final output = Uint8List(width * height * 4);
    for (var n = 0; n < pixels.length; n++) {
      output.setRange(n * 4, n * 4 + 4, palette.pixels, pixels[n] * 4);
    }
    return output;
  }
}

class _TextureSlot {
  LegacyTexture? data;
  int minFilter = 9986, magFilter = 9729;
}

class _Images {
  const _Images(this.rgb, this.alpha);
  final ui.Image rgb, alpha;
  void dispose() {
    rgb.dispose();
    alpha.dispose();
  }
}

sealed class _Command {
  const _Command(this.target, this.clip);
  final LegacyTexture? target;
  final ui.Rect? clip;
}

class _Clear extends _Command {
  const _Clear(super.target, super.clip, this.color, this.writeAlpha);
  final ui.Color color;
  final bool writeAlpha;
}

class LegacyBatch extends _Command {
  LegacyBatch({
    required LegacyTexture? target,
    required ui.Rect? clip,
    required this.positions,
    required this.indices,
    required this.mode,
    required this.effect,
    required this.fxColor,
    required this.blend,
    required this.additive,
    required this.writeAlpha,
    this.colors,
    this.textureCoordinates,
    this.texture,
    this.palette,
    this.linear = false,
  }) : super(target, clip);
  final Float32List positions;
  final Uint16List indices;
  final Int32List? colors;
  final Float32List? textureCoordinates;
  final LegacyTexture? texture, palette;
  final int mode, effect;
  final List<double> fxColor;
  final bool blend, linear, additive, writeAlpha;
}

class _Surface {
  _Surface(this.width, this.height, [ui.Image? base])
    : recorder = ui.PictureRecorder() {
    canvas = ui.Canvas(recorder);
    if (base != null) canvas.drawImage(base, ui.Offset.zero, ui.Paint());
  }
  final int width, height;
  final ui.PictureRecorder recorder;
  late final ui.Canvas canvas;
  ui.Picture finish() => recorder.endRecording();
}

/// Native replacement for GLLib.T3 only. Original cGame, ASprite, Q3, effects
/// geometry, batching decisions and K3 bookkeeping continue to run as Dart DEX.
class LegacyRenderer {
  late final DalvikObject glContext;
  late final DalvikObject eglConfig;
  int _lastGlError = 0;
  final Map<int, _TextureSlot> _textures = {};
  final Map<int, int> _framebuffers = {};
  final Map<(LegacyTexture, LegacyTexture?), _Images> _images = {};
  final Map<LegacyTexture, _Images> _renderedTargets = {};
  final List<_Command> _commands = [];
  ui.FragmentProgram? _program;
  int _nextTexture = 1,
      _nextFramebuffer = 1,
      _activeTexture = 0,
      _framebuffer = 0;
  final Map<int, int> _bindings = {};
  ui.Rect _viewport = ui.Rect.zero, _scissor = ui.Rect.zero;
  bool _scissorEnabled = false, _blend = false;
  int _blendDestination = 771;
  List<bool> _colorMask = [true, true, true, true];
  ui.Color _clearColor = const ui.Color(0x00000000);
  int width = 800, height = 480;

  List<LegacyBatch> get batches =>
      List.unmodifiable(_commands.whereType<LegacyBatch>());
  LegacyTexture texture(int id) =>
      _textures[id]?.data ??
      (throw MissingDalvikBridge('unuploaded texture $id'));

  /// Diagnostic readback of the actual straight RGBA storage, including RGB
  /// under zero alpha. Does not substitute for executing pending commands.
  Future<Uint8List> readTexturePixels(int id, {int? paletteId}) async {
    final value = texture(id), rendered = _renderedTargets[texture(id)];
    if (rendered == null) {
      return Uint8List.fromList(
        value.rgba(paletteId == null ? null : texture(paletteId)),
      );
    }
    final rgb = (await rendered.rgb.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final alpha = (await rendered.alpha.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    for (var n = 0; n < rgb.length; n += 4) {
      rgb[n + 3] = alpha[n];
    }
    return rgb;
  }

  Future<void> load() async => _program = await ui.FragmentProgram.fromAsset(
    'shaders/legacy_texture.frag',
  );
  void beginFrame(int width, int height) {
    this.width = width;
    this.height = height;
    _commands.clear();
  }

  void dispose() {
    for (final images in _images.values) {
      images.dispose();
    }
    for (final image in _renderedTargets.values) {
      image.dispose();
    }
    _images.clear();
    _renderedTargets.clear();
    _textures.clear();
    _commands.clear();
  }

  LegacyTexture? get _target => _framebuffer == 0
      ? null
      : texture(
          _framebuffers[_framebuffer] ??
              (throw MissingDalvikBridge(
                'framebuffer $_framebuffer has no color attachment',
              )),
        );
  ui.Rect? _clip(LegacyTexture? target) {
    if (!_scissorEnabled) return null;
    return target == null
        ? ui.Rect.fromLTWH(
            _scissor.left,
            height - _scissor.bottom,
            _scissor.width,
            _scissor.height,
          )
        : _scissor;
  }

  void _checkMask(LegacyTexture? target) {
    if (!_colorMask[0] || !_colorMask[1] || !_colorMask[2]) {
      throw MissingDalvikBridge('partial RGB write mask $_colorMask');
    }
  }

  Future<ui.Image> _decodeOpaque(int width, int height, Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final result = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return result;
  }

  Future<_Images> _textureImages(
    LegacyTexture texture,
    LegacyTexture? palette,
  ) async {
    if (_images.containsKey((texture, palette))) {
      return _images[(texture, palette)]!;
    }
    final rgba = texture.rgba(palette);
    final rgb = Uint8List(rgba.length), alpha = Uint8List(rgba.length);
    for (var n = 0; n < rgba.length; n += 4) {
      rgb[n] = rgba[n];
      rgb[n + 1] = rgba[n + 1];
      rgb[n + 2] = rgba[n + 2];
      rgb[n + 3] = 255;
      alpha[n] = alpha[n + 1] = alpha[n + 2] = rgba[n + 3];
      alpha[n + 3] = 255;
    }
    final result = _Images(
      await _decodeOpaque(texture.width, texture.height, rgb),
      await _decodeOpaque(texture.width, texture.height, alpha),
    );
    _images[(texture, palette)] = result;
    return result;
  }

  /// Execute captured drawing in order, resolving real texture uploads outside
  /// the synchronous original-game invocation. Returned picture owns the frame.
  Future<ui.Picture> renderFrame() async {
    final program = _program;
    if (program == null) {
      throw MissingDalvikBridge(
        'load original-effect Flutter fragment program',
      );
    }
    // RGB and alpha are independent opaque planes. GLES blends straight RGB
    // and alpha with the same SRC_ALPHA factor; a premultiplied Flutter FBO
    // cannot represent that state, especially RGB stored underneath alpha zero.
    final surfaces = <(LegacyTexture?, bool), _Surface>{
      (null, false): _Surface(width, height),
    };
    _Surface surface(LegacyTexture? target, bool alpha) =>
        surfaces.putIfAbsent((target, alpha), () {
          final value = target!;
          final base = _renderedTargets[value] ?? _images[(value, null)];
          return _Surface(
            value.width,
            value.height,
            alpha ? base!.alpha : base!.rgb,
          );
        });
    _Images? finishTarget(LegacyTexture target) {
      final rgb = surfaces.remove((target, false));
      final alpha = surfaces.remove((target, true));
      if (rgb != null || alpha != null) {
        final previous = _renderedTargets[target] ?? _images[(target, null)]!;
        ui.Image finish(_Surface? pending, ui.Image unchanged) {
          if (pending == null) return unchanged.clone();
          final picture = pending.finish();
          final image = picture.toImageSync(target.width, target.height);
          picture.dispose();
          return image;
        }

        final result = _Images(
          finish(rgb, previous.rgb),
          finish(alpha, previous.alpha),
        );
        _renderedTargets.remove(target)?.dispose();
        _renderedTargets[target] = result;
      }
      return _renderedTargets[target];
    }

    for (final command in _commands) {
      _Images? images;
      if (command is LegacyBatch && command.texture != null) {
        if (identical(command.texture, command.target)) {
          throw MissingDalvikBridge(
            'simultaneous read/write feedback on same texture',
          );
        }
        images =
            finishTarget(command.texture!) ??
            await _textureImages(command.texture!, command.palette);
      }
      final target = command.target;
      if (target != null && !_renderedTargets.containsKey(target)) {
        await _textureImages(target, null);
      }
      for (final alphaPlane in target == null ? [false] : [false, true]) {
        final writeAlpha = command is _Clear
            ? command.writeAlpha
            : (command as LegacyBatch).writeAlpha;
        if (alphaPlane && !writeAlpha) continue;
        final canvas = surface(target, alphaPlane).canvas;
        canvas.save();
        if (command.clip != null) {
          canvas.clipRect(command.clip!, doAntiAlias: false);
        }
        if (command is _Clear) {
          final alpha = (command.color.a * 255).round();
          canvas.drawColor(
            alphaPlane
                ? ui.Color.fromARGB(255, alpha, alpha, alpha)
                : command.color.withAlpha(255),
            ui.BlendMode.src,
          );
        } else if (command is LegacyBatch) {
          ui.FragmentShader? shader;
          final paint = ui.Paint()
            ..isAntiAlias = false
            ..blendMode = !command.blend
                ? ui.BlendMode.src
                : command.additive
                ? ui.BlendMode.plus
                : ui.BlendMode.srcOver;
          if (images != null) {
            shader = program.fragmentShader()
              ..setFloat(0, command.texture!.width.toDouble())
              ..setFloat(1, command.texture!.height.toDouble())
              ..setFloat(2, command.effect.toDouble())
              ..setFloat(3, command.linear ? 1 : 0)
              ..setFloat(4, command.fxColor[0])
              ..setFloat(5, command.fxColor[1])
              ..setFloat(6, command.fxColor[2])
              ..setFloat(7, command.fxColor[3])
              ..setFloat(8, alphaPlane ? 1 : 0)
              ..setFloat(9, command.blend ? 1 : 0)
              ..setImageSampler(0, images.rgb)
              ..setImageSampler(1, images.alpha);
            paint.shader = shader;
          }
          Int32List? colors = command.colors;
          if (colors != null && (alphaPlane || !command.blend)) {
            if (alphaPlane &&
                colors.any(
                  (c) => (c >>> 24 & 255) != (colors![0] >>> 24 & 255),
                )) {
              throw MissingDalvikBridge('varying-alpha colored FBO vertices');
            }
            colors = Int32List.fromList(
              colors.map((c) {
                final alpha = c >>> 24 & 255;
                final rgb = alphaPlane ? alpha * 0x010101 : c & 0xffffff;
                return ((command.blend ? alpha : 255) << 24) | rgb;
              }).toList(),
            );
          }
          if (command.mode == 0) {
            for (var n = 0; n < command.indices.length; n += 2) {
              final a = command.indices[n], b = command.indices[n + 1];
              final colorA = colors![a], colorB = colors[b];
              if (colorA != colorB) {
                throw MissingDalvikBridge('GLLib gradient line rasterization');
              }
              paint
                ..color = ui.Color(colorA & 0xffffffff)
                ..strokeWidth = 1;
              canvas.drawLine(
                ui.Offset(
                  command.positions[a * 2],
                  command.positions[a * 2 + 1],
                ),
                ui.Offset(
                  command.positions[b * 2],
                  command.positions[b * 2 + 1],
                ),
                paint,
              );
            }
          } else {
            final vertices = ui.Vertices.raw(
              ui.VertexMode.triangles,
              command.positions,
              textureCoordinates: command.textureCoordinates,
              colors: colors,
              indices: command.indices,
            );
            canvas.drawVertices(
              vertices,
              images == null ? ui.BlendMode.dst : ui.BlendMode.srcOver,
              paint,
            );
            vertices.dispose();
          }
          shader?.dispose();
        }
        canvas.restore();
      }
    }
    for (final key in surfaces.keys.toList()) {
      if (key.$1 != null) finishTarget(key.$1!);
    }
    for (final key in _images.keys.toList()) {
      if (!identical(_textures[key.$1.id]?.data, key.$1) ||
          (key.$2 != null && !identical(_textures[key.$2!.id]?.data, key.$2))) {
        _images.remove(key)!.dispose();
      }
    }
    for (final key in _renderedTargets.keys.toList()) {
      if (!identical(_textures[key.id]?.data, key)) {
        _renderedTargets.remove(key)!.dispose();
      }
    }
    return surfaces[(null, false)]!.finish();
  }

  void capture(DalvikRuntime vm, List<Object?> args) {
    if (!vm.isNull(args[0])) {
      throw MissingDalvikBridge(
        'GLLib.T3 cached m1 batch (no original construction path observed)',
      );
    }
    Object? stat(String name, String type) =>
        vm.getStatic(_gllib, '$_gllib->$name:$type');
    int integer(String name) => stat(name, 'I') as int;
    void copyScratch(
      String arrayName,
      String arrayType,
      String bufferName,
      String bufferType,
    ) {
      final source = vm.asArray(stat(arrayName, arrayType)).values;
      final buffer = javaNioBuffer(vm, stat(bufferName, bufferType));
      buffer.position = 0;
      buffer.limit = buffer.capacity;
      buffer.mark = -1;
      if (source.length > buffer.capacity) {
        vm.throwJava('Ljava/nio/BufferOverflowException;');
      }
      for (var n = 0; n < source.length; n++) {
        buffer.writeRaw(n, source[n] as int);
      }
    }

    copyScratch('s2', '[F', 'r2', 'Ljava/nio/FloatBuffer;');
    copyScratch('u2', '[S', 't2', 'Ljava/nio/ShortBuffer;');
    final count = integer('k2');
    if (count <= 0) return;
    final mode = integer('c2'),
        effect = integer('d2'),
        stride = integer('v2'),
        components = integer('e2'),
        vertices = integer('i2');
    if (mode < 0 ||
        mode > 2 ||
        effect < 0 ||
        effect > 4 ||
        components < 2 ||
        components > 4) {
      throw MissingDalvikBridge(
        'T3 mode=$mode effect=$effect positionComponents=$components',
      );
    }
    final data = vm.asArray(stat('s2', '[F')).values;
    final indices = Uint16List.fromList(
      vm
          .asArray(stat('u2', '[S'))
          .values
          .take(count)
          .map((v) => (v as int) & 65535)
          .toList(),
    );
    final matrix = vm
        .asArray(vm.isNull(args[1]) ? stat('Q2', '[F') : args[1])
        .values
        .map((v) => JavaNumbers.floatFromBits(v as int))
        .toList();
    final target = _target;
    _checkMask(target);
    final targetHeight = target?.height ?? height;
    final positions = Float32List(vertices * 2),
        uv = mode == 2 ? Float32List(vertices * 2) : null;
    final colors = mode == 2 ? null : Int32List(vertices);
    final fx = [
      for (final name in ['M2', 'N2', 'O2', 'P2']) integer(name) / 255.0,
    ];
    LegacyTexture? texture, palette;
    if (mode == 2) {
      final image = vm.object(stat('l2', _image));
      final ids = vm.asArray(vm.getField(image, '$_image->g:[I'));
      texture = this.texture(ids.values[0] as int);
      _activeTexture = 0;
      _bindings[0] = texture.id;
      final paletteIds = vm.getField(image, '$_image->a:[I');
      if (!vm.isNull(paletteIds)) {
        palette = this.texture(vm.asArray(paletteIds).values[0] as int);
        _activeTexture = 1;
        _bindings[1] = palette.id;
      }
    }
    javaNioBuffer(vm, stat('r2', 'Ljava/nio/FloatBuffer;')).position =
        components;
    double value(int n) => JavaNumbers.floatFromBits(data[n] as int);
    for (var n = 0; n < vertices; n++) {
      final offset = n * stride;
      final x = value(offset),
          y = value(offset + 1),
          z = components > 2 ? value(offset + 2) : 0.0,
          w = components > 3 ? value(offset + 3) : 1.0;
      final cx = x * matrix[0] + y * matrix[1] + z * matrix[2] + w * matrix[3];
      final cy = x * matrix[4] + y * matrix[5] + z * matrix[6] + w * matrix[7];
      final cw =
          x * matrix[12] + y * matrix[13] + z * matrix[14] + w * matrix[15];
      if (cw != 1) {
        throw MissingDalvikBridge('perspective-correct T3 interpolation w=$cw');
      }
      positions[n * 2] = _viewport.left + (cx + 1) * _viewport.width / 2;
      final py = _viewport.top + (cy + 1) * _viewport.height / 2;
      positions[n * 2 + 1] = target == null ? targetHeight - py : py;
      if (uv != null) {
        uv[n * 2] = value(offset + components) * texture!.width;
        uv[n * 2 + 1] = value(offset + components + 1) * texture.height;
      } else {
        var r = value(offset + components),
            g = value(offset + components + 1),
            b = value(offset + components + 2),
            a = value(offset + components + 3);
        if (effect == 1) {
          r = fx[0];
          g = fx[1];
          b = fx[2];
        } else if (effect == 2) {
          r = g = b = r * .2125 + g * .7154 + b * .0721;
        } else if (effect == 4) {
          r += (fx[0] - r) * fx[3];
          g += (fx[1] - g) * fx[3];
          b += (fx[2] - b) * fx[3];
        }
        if (effect != 4) a *= fx[3];
        int channel(double n) => (n.clamp(0, 1) * 255).round();
        colors![n] =
            (channel(a) << 24) |
            (channel(r) << 16) |
            (channel(g) << 8) |
            channel(b);
      }
    }
    _commands.add(
      LegacyBatch(
        target: target,
        clip:
            (target == null
                    ? ui.Rect.fromLTWH(
                        _viewport.left,
                        height - _viewport.bottom,
                        _viewport.width,
                        _viewport.height,
                      )
                    : _viewport)
                .intersect(
                  _clip(target) ??
                      (target == null
                          ? ui.Rect.fromLTWH(
                              0,
                              0,
                              width.toDouble(),
                              height.toDouble(),
                            )
                          : ui.Rect.fromLTWH(
                              0,
                              0,
                              target.width.toDouble(),
                              target.height.toDouble(),
                            )),
                ),
        positions: positions,
        indices: indices,
        mode: mode,
        effect: effect,
        fxColor: fx,
        blend: _blend,
        additive: _blendDestination == 1,
        writeAlpha: _colorMask[3],
        colors: colors,
        textureCoordinates: uv,
        texture: texture,
        palette: palette,
        linear:
            mode == 2 &&
            (texture!.indexed
                ? integer('w2') == 4
                : _textures[texture.id]!.magFilter == 9729),
      ),
    );
  }
}

void registerLegacyRenderer(
  DalvikRuntime vm, {
  required LegacyRenderer renderer,
}) {
  vm.registerExternalClass(_gl);
  const gl10 = 'Ljavax/microedition/khronos/opengles/GL10;';
  const contextType = 'Lport/FlutterGraphicsContext;';
  const configType = 'Ljavax/microedition/khronos/egl/EGLConfig;';
  vm.registerExternalClass(gl10);
  vm.registerExternalClass(contextType, interfaces: [gl10]);
  vm.registerExternalClass(configType);
  renderer.glContext = DalvikObject(contextType, nativeValue: renderer);
  renderer.eglConfig = DalvikObject(configType, nativeValue: renderer);
  Object? getString(DalvikRuntime v, int name) {
    final value = switch (name) {
      7936 => 'Flutter',
      7937 => 'Flutter runtime-effect renderer',
      7938 => 'Green Farm GLES compatibility bridge 1',
      7939 => '',
      _ => null,
    };
    if (value == null) {
      if (renderer._lastGlError == 0) renderer._lastGlError = 1280;
      return null;
    }
    return v.newString(value);
  }

  vm.registerNative(
    '$gl10->glGetString(I)Ljava/lang/String;',
    (v, a) => getString(v, a[1] as int),
  );
  vm.registerNative(
    '$_gl->glGetString(I)Ljava/lang/String;',
    (v, a) => getString(v, a[0] as int),
  );
  vm.registerNative('$_gl->glGetError()I', (v, a) {
    final error = renderer._lastGlError;
    renderer._lastGlError = 0;
    return error;
  });
  void native(String name, DalvikBody body) =>
      vm.registerNative('$_gl->$name', body);
  int i(Object? v) => JBits.int32(v);
  void require(bool condition, String operation) {
    if (!condition) throw MissingDalvikBridge(operation);
  }

  vm.registerNative('$_gllib->T3(Lc/c/a/a/a/w/m1;[F)V', (v, a) {
    renderer.capture(v, a);
    return null;
  });
  vm.registerNative('$_gllib->m4()V', (v, a) {
    require(
      renderer._program != null,
      'load fixed GLLib shader program before m4',
    );
    final table = v.array('[[I', 5);
    for (var effect = 0; effect < 5; effect++) {
      final row = v.array('[I', 4);
      for (var kind = 0; kind < 4; kind++) {
        row.values[kind] = (effect == 3 ? 0 : effect) * 4 + kind + 1;
      }
      table.values[effect] = row;
    }
    v.putStatic(_gllib, '$_gllib->K2:[[I', table);
    return null;
  });
  native('glActiveTexture(I)V', (v, a) {
    final unit = i(a[0]) - 33984;
    require(unit == 0 || unit == 1, 'texture unit $unit');
    renderer._activeTexture = unit;
    return null;
  });
  native('glGenTextures(I[II)V', (v, a) {
    for (var n = 0; n < i(a[0]); n++) {
      final id = renderer._nextTexture++;
      renderer._textures[id] = _TextureSlot();
      v.arrayPut(a[1], i(a[2]) + n, id);
    }
    return null;
  });
  native('glDeleteTextures(I[II)V', (v, a) {
    for (var n = 0; n < i(a[0]); n++) {
      renderer._textures.remove(v.arrayGet(a[1], i(a[2]) + n));
    }
    return null;
  });
  native('glBindTexture(II)V', (v, a) {
    require(i(a[0]) == 3553, 'texture target ${a[0]}');
    renderer._bindings[renderer._activeTexture] = i(a[1]);
    return null;
  });
  for (final floating in [false, true]) {
    native('glTexParameter${floating ? 'f(IIF)' : 'i(III)'}V', (v, a) {
      require(i(a[0]) == 3553, 'texture target ${a[0]}');
      final id = renderer._bindings[renderer._activeTexture],
          slot = renderer._textures[id];
      if (slot == null) throw MissingDalvikBridge('bound texture $id');
      final name = i(a[1]),
          value = floating ? JBits.float(a, 2).toInt() : i(a[2]);
      if (name == 10241 || name == 10240) {
        require(value == 9728 || value == 9729, 'texture filter $value');
        if (name == 10241) {
          slot.minFilter = value;
        } else {
          slot.magFilter = value;
        }
      } else {
        require(
          (name == 10242 || name == 10243) && value == 33071,
          'texture wrap $name=$value',
        );
      }
      return null;
    });
  }
  native('glTexImage2D(IIIIIIIILjava/nio/Buffer;)V', (v, a) {
    final width = i(a[3]), height = i(a[4]), format = i(a[6]), type = i(a[7]);
    require(
      i(a[0]) == 3553 &&
          i(a[1]) == 0 &&
          i(a[5]) == 0 &&
          width > 0 &&
          height > 0,
      'texture upload dimensions/level/target',
    );
    require(
      (format == 6408 && (type == 5121 || type == 32819 || type == 32820)) ||
          (format == 6409 && type == 5121),
      'texture format $format/$type',
    );
    final id = renderer._bindings[renderer._activeTexture],
        slot = renderer._textures[id];
    if (id == null || slot == null) {
      throw MissingDalvikBridge('upload without generated texture');
    }
    final indexed = format == 6409, count = width * height;
    final pixels = Uint8List(count * (indexed ? 1 : 4));
    if (!v.isNull(a[8])) {
      final bytes = javaNioBuffer(v, a[8]).copyBytes();
      final bytesPerPixel = indexed
          ? 1
          : type == 5121
          ? 4
          : 2;
      final rowBytes = width * bytesPerPixel, rowStride = (rowBytes + 3) & ~3;
      final requiredBytes = (height - 1) * rowStride + rowBytes;
      if (bytes.length < requiredBytes) {
        v.throwJava(
          'Ljava/lang/IllegalArgumentException;',
          'Texture Buffer too small',
        );
      }
      if (type == 5121) {
        for (var y = 0; y < height; y++) {
          pixels.setRange(
            y * rowBytes,
            (y + 1) * rowBytes,
            bytes,
            y * rowStride,
          );
        }
      } else {
        for (var n = 0; n < count; n++) {
          final byte = (n ~/ width) * rowStride + (n % width) * 2;
          final word = bytes[byte] | (bytes[byte + 1] << 8), p = n * 4;
          if (type == 32819) {
            pixels[p] = ((word >> 12) & 15) * 17;
            pixels[p + 1] = ((word >> 8) & 15) * 17;
            pixels[p + 2] = ((word >> 4) & 15) * 17;
            pixels[p + 3] = (word & 15) * 17;
          } else {
            int five(int n) => (n << 3) | (n >> 2);
            pixels[p] = five((word >> 11) & 31);
            pixels[p + 1] = five((word >> 6) & 31);
            pixels[p + 2] = five((word >> 1) & 31);
            pixels[p + 3] = (word & 1) * 255;
          }
        }
      }
    }
    slot.data = LegacyTexture(id, width, height, pixels, indexed: indexed);
    return null;
  });
  native('glGenFramebuffers(I[II)V', (v, a) {
    for (var n = 0; n < i(a[0]); n++) {
      v.arrayPut(a[1], i(a[2]) + n, renderer._nextFramebuffer++);
    }
    return null;
  });
  native('glBindFramebuffer(II)V', (v, a) {
    require(i(a[0]) == 36160, 'framebuffer target ${a[0]}');
    renderer._framebuffer = i(a[1]);
    return null;
  });
  native('glFramebufferTexture2D(IIIII)V', (v, a) {
    require(
      i(a[0]) == 36160 && i(a[1]) == 36064 && i(a[2]) == 3553 && i(a[4]) == 0,
      'framebuffer attachment format',
    );
    renderer._framebuffers[renderer._framebuffer] = i(a[3]);
    return null;
  });
  native('glViewport(IIII)V', (v, a) {
    renderer._viewport = ui.Rect.fromLTWH(
      i(a[0]).toDouble(),
      i(a[1]).toDouble(),
      i(a[2]).toDouble(),
      i(a[3]).toDouble(),
    );
    return null;
  });
  native('glScissor(IIII)V', (v, a) {
    renderer._scissor = ui.Rect.fromLTWH(
      i(a[0]).toDouble(),
      i(a[1]).toDouble(),
      i(a[2]).toDouble(),
      i(a[3]).toDouble(),
    );
    return null;
  });
  native('glBlendFunc(II)V', (v, a) {
    require(
      i(a[0]) == 770 && (i(a[1]) == 771 || i(a[1]) == 1),
      'blend factors ${a[0]}/${a[1]}',
    );
    renderer._blendDestination = i(a[1]);
    return null;
  });
  native('glColorMask(ZZZZ)V', (v, a) {
    renderer._colorMask = a.map((n) => i(n) != 0).toList();
    return null;
  });
  for (final enable in [false, true]) {
    native('gl${enable ? 'Enable' : 'Disable'}(I)V', (v, a) {
      switch (i(a[0])) {
        case 3042:
          renderer._blend = enable;
        case 3089:
          renderer._scissorEnabled = enable;
        default:
          throw MissingDalvikBridge('GL capability ${a[0]}=$enable');
      }
      return null;
    });
  }
  native('glClearColor(FFFF)V', (v, a) {
    renderer._clearColor = ui.Color.fromARGB(
      (JBits.float(a, 3).clamp(0, 1) * 255).round(),
      (JBits.float(a, 0).clamp(0, 1) * 255).round(),
      (JBits.float(a, 1).clamp(0, 1) * 255).round(),
      (JBits.float(a, 2).clamp(0, 1) * 255).round(),
    );
    return null;
  });
  native('glClear(I)V', (v, a) {
    require(i(a[0]) == 16384, 'clear mask ${a[0]}');
    final target = renderer._target;
    renderer._checkMask(target);
    renderer._commands.add(
      _Clear(
        target,
        renderer._clip(target),
        renderer._clearColor,
        renderer._colorMask[3],
      ),
    );
    return null;
  });
}
