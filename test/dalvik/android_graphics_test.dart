import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/compat/java_numbers.dart';
import 'package:green_farm_port/engine/dalvik/android_graphics.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_io.dart';
import 'package:green_farm_port/engine/dalvik/cooperative.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/generated/c0250.dart';
import 'package:green_farm_port/generated/c0264.dart';

const typeface = 'Landroid/graphics/Typeface;';
const paint = 'Landroid/graphics/Paint;';
const bitmap = 'Landroid/graphics/Bitmap;';
const canvas = 'Landroid/graphics/Canvas;';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final graphics = AndroidGraphicsEnvironment();
  setUpAll(graphics.loadFonts);
  late DalvikRuntime vm;
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerAndroidGraphics(vm, environment: graphics);
  });
  DalvikObject make(
    String owner, [
    String signature = '()V',
    List<Object?> args = const [],
  ]) {
    final object = vm.allocate(owner);
    vm.call('$owner-><init>$signature', [object, ...args], kind: 'direct');
    return object;
  }

  Object? call(
    DalvikObject object,
    String method, [
    List<Object?> args = const [],
  ]) => vm.call('${object.className}->$method', [
    object,
    ...args,
  ], kind: 'virtual');
  double asFloat(Object? bits) => JavaNumbers.floatFromBits(bits as int);

  test('Android Color parses exact AOSP names and hex ARGB values', () {
    Object? parse(String value) => vm.call(
      'Landroid/graphics/Color;->parseColor(Ljava/lang/String;)I',
      [vm.newString(value)],
      kind: 'static',
    );
    expect(parse('BLACK'), 0xff000000.toSigned(32));
    expect(parse('gray'), 0xff888888.toSigned(32));
    expect(parse('green'), 0xff00ff00.toSigned(32));
    expect(parse('teal'), 0xff008080.toSigned(32));
    expect(parse('#c0ffee'), 0xffc0ffee.toSigned(32));
    expect(parse('#12345678'), 0x12345678);
    for (final value in ['transparent', '#123', 'red ', '#zzzzzz']) {
      expect(() => parse(value), throwsA(isA<DalvikThrown>()));
    }
    expect(() => parse(''), throwsA(isA<DalvikThrown>()));
  });

  test('original q.c suspends for real PNG decode and Bitmap scaling then resumes', () async {
    registerJavaIo(vm);
    registerClass264(vm);
    final source = AndroidBitmap(
      2,
      1,
      Uint8List.fromList([255, 0, 0, 255, 0, 0, 255, 255]),
    );
    await source.prepareImage();
    final png = await source.image!.toByteData(format: ui.ImageByteFormat.png);
    final input = javaByteArrayInputStream(vm, png!.buffer.asUint8List());
    final imageObject = await DalvikExecutor().run(
      () => vm.call('Ld/b/b/q;->c(Ljava/io/InputStream;II)Ld/b/b/q;', [
        input,
        4,
        2,
      ], kind: 'static'),
    ) as DalvikObject;
    final bitmapObject = vm.getField(
      imageObject,
      'Ld/b/b/q;->c:Landroid/graphics/Bitmap;',
    ) as DalvikObject;
    final actual = bitmapObject.nativeValue as AndroidBitmap;
    expect([actual.width, actual.height], [4, 2]);
    expect(actual.rgba.sublist(0, 4), [255, 0, 0, 255]);
    expect(actual.rgba.sublist(12, 16), [0, 0, 255, 255]);
    expect(actual.rgba[4], inInclusiveRange(190, 192));
    expect(actual.rgba[6], inInclusiveRange(63, 65));
    final unchanged = await DalvikExecutor().run(
      () => vm.call(
        '$bitmap->createScaledBitmap(Landroid/graphics/Bitmap;IIZ)Landroid/graphics/Bitmap;',
        [bitmapObject, 4, 2, 1],
        kind: 'static',
      ),
    );
    expect(unchanged, same(bitmapObject));
    final invalid = await DalvikExecutor().run(
      () => vm.call(
        'Landroid/graphics/BitmapFactory;->decodeStream(Ljava/io/InputStream;)Landroid/graphics/Bitmap;',
        [
          javaByteArrayInputStream(vm, [1, 2, 3]),
        ],
        kind: 'static',
      ),
    );
    expect(invalid, isNull);
    // A native InputStream can itself pause before producing each chunk.
    // BitmapFactory must retain its accumulator and finish each read once.
    const deferred = 'Ltest/DeferredImageInput;';
    vm.registerExternalClass(deferred, superclass: 'Ljava/io/InputStream;');
    final encoded = png.buffer.asUint8List();
    var offset = 0, reads = 0;
    vm.registerNative('$deferred->read([B)I', (v, a) {
      reads++;
      if (offset == encoded.length) return -1;
      v.suspendUntil(
        Future<Object?>(() {
          final count = (encoded.length - offset).clamp(0, 16);
          for (var n = 0; n < count; n++) {
            v.arrayPut(a[1], n, encoded[offset + n].toSigned(8));
          }
          offset += count;
          return count;
        }),
      );
    });
    final decoded = await DalvikExecutor().run(
      () => vm.call(
        'Landroid/graphics/BitmapFactory;->decodeStream(Ljava/io/InputStream;)Landroid/graphics/Bitmap;',
        [DalvikObject(deferred)],
        kind: 'static',
      ),
    ) as DalvikObject;
    expect((decoded.nativeValue as AndroidBitmap).rgba, source.rgba);
    expect(reads, (encoded.length + 15) ~/ 16 + 1);
    source.image!.dispose();
  });

  test('Canvas getPixels awaits real glyph pixels and preserves further Canvas drawing', () async {
    final state = AndroidBitmap(64, 24, Uint8List(64 * 24 * 4), mutable: true);
    final object = javaAndroidBitmap(state);
    final c = make(canvas, '(Landroid/graphics/Bitmap;)V', [object]),
        p = make(paint);
    call(p, 'setColor(I)V', [0xff00ff00.toSigned(32)]);
    call(p, 'setTextSize(F)V', [JavaNumbers.floatBits(16)]);
    expect(call(c, 'save()I'), 1);
    void draw(double x) =>
        call(c, 'drawText(Ljava/lang/String;IIFFLandroid/graphics/Paint;)V', [
          vm.newString('W'),
          0,
          1,
          JavaNumbers.floatBits(x),
          JavaNumbers.floatBits(18),
          p,
        ]);
    final target = vm.array('[I', 64 * 24);
    Future<void> read() async {
      await DalvikExecutor().run(
        () =>
            call(object, 'getPixels([IIIIIII)V', [target, 0, 64, 0, 0, 64, 24]),
      );
    }

    draw(1);
    await read();
    final first = target.values.where((n) => (n as int) >>> 24 != 0).length;
    expect(first, greaterThan(20));
    draw(25);
    await read();
    expect(
      target.values.where((n) => (n as int) >>> 24 != 0).length,
      greaterThan(first),
    );
    expect(call(c, 'save()I'), 2);
    call(c, 'restoreToCount(I)V', [1]);
    expect(state.pixelsDirty, isFalse);
  });

  test('real AOSP fonts supply Android metrics and distinguish proportional glyphs', () {
    final p = make(paint);
    call(p, 'setTextSize(F)V', [JavaNumbers.floatBits(14)]);
    expect(asFloat(call(p, 'ascent()F')), -1900 * 14 / 2048);
    expect(asFloat(call(p, 'descent()F')), 500 * 14 / 2048);
    double measure(String text) => asFloat(
      call(p, 'measureText(Ljava/lang/String;II)F', [
        vm.newString(text),
        0,
        text.length,
      ]),
    );
    expect(measure('WWW'), greaterThan(measure('iii') * 2));
    final mono = vm.call(
      '$typeface->create(Ljava/lang/String;I)Landroid/graphics/Typeface;',
      [vm.newString('monospace'), 0],
      kind: 'static',
    );
    expect(
      call(
        p,
        'setTypeface(Landroid/graphics/Typeface;)Landroid/graphics/Typeface;',
        [mono],
      ),
      same(mono),
    );
    expect(measure('WWW'), closeTo(measure('iii'), 0.001));
  });

  test(
    'original DEX Font initializer constructs and measures actual AOSP fonts',
    () {
      registerClass250(vm);
      final font = vm.call(
        'Ld/b/b/l;->c()Ld/b/b/l;',
        [],
        kind: 'static',
      ) as DalvikObject;
      expect(call(font, 'g()I'), 16);
      expect(
        call(font, 'l(Ljava/lang/String;)I', [vm.newString('Green Farm 3')]),
        greaterThan(50),
      );
      expect(vm.executedInstructions, greaterThan(100));
    },
  );

  test('font measurement without a loaded source fails explicitly', () {
    final other = DalvikRuntime();
    registerJavaCore(other);
    registerAndroidGraphics(other, environment: AndroidGraphicsEnvironment());
    final p = other.allocate(paint);
    other.call('$paint-><init>()V', [p], kind: 'direct');
    expect(
      () => other.call('$paint->ascent()F', [p], kind: 'virtual'),
      throwsA(isA<MissingDalvikBridge>()),
    );
  });

  test('Bitmap.getPixels preserves original RGBA as signed ARGB and negative stride', () {
    final image = javaAndroidBitmap(
      AndroidBitmap(
        2,
        2,
        Uint8List.fromList([
          255,
          0,
          0,
          255,
          0,
          255,
          0,
          255,
          0,
          0,
          255,
          255,
          12,
          34,
          56,
          128,
        ]),
      ),
    );
    final target = vm.array('[I', 4);
    call(image, 'getPixels([IIIIIII)V', [target, 2, -2, 0, 0, 2, 2]);
    expect(target.values, [
      0xff0000ff.toSigned(32),
      0x800c2238.toSigned(32),
      0xffff0000.toSigned(32),
      0xff00ff00.toSigned(32),
    ]);
    call(image, 'recycle()V');
    expect(call(image, 'isRecycled()Z'), 1);
    expect(
      () => call(image, 'getPixels([IIIIIII)V', [target, 0, 2, 0, 0, 2, 2]),
      throwsA(isA<DalvikThrown>()),
    );
  });

  test('Canvas records and rasterizes real glyphs and preserves Android save counts', () async {
    const config = 'Landroid/graphics/Bitmap\$Config;';
    final argb = vm.getStatic(config, '$config->ARGB_8888:$config');
    final image = vm.call(
      '$bitmap->createBitmap(IILandroid/graphics/Bitmap\$Config;)Landroid/graphics/Bitmap;',
      [120, 40, argb],
      kind: 'static',
    ) as DalvikObject;
    final c = make(canvas, '(Landroid/graphics/Bitmap;)V', [image]);
    final p = make(paint);
    call(p, 'setTextSize(F)V', [JavaNumbers.floatBits(18)]);
    call(p, 'setAntiAlias(Z)V', [1]);
    call(p, 'setColor(I)V', [0xff00ff00.toSigned(32)]);
    expect(call(c, 'save()I'), 1);
    expect(call(c, 'save()I'), 2);
    call(c, 'restoreToCount(I)V', [1]);
    call(c, 'drawText(Ljava/lang/String;IIFFLandroid/graphics/Paint;)V', [
      vm.newString('Granja'),
      0,
      6,
      JavaNumbers.floatBits(5),
      JavaNumbers.floatBits(25),
      p,
    ]);
    final surface = c.nativeValue as AndroidCanvasSurface;
    final pixels = await surface.finish().toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(pixels, isNotNull);
    final rgba = pixels!.buffer.asUint8List();
    expect(
      List.generate(
        120 * 40,
        (i) => rgba[i * 4 + 3],
      ).where((n) => n > 0).length,
      greaterThan(50),
    );
    expect(
      List.generate(120 * 40, (i) => rgba[i * 4 + 1]).any((n) => n > 0),
      isTrue,
    );
  });
}
