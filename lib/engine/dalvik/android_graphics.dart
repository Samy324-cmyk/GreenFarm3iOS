import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../compat/java_numbers.dart';
import 'cooperative.dart';
import 'numbers.dart';
import 'runtime.dart';

const _typeface = 'Landroid/graphics/Typeface;';
const _paint = 'Landroid/graphics/Paint;';
const _bitmap = 'Landroid/graphics/Bitmap;';
const _canvas = 'Landroid/graphics/Canvas;';
const _config = 'Landroid/graphics/Bitmap\$Config;';

class AndroidTypeface {
  const AndroidTypeface(this.family, this.style);
  final String family;
  final int style;
  String get fontKey => family == 'monospace'
      ? 'DroidSansMono'
      : 'Roboto${const ['', '-Bold', '-Italic', '-BoldItalic'][style]}';
}

class _FontMetric {
  const _FontMetric(this.units, this.ascent, this.descent);
  final int units, ascent, descent;
  factory _FontMetric.parse(ByteData data) {
    var head = -1, hhea = -1;
    final count = data.getUint16(4);
    for (var n = 0; n < count; n++) {
      final offset = 12 + n * 16;
      final tag = data.getUint32(offset), table = data.getUint32(offset + 8);
      if (tag == 0x68656164) head = table;
      if (tag == 0x68686561) hhea = table;
    }
    if (head < 0 || hhea < 0) {
      throw const FormatException('TrueType head/hhea tables missing');
    }
    return _FontMetric(
      data.getUint16(head + 18),
      data.getInt16(hhea + 4),
      data.getInt16(hhea + 6),
    );
  }
}

/// Real Flutter/Skia fonts and predecoded bitmaps supplied during bootstrap.
/// The AOSP fonts are pinned to Android5.1.1_r38, including their original NOTICE.
class AndroidGraphicsEnvironment {
  final Map<String, _FontMetric> _fonts = {};
  AndroidBitmap? Function(Uint8List encoded)? decodeImageSync;
  bool get fontsLoaded => _fonts.length == 5;

  Future<void> loadFonts({
    Future<ByteData> Function(String path)? loader,
  }) async {
    final load = loader ?? rootBundle.load;
    for (final key in [
      'Roboto',
      'Roboto-Bold',
      'Roboto-Italic',
      'Roboto-BoldItalic',
      'DroidSansMono',
    ]) {
      final file = key == 'Roboto' ? 'Roboto-Regular' : key;
      final bytes = await load('assets/fonts/$file.ttf');
      final font = FontLoader('Android-$key')..addFont(Future.value(bytes));
      await font.load();
      _fonts[key] = _FontMetric.parse(bytes);
    }
  }

  _FontMetric _metrics(AndroidTypeface typeface) =>
      _fonts[typeface.fontKey] ??
      (throw MissingDalvikBridge(
        'load AOSP font ${typeface.fontKey} before measuring text',
      ));

  ui.Paragraph paragraph(String text, AndroidPaint paint) {
    final typeface = paint.typeface ?? const AndroidTypeface('sans-serif', 0);
    _metrics(
      typeface,
    ); // Never silently use Flutter's test/default replacement font.
    if (paint.fakeBold) {
      throw MissingDalvikBridge(
        'Android Paint synthetic fake-bold glyph rasterization',
      );
    }
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: 'Android-${typeface.fontKey}',
              fontSize: paint.textSize,
              textDirection: ui.TextDirection.ltr,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              fontFamily: 'Android-${typeface.fontKey}',
              fontSize: paint.textSize,
              foreground: paint.toUiPaint(),
              fontWeight: typeface.style & 1 != 0
                  ? ui.FontWeight.bold
                  : ui.FontWeight.normal,
              fontStyle: typeface.style & 2 != 0
                  ? ui.FontStyle.italic
                  : ui.FontStyle.normal,
            ),
          )
          ..addText(text);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: 100000000));
  }
}

class AndroidPaint {
  AndroidTypeface? typeface;
  DalvikObject? typefaceObject;
  double textSize = 16, textSkewX = 0, strokeWidth = 0;
  int color = -0x1000000, style = 0, cap = 0, align = 0;
  bool antiAlias = false,
      dither = false,
      filterBitmap = false,
      fakeBold = false;
  ui.Paint toUiPaint() {
    if (style == 2) throw MissingDalvikBridge('Paint.Style.FILL_AND_STROKE');
    return ui.Paint()
      ..color = ui.Color(color & 0xffffffff)
      ..isAntiAlias = antiAlias
      ..strokeWidth = strokeWidth
      ..style = style == 1 ? ui.PaintingStyle.stroke : ui.PaintingStyle.fill
      ..strokeCap = ui.StrokeCap.values[cap]
      ..filterQuality = filterBitmap
          ? ui.FilterQuality.low
          : ui.FilterQuality.none;
  }
}

/// Keeps original unpremultiplied RGBA bytes for synchronous Bitmap.getPixels.
class AndroidBitmap {
  AndroidBitmap(
    this.width,
    this.height,
    this.rgba, {
    this.mutable = false,
    this.config = 'ARGB_8888',
  }) {
    if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
      throw ArgumentError('Bitmap dimensions/bytes disagree');
    }
  }
  final int width, height;
  final Uint8List rgba;
  final bool mutable;
  final String config;
  bool recycled = false, pixelsDirty = false;
  ui.Image? image;
  AndroidCanvasSurface? drawing;
  int paintVersion = 0;

  Future<Uint8List> synchronizePixels() async {
    if (!pixelsDirty) return rgba;
    if (config != 'ARGB_8888') {
      throw MissingDalvikBridge('Canvas readback into Bitmap.$config');
    }
    final version = paintVersion;
    final rendered = drawing?.finish() ?? image;
    if (rendered == null) throw StateError('Dirty bitmap has no Canvas image');
    final data = await rendered.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) throw StateError('Bitmap readback failed');
    final pixels = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (paintVersion == version) {
      rgba.setAll(0, pixels);
      pixelsDirty = false;
    }
    return pixels;
  }

  Future<void> prepareImage() async {
    if (pixelsDirty) await synchronizePixels();
    if (image != null) return;
    final premultiplied = Uint8List.fromList(rgba);
    for (var n = 0; n < rgba.length; n += 4) {
      for (var channel = 0; channel < 3; channel++) {
        premultiplied[n + channel] =
            (rgba[n + channel] * rgba[n + 3] + 127) ~/ 255;
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(premultiplied);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    image = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

/// Canvas state recorded into a real Flutter Picture; no screen placeholder.
class AndroidCanvasSurface {
  AndroidCanvasSurface(this.bitmap)
    : recorder = ui.PictureRecorder(),
      width = bitmap.width,
      height = bitmap.height {
    canvas = ui.Canvas(recorder);
    final previous = bitmap.image;
    if (previous != null) {
      canvas.drawImage(previous, ui.Offset.zero, ui.Paint());
    } else if (bitmap.config == 'RGB_565') {
      canvas.drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
    } else if (bitmap.rgba.any((channel) => channel != 0)) {
      throw MissingDalvikBridge(
        'prepareImage before drawing over nonempty Bitmap pixels',
      );
    }
  }
  final AndroidBitmap bitmap;
  final int width, height;
  ui.PictureRecorder recorder;
  late ui.Canvas canvas;
  ui.Image finish() {
    final saveCount = canvas.getSaveCount();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    bitmap.image?.dispose();
    bitmap.image = image;
    recorder = ui.PictureRecorder();
    canvas = ui.Canvas(recorder)..drawImage(image, ui.Offset.zero, ui.Paint());
    for (var n = 1; n < saveCount; n++) {
      canvas.save();
    }
    return image;
  }
}

DalvikObject javaAndroidBitmap(AndroidBitmap bitmap) =>
    DalvikObject(_bitmap, nativeValue: bitmap);

void registerAndroidGraphics(
  DalvikRuntime vm, {
  required AndroidGraphicsEnvironment environment,
}) {
  for (final name in [
    'Typeface',
    'Paint',
    'Point',
    'RectF',
    'Path',
    'Bitmap',
    'BitmapFactory',
    'Canvas',
    'Color',
  ]) {
    vm.registerExternalClass('Landroid/graphics/$name;');
  }
  for (final entry in {
    'Landroid/graphics/Point;': ['x:I', 'y:I'],
    'Landroid/graphics/RectF;': ['left:F', 'top:F', 'right:F', 'bottom:F'],
  }.entries) {
    for (final field in entry.value) {
      vm.classes[entry.key]!.instanceFields['${entry.key}->$field'] = field
          .split(':')
          .last;
    }
  }
  void enumeration(String name, List<String> values) {
    vm.registerExternalClass(name);
    for (var n = 0; n < values.length; n++) {
      vm.classes[name]!.staticFields['$name->${values[n]}:$name'] =
          DalvikObject(name, nativeValue: n);
    }
  }

  enumeration('Landroid/graphics/Paint\$Align;', ['LEFT', 'CENTER', 'RIGHT']);
  enumeration('Landroid/graphics/Paint\$Cap;', ['BUTT', 'ROUND', 'SQUARE']);
  enumeration('Landroid/graphics/Paint\$Style;', [
    'FILL',
    'STROKE',
    'FILL_AND_STROKE',
  ]);
  enumeration(_config, ['ALPHA_8', 'RGB_565', 'ARGB_4444', 'ARGB_8888']);
  void put(String owner, String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);
  put('Landroid/graphics/Color;', 'parseColor(Ljava/lang/String;)I', (v, a) {
    final text = v.string(a[0]);
    if (text.isEmpty) {
      v.throwJava(
        'Ljava/lang/StringIndexOutOfBoundsException;',
        'length=0; index=0',
      );
    }
    if (text.startsWith('#')) {
      final hex = text.substring(1);
      final value = RegExp(r'^[+-]?[0-9a-fA-F]+$').hasMatch(hex)
          ? int.tryParse(hex, radix: 16)
          : null;
      if (value == null) v.throwJava('Ljava/lang/NumberFormatException;', hex);
      if (text.length == 7) return (value | 0xff000000).toSigned(32);
      if (text.length == 9) return value.toSigned(32);
    } else {
      // Exact AOSP android-5.1.1_r38 Color.sColorNameMap; "transparent" is
      // intentionally absent because the original Android API rejects it.
      const names = <String, int>{
        'black': 0xff000000,
        'darkgray': 0xff444444,
        'gray': 0xff888888,
        'lightgray': 0xffcccccc,
        'white': 0xffffffff,
        'red': 0xffff0000,
        'green': 0xff00ff00,
        'blue': 0xff0000ff,
        'yellow': 0xffffff00,
        'cyan': 0xff00ffff,
        'magenta': 0xffff00ff,
        'aqua': 0xff00ffff,
        'fuchsia': 0xffff00ff,
        'darkgrey': 0xff444444,
        'grey': 0xff888888,
        'lightgrey': 0xffcccccc,
        'lime': 0xff00ff00,
        'maroon': 0xff800000,
        'navy': 0xff000080,
        'olive': 0xff808000,
        'purple': 0xff800080,
        'silver': 0xffc0c0c0,
        'teal': 0xff008080,
      };
      final value = names[text.toLowerCase()];
      if (value != null) return value.toSigned(32);
    }
    v.throwJava('Ljava/lang/IllegalArgumentException;', 'Unknown color');
  });
  AndroidPaint paint(Object? value) =>
      vm.object(value).nativeValue as AndroidPaint;
  AndroidBitmap bitmap(Object? value) {
    final b = vm.object(value).nativeValue as AndroidBitmap;
    if (b.recycled) {
      vm.throwJava(
        'Ljava/lang/IllegalStateException;',
        'Cannot use a recycled bitmap',
      );
    }
    return b;
  }

  int intValue(Object? value) => JBits.int32(value);
  int raw(double value) => JavaNumbers.floatBits(value);
  void checkRange(int start, int length, int total) {
    if (start < 0 || length < 0 || start > total - length) {
      vm.throwJava('Ljava/lang/IndexOutOfBoundsException;');
    }
  }

  put(_typeface, 'create(Ljava/lang/String;I)Landroid/graphics/Typeface;', (
    v,
    a,
  ) {
    final family = v.isNull(a[0]) ? 'sans-serif' : v.string(a[0]);
    if (!['sans-serif', 'Roboto', 'monospace'].contains(family)) {
      throw MissingDalvikBridge('Android font family $family');
    }
    var style = intValue(a[1]);
    if (style < 0 || style > 3) style = 0;
    return DalvikObject(_typeface, nativeValue: AndroidTypeface(family, style));
  });
  put(
    _typeface,
    'getStyle()I',
    (v, a) => (v.object(a[0]).nativeValue as AndroidTypeface).style,
  );
  put(_paint, '<init>()V', (v, a) {
    v.object(a[0]).nativeValue = AndroidPaint();
    return null;
  });
  put(
    _paint,
    'setTypeface(Landroid/graphics/Typeface;)Landroid/graphics/Typeface;',
    (v, a) {
      final p = paint(a[0]);
      p.typefaceObject = v.isNull(a[1]) ? null : v.object(a[1]);
      p.typeface = p.typefaceObject?.nativeValue as AndroidTypeface?;
      return a[1];
    },
  );
  for (final field in ['AntiAlias', 'Dither', 'FilterBitmap', 'FakeBoldText']) {
    put(_paint, 'set$field(Z)V', (v, a) {
      final p = paint(a[0]), enabled = intValue(a[1]) != 0;
      switch (field) {
        case 'AntiAlias':
          p.antiAlias = enabled;
        case 'Dither':
          p.dither = enabled;
        case 'FilterBitmap':
          p.filterBitmap = enabled;
        case 'FakeBoldText':
          p.fakeBold = enabled;
      }
      return null;
    });
  }
  for (final field in ['TextSize', 'TextSkewX', 'StrokeWidth']) {
    put(_paint, 'set$field(F)V', (v, a) {
      final p = paint(a[0]), value = JBits.float(a, 1);
      switch (field) {
        case 'TextSize':
          if (value >= 0) p.textSize = value;
        case 'TextSkewX':
          p.textSkewX = value;
        case 'StrokeWidth':
          if (value >= 0) p.strokeWidth = value;
      }
      return null;
    });
  }
  put(_paint, 'setColor(I)V', (v, a) {
    paint(a[0]).color = intValue(a[1]);
    return null;
  });
  for (final entry in {
    'TextAlign': 'Align',
    'StrokeCap': 'Cap',
    'Style': 'Style',
  }.entries) {
    put(_paint, 'set${entry.key}(Landroid/graphics/Paint\$${entry.value};)V', (
      v,
      a,
    ) {
      final p = paint(a[0]), value = v.object(a[1]).nativeValue as int;
      switch (entry.key) {
        case 'TextAlign':
          p.align = value;
        case 'StrokeCap':
          p.cap = value;
        case 'Style':
          p.style = value;
      }
      return null;
    });
  }
  for (final name in ['ascent', 'descent']) {
    put(_paint, '$name()F', (v, a) {
      final p = paint(a[0]),
          metric = environment._metrics(
            paint(a[0]).typeface ?? const AndroidTypeface('sans-serif', 0),
          );
      return raw(
        -(name == 'ascent' ? metric.ascent : metric.descent) *
            p.textSize /
            metric.units,
      );
    });
  }
  for (final chars in [true, false]) {
    put(_paint, 'measureText(${chars ? '[C' : 'Ljava/lang/String;'}II)F', (
      v,
      a,
    ) {
      final start = intValue(a[2]), third = intValue(a[3]);
      final String text;
      if (chars) {
        final array = v.asArray(a[1]);
        checkRange(start, third, array.values.length);
        text = String.fromCharCodes(
          array.values.skip(start).take(third).cast<int>(),
        );
      } else {
        final string = v.string(a[1]);
        checkRange(start, third - start, string.length);
        text = string.substring(start, third);
      }
      if (text.isEmpty || paint(a[0]).textSize == 0) return raw(0);
      final paragraph = environment.paragraph(text, paint(a[0]));
      final width = paragraph.computeLineMetrics().fold<double>(
        0,
        (sum, line) => sum + line.width,
      );
      paragraph.dispose();
      return raw(width);
    });
  }
  for (final type in ['Point', 'RectF']) {
    put('Landroid/graphics/$type;', '<init>()V', (v, a) => null);
  }
  put('Landroid/graphics/Path;', '<init>()V', (v, a) {
    v.object(a[0]).nativeValue = ui.Path();
    return null;
  });
  put(
    _bitmap,
    'getWidth()I',
    (v, a) => (v.object(a[0]).nativeValue as AndroidBitmap).width,
  );
  put(
    _bitmap,
    'getHeight()I',
    (v, a) => (v.object(a[0]).nativeValue as AndroidBitmap).height,
  );
  put(
    _bitmap,
    'isRecycled()Z',
    (v, a) => (v.object(a[0]).nativeValue as AndroidBitmap).recycled ? 1 : 0,
  );
  put(
    _bitmap,
    'isMutable()Z',
    (v, a) => (v.object(a[0]).nativeValue as AndroidBitmap).mutable ? 1 : 0,
  );
  put(_bitmap, 'recycle()V', (v, a) {
    final b = v.object(a[0]).nativeValue as AndroidBitmap;
    b.recycled = true;
    b.image?.dispose();
    b.image = null;
    return null;
  });
  put(
    _bitmap,
    'createBitmap(IILandroid/graphics/Bitmap\$Config;)Landroid/graphics/Bitmap;',
    (v, a) {
      final width = intValue(a[0]),
          height = intValue(a[1]),
          config = v.object(a[2]).nativeValue as int;
      if (width <= 0 || height <= 0) {
        v.throwJava(
          'Ljava/lang/IllegalArgumentException;',
          'width and height must be > 0',
        );
      }
      if (config != 1 && config != 3) {
        throw MissingDalvikBridge('Bitmap.Config $config allocation');
      }
      final rgba = Uint8List(width * height * 4);
      if (config == 1) {
        for (var n = 3; n < rgba.length; n += 4) {
          rgba[n] = 255;
        }
      }
      return javaAndroidBitmap(
        AndroidBitmap(
          width,
          height,
          rgba,
          mutable: true,
          config: config == 1 ? 'RGB_565' : 'ARGB_8888',
        ),
      );
    },
  );
  put(_bitmap, 'getPixels([IIIIIII)V', (v, a) {
    final b = bitmap(a[0]), target = v.asArray(a[1]);
    final offset = intValue(a[2]),
        stride = intValue(a[3]),
        x = intValue(a[4]),
        y = intValue(a[5]),
        width = intValue(a[6]),
        height = intValue(a[7]);
    if (width < 0 ||
        height < 0 ||
        x < 0 ||
        y < 0 ||
        x > b.width - width ||
        y > b.height - height ||
        stride.abs() < width) {
      v.throwJava('Ljava/lang/IllegalArgumentException;');
    }
    if (width == 0 || height == 0) return null;
    final last = offset + (height - 1) * stride;
    checkRange(
      math.min(offset, last),
      (last - offset).abs() + width,
      target.values.length,
    );
    Object? copy(Uint8List pixels) {
      for (var row = 0; row < height; row++) {
        for (var col = 0; col < width; col++) {
          final p = ((y + row) * b.width + x + col) * 4;
          target.values[offset + row * stride + col] =
              ((pixels[p + 3] << 24) |
                      (pixels[p] << 16) |
                      (pixels[p + 1] << 8) |
                      pixels[p + 2])
                  .toSigned(32);
        }
      }
      return null;
    }

    if (b.pixelsDirty) v.suspendUntil(b.synchronizePixels().then(copy));
    return copy(b.rgba);
  });
  put(
    _bitmap,
    'createScaledBitmap(Landroid/graphics/Bitmap;IIZ)Landroid/graphics/Bitmap;',
    (v, a) {
      final source = bitmap(a[0]),
          width = intValue(a[1]),
          height = intValue(a[2]),
          filter = intValue(a[3]) != 0;
      if (width <= 0 || height <= 0) {
        v.throwJava(
          'Ljava/lang/IllegalArgumentException;',
          'width and height must be > 0',
        );
      }
      if (width == source.width && height == source.height) return a[0];
      Future<Object?> scale() async {
        if (source.pixelsDirty) await source.synchronizePixels();
        await source.prepareImage();
        if (source.config != 'ARGB_8888') {
          throw MissingDalvikBridge(
            'Bitmap scaling with ${source.config} destination quantization',
          );
        }
        final recorder = ui.PictureRecorder();
        // Use one recording for the exact full-source/full-destination mapping.
        final targetCanvas = ui.Canvas(recorder);
        targetCanvas.drawImageRect(
          source.image!,
          ui.Rect.fromLTWH(
            0,
            0,
            source.width.toDouble(),
            source.height.toDouble(),
          ),
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()
            ..isAntiAlias = false
            ..filterQuality = filter
                ? ui.FilterQuality.low
                : ui.FilterQuality.none,
        );
        final picture = recorder.endRecording(),
            image = picture.toImageSync(width, height);
        picture.dispose();
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (bytes == null) {
          image.dispose();
          throw StateError('Scaled Bitmap readback failed');
        }
        return javaAndroidBitmap(
          AndroidBitmap(
            width,
            height,
            Uint8List.fromList(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            ),
            mutable: true,
          )..image = image,
        );
      }

      v.suspendUntil(scale());
    },
  );
  put(
    'Landroid/graphics/BitmapFactory;',
    'decodeStream(Ljava/io/InputStream;)Landroid/graphics/Bitmap;',
    (v, a) {
      if (v.isNull(a[0])) return null;
      final decode = environment.decodeImageSync;
      final bytes = <int>[], scratch = v.array('[B', 8192);
      Future<Object?> decodeAsync() async {
        ui.Codec codec;
        try {
          codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
        } on Exception {
          return null;
        }
        final ui.Image image;
        try {
          image = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (data == null) {
          image.dispose();
          throw StateError('Decoded bitmap readback failed');
        }
        return javaAndroidBitmap(
          AndroidBitmap(
            image.width,
            image.height,
            Uint8List.fromList(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            ),
          )..image = image,
        );
      }

      Object? finish() {
        if (decode == null) v.suspendUntil(decodeAsync());
        final result = decode(Uint8List.fromList(bytes));
        return result == null ? null : javaAndroidBitmap(result);
      }

      void append(int count) {
        if (count == 0) {
          throw MissingDalvikBridge(
            'non-progressing BitmapFactory InputStream',
          );
        }
        bytes.addAll(scratch.values.take(count).map((n) => (n as int) & 255));
      }

      Object? drain() {
        while (true) {
          final int count;
          try {
            count = v.call('Ljava/io/InputStream;->read([B)I', [
              a[0],
              scratch,
            ], kind: 'virtual') as int;
          } on DalvikPause catch (pause) {
            pause.addFrame(
              DalvikResumeFrame(
                methodKey: 'Landroid/graphics/BitmapFactory;->decodeStream',
                pc: 0,
                resume: (completion) {
                  final n = completion.unwrap() as int;
                  if (n < 0) return finish();
                  append(n);
                  return drain();
                },
              ),
            );
            rethrow;
          }
          if (count < 0) return finish();
          append(count);
        }
      }

      return drain();
    },
  );
  put(_canvas, '<init>(Landroid/graphics/Bitmap;)V', (v, a) {
    final b = bitmap(a[1]);
    if (!b.mutable) {
      v.throwJava('Ljava/lang/IllegalStateException;', 'Immutable bitmap');
    }
    Object? attach() {
      v.object(a[0]).nativeValue = b.drawing ??= AndroidCanvasSurface(b);
      return null;
    }

    if (b.image == null &&
        b.rgba.any((channel) => channel != 0) &&
        b.config != 'RGB_565') {
      v.suspendUntil(b.prepareImage().then((_) => attach()));
    }
    return attach();
  });
  put(
    _canvas,
    'getWidth()I',
    (v, a) => (v.object(a[0]).nativeValue as AndroidCanvasSurface).width,
  );
  put(
    _canvas,
    'getHeight()I',
    (v, a) => (v.object(a[0]).nativeValue as AndroidCanvasSurface).height,
  );
  put(_canvas, 'save()I', (v, a) {
    final c = (v.object(a[0]).nativeValue as AndroidCanvasSurface).canvas;
    final count = c.getSaveCount();
    c.save();
    return count;
  });
  put(_canvas, 'restoreToCount(I)V', (v, a) {
    final c = (v.object(a[0]).nativeValue as AndroidCanvasSurface).canvas,
        count = intValue(a[1]);
    if (count < 1) {
      v.throwJava('Ljava/lang/IllegalArgumentException;', 'saveCount < 1');
    }
    c.restoreToCount(math.min(count, c.getSaveCount()));
    return null;
  });
  put(_canvas, 'drawText(Ljava/lang/String;IIFFLandroid/graphics/Paint;)V', (
    v,
    a,
  ) {
    final s = v.object(a[0]).nativeValue as AndroidCanvasSurface,
        p = paint(a[6]);
    final text = v.string(a[1]), start = intValue(a[2]), end = intValue(a[3]);
    checkRange(start, end - start, text.length);
    final paragraph = environment.paragraph(text.substring(start, end), p),
        metrics = paragraph.computeLineMetrics();
    if (metrics.isNotEmpty) {
      final width = paragraph.maxIntrinsicWidth,
          x = JBits.float(a, 4),
          baseline = JBits.float(a, 5);
      final left =
          x -
          (p.align == 1
              ? width / 2
              : p.align == 2
              ? width
              : 0);
      s.canvas.save();
      s.canvas.translate(left, baseline);
      if (p.textSkewX != 0) {
        s.canvas.transform(
          Float64List.fromList([
            1,
            0,
            0,
            0,
            p.textSkewX,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
        );
      }
      s.canvas.drawParagraph(paragraph, ui.Offset(0, -metrics.first.baseline));
      s.canvas.restore();
      s.bitmap.pixelsDirty = true;
      s.bitmap.paintVersion++;
    }
    paragraph.dispose();
    return null;
  });
}
