import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/compat/java_numbers.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_nio.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/engine/render/legacy_renderer.dart';
import 'package:green_farm_port/generated/c0047.dart';

const gl = 'Landroid/opengl/GLES20;';
const game = 'Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/GLLib;';
const imageType = 'Lc/c/a/a/a/w/m0;';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DalvikRuntime vm;
  late LegacyRenderer renderer;
  Object? call(String owner, String member, List<Object?> args) =>
      vm.call('$owner->$member', args, kind: 'static');
  DalvikArray array(String type, List<int> values) {
    final a = vm.array(type, values.length);
    a.values.setAll(0, values);
    return a;
  }

  int float(double n) => JavaNumbers.floatBits(n);
  void stat(String field, String type, Object? value) =>
      vm.putStatic(game, '$game->$field:$type', value);
  setUp(() async {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaNio(vm);
    renderer = LegacyRenderer();
    await renderer.load();
    registerLegacyRenderer(vm, renderer: renderer);
    vm.registerClass(
      DalvikClass(
        game,
        superclass: 'Ljava/lang/Object;',
        staticFields: {
          for (final name in [
            'i2',
            'j2',
            'k2',
            'c2',
            'd2',
            'e2',
            'v2',
            'w2',
            'M2',
            'N2',
            'O2',
            'P2',
          ])
            '$game->$name:I': 0,
          '$game->s2:[F': null,
          '$game->u2:[S': null,
          '$game->Q2:[F': null,
          '$game->l2:$imageType': null,
          '$game->r2:Ljava/nio/FloatBuffer;': null,
          '$game->t2:Ljava/nio/ShortBuffer;': null,
        },
      ),
    );
    // Isolated texture-constructor test doubles for diagnostics/config only.
    vm.registerNative(
      '$game->H0(Ljava/lang/String;Ljava/lang/String;I)V',
      (_, a) => null,
    );
    vm.registerNative('$game->k4()Z', (_, a) => 0);
    vm.registerNative('$game->d4()I', (_, a) => -1);
    vm.registerClass(
      DalvikClass(
        'Lc/c/a/a/a/w/p;',
        superclass: 'Ljava/lang/Object;',
        staticFields: {'Lc/c/a/a/a/w/p;->p:Z': 0, 'Lc/c/a/a/a/w/p;->y:Z': 0},
      ),
    );
    registerClass47(vm);
    stat(
      'r2',
      'Ljava/nio/FloatBuffer;',
      call('Ljava/nio/FloatBuffer;', 'allocate(I)Ljava/nio/FloatBuffer;', [32]),
    );
    stat(
      't2',
      'Ljava/nio/ShortBuffer;',
      call('Ljava/nio/ShortBuffer;', 'allocate(I)Ljava/nio/ShortBuffer;', [6]),
    );
    renderer.beginFrame(8, 8);
    call(gl, 'glViewport(IIII)V', [0, 0, 8, 8]);
    call(gl, 'glEnable(I)V', [3042]);
    call(gl, 'glBlendFunc(II)V', [770, 771]);
    call(gl, 'glClearColor(FFFF)V', [float(0), float(0), float(0), float(1)]);
    call(gl, 'glClear(I)V', [16384]);
  });
  DalvikObject texture(List<int> argb, int width, int height) {
    final image = vm.allocate(imageType),
        bytes = array('[I', argb.map((n) => n.toSigned(32)).toList());
    vm.call('$imageType-><init>([III)V', [
      image,
      bytes,
      width,
      height,
    ], kind: 'direct');
    return image;
  }

  void batch(
    DalvikObject image, {
    int effect = 0,
    List<int> fx = const [255, 255, 255, 255],
    bool linear = false,
  }) {
    stat('i2', 'I', 4);
    stat('k2', 'I', 6);
    stat('c2', 'I', 2);
    stat('d2', 'I', effect);
    stat('e2', 'I', 3);
    stat('v2', 'I', 5);
    stat('w2', 'I', 2);
    for (var n = 0; n < 4; n++) {
      stat(['M2', 'N2', 'O2', 'P2'][n], 'I', fx[n]);
    }
    stat('l2', imageType, image);
    stat(
      's2',
      '[F',
      array(
        '[F',
        [
          0.0,
          0,
          0,
          0,
          0,
          8,
          0,
          0,
          1,
          0,
          8,
          8,
          0,
          1,
          1,
          0,
          8,
          0,
          0,
          1,
        ].map((n) => float(n.toDouble())).toList(),
      ),
    );
    stat('u2', '[S', array('[S', [0, 1, 3, 1, 2, 3]));
    stat(
      'Q2',
      '[F',
      array(
        '[F',
        [
          .25,
          0,
          0,
          -1,
          0,
          -.25,
          0,
          1,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
        ].map((n) => float(n.toDouble())).toList(),
      ),
    );
    if (linear) call(gl, 'glTexParameteri(III)V', [3553, 10240, 9729]);
    call(game, 'T3(Lc/c/a/a/a/w/m1;[F)V', [null, null]);
  }

  Future<Uint8List> pixels() async {
    final picture = await renderer.renderFrame();
    final image = picture.toImageSync(8, 8);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    picture.dispose();
    image.dispose();
    return data!.buffer.asUint8List();
  }

  List<int> at(Uint8List bytes, int x, int y) =>
      bytes.sublist((y * 8 + x) * 4, (y * 8 + x) * 4 + 4);

  test('original m0 constructor preserves ARGB conversion side effects and real texture pixels', () async {
    final image = texture(
      [0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff],
      2,
      2,
    );
    final id =
        vm.asArray(vm.getField(image, '$imageType->g:[I')).values[0] as int;
    expect(renderer.texture(id).pixels, [
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
      255,
      255,
      255,
      255,
    ]);
    batch(image);
    expect(renderer.batches.single.positions, [0, 0, 8, 0, 8, 8, 0, 8]);
    final result = await pixels();
    expect(at(result, 1, 1), [255, 0, 0, 255]);
    expect(at(result, 6, 1), [0, 255, 0, 255]);
    expect(at(result, 1, 6), [0, 0, 255, 255]);
  });

  test('texture shader retains transparent RGB during straight-alpha bilinear sampling', () async {
    final image = texture([0x00ff0000, 0xff0000ff], 2, 1);
    batch(image, linear: true);
    final result = await pixels();
    // Pixel3 center -> source .875 -> 37.5% opaque blue mixed with transparent red.
    expect(at(result, 3, 4)[0], closeTo(60, 1));
    expect(at(result, 3, 4)[2], closeTo(36, 1));
  });

  test(
    'original shader effects render solid tint, luminance and color mix',
    () async {
      final image = texture([0xffff0000], 1, 1);
      for (final effect in [1, 2, 4]) {
        renderer.beginFrame(8, 8);
        call(gl, 'glClear(I)V', [16384]);
        batch(
          image,
          effect: effect,
          fx: effect == 4 ? [0, 0, 255, 128] : [0, 255, 0, 255],
        );
        final color = at(await pixels(), 4, 4);
        if (effect == 1) expect(color, [0, 255, 0, 255]);
        if (effect == 2) {
          expect(color[0], closeTo(54, 1));
          expect(color[1], color[0]);
          expect(color[2], color[0]);
        }
        if (effect == 4) {
          expect(color[0], closeTo(127, 1));
          expect(color[2], closeTo(128, 1));
          expect(color[3], 255);
        }
      }
    },
  );

  test('GLES4444 and5551 uploads use actual native short words', () {
    for (final type in [32819, 32820]) {
      final ids = array('[I', [0]);
      call(gl, 'glGenTextures(I[II)V', [1, ids, 0]);
      final id = ids.values[0] as int;
      call(gl, 'glBindTexture(II)V', [3553, id]);
      final source = array('[S', [
        type == 32819 ? 0xf81f.toSigned(16) : 0xf801.toSigned(16),
      ]);
      final buffer = call(
        'Ljava/nio/ShortBuffer;',
        'wrap([S)Ljava/nio/ShortBuffer;',
        [source],
      );
      call(gl, 'glTexImage2D(IIIIIIIILjava/nio/Buffer;)V', [
        3553,
        0,
        6408,
        1,
        1,
        0,
        6408,
        type,
        buffer,
      ]);
      expect(
        renderer.texture(id).pixels,
        type == 32819 ? [255, 136, 17, 255] : [255, 0, 0, 255],
      );
    }
  });

  test(
    'unsupported GL capabilities fail instead of claiming rendering success',
    () {
      expect(
        () => call(gl, 'glEnable(I)V', [2929]),
        throwsA(isA<MissingDalvikBridge>()),
      );
    },
  );

  test(
    'original indexed m0 constructor and palette produce real colors',
    () async {
      final image = vm.allocate(imageType);
      vm.call('$imageType-><init>([B[III)V', [
        image,
        array('[B', [0, 1, 2, 1]),
        array('[I', [
          0xffff0000.toSigned(32),
          0xff00ff00.toSigned(32),
          0xff0000ff.toSigned(32),
        ]),
        4,
        1,
      ], kind: 'direct');
      batch(image);
      final result = await pixels();
      expect(at(result, 0, 4), [255, 0, 0, 255]);
      expect(at(result, 2, 4), [0, 255, 0, 255]);
      expect(at(result, 4, 4), [0, 0, 255, 255]);
    },
  );

  test('render targets retain GL row orientation and source snapshots', () async {
    final source = texture(
      [0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff],
      2,
      2,
    );
    final target = texture(List.filled(64, 0xff000000), 8, 8);
    final targetId =
        vm.asArray(vm.getField(target, '$imageType->g:[I')).values[0] as int;
    final fbo = array('[I', [0]);
    call(gl, 'glGenFramebuffers(I[II)V', [1, fbo, 0]);
    call(gl, 'glBindFramebuffer(II)V', [36160, fbo.values[0]]);
    call(gl, 'glFramebufferTexture2D(IIIII)V', [
      36160,
      36064,
      3553,
      targetId,
      0,
    ]);
    batch(source);
    call(gl, 'glBindFramebuffer(II)V', [36160, 0]);
    batch(target);
    // Original GLLib.F3 applies the vertical flip when drawing an FBO image;
    // direct T3 with unflipped UVs must expose GL's bottom-to-top texture rows.
    final result = await pixels();
    expect(at(result, 1, 1), [0, 0, 255, 255]);
    expect(at(result, 1, 6), [255, 0, 0, 255]);
  });

  test(
    'actual blend state, scissor and colored geometry are honored',
    () async {
      final image = texture([0xff800000], 1, 1);
      batch(image);
      call(gl, 'glBlendFunc(II)V', [770, 1]);
      batch(image);
      expect(at(await pixels(), 4, 4), [255, 0, 0, 255]);
      renderer.beginFrame(8, 8);
      call(gl, 'glBlendFunc(II)V', [770, 771]);
      call(gl, 'glClear(I)V', [16384]);
      call(gl, 'glEnable(I)V', [3089]);
      call(gl, 'glScissor(IIII)V', [0, 0, 4, 4]);
      batch(image);
      stat('c2', 'I', 1);
      stat('v2', 'I', 7);
      stat(
        's2',
        '[F',
        array(
          '[F',
          [
            0.0,
            0,
            0,
            0,
            1,
            0,
            1,
            8,
            0,
            0,
            0,
            1,
            0,
            1,
            8,
            8,
            0,
            0,
            1,
            0,
            1,
            0,
            8,
            0,
            0,
            1,
            0,
            1,
          ].map((n) => float(n.toDouble())).toList(),
        ),
      );
      call(game, 'T3(Lc/c/a/a/a/w/m1;[F)V', [null, null]);
      final result = await pixels();
      expect(at(result, 1, 6), [0, 255, 0, 255]);
      expect(at(result, 1, 1), [0, 0, 0, 255]);
      expect(at(result, 6, 6), [0, 0, 0, 255]);
    },
  );

  test(
    'FBO preserves straight RGB under zero alpha and GLES alpha blending',
    () async {
      final source = texture([0x80ff0000], 1, 1);
      for (final writeAlpha in [true, false]) {
        renderer.beginFrame(8, 8);
        call(gl, 'glBindFramebuffer(II)V', [36160, 0]);
        call(gl, 'glColorMask(ZZZZ)V', [1, 1, 1, 1]);
        call(gl, 'glClear(I)V', [16384]);
        final target = texture(List.filled(64, 0x000000ff), 8, 8);
        final targetId =
            vm.asArray(vm.getField(target, '$imageType->g:[I')).values[0]
                as int;
        final fbo = array('[I', [0]);
        call(gl, 'glGenFramebuffers(I[II)V', [1, fbo, 0]);
        call(gl, 'glBindFramebuffer(II)V', [36160, fbo.values[0]]);
        call(gl, 'glFramebufferTexture2D(IIIII)V', [
          36160,
          36064,
          3553,
          targetId,
          0,
        ]);
        call(gl, 'glColorMask(ZZZZ)V', [1, 1, 1, writeAlpha ? 1 : 0]);
        batch(source);
        call(gl, 'glBindFramebuffer(II)V', [36160, 0]);
        call(gl, 'glColorMask(ZZZZ)V', [1, 1, 1, 1]);
        batch(target);
        final screen = await pixels(),
            stored = await renderer.readTexturePixels(targetId);
        expect(stored[0], closeTo(128, 1));
        expect(stored[2], closeTo(127, 1));
        expect(stored[3], writeAlpha ? closeTo(64, 1) : 0);
        if (writeAlpha) {
          expect(at(screen, 4, 4)[0], closeTo(32, 1));
          expect(at(screen, 4, 4)[2], closeTo(32, 1));
        } else {
          expect(at(screen, 4, 4), [0, 0, 0, 255]);
        }
      }
    },
  );

  test(
    'GLES upload honors four-byte row alignment without consuming padding',
    () {
      final ids = array('[I', [0]);
      call(gl, 'glGenTextures(I[II)V', [1, ids, 0]);
      final id = ids.values[0] as int;
      call(gl, 'glBindTexture(II)V', [3553, id]);
      final source = array('[S', [0xf801.toSigned(16), 0, 0x003f]);
      final buffer = call(
        'Ljava/nio/ShortBuffer;',
        'wrap([S)Ljava/nio/ShortBuffer;',
        [source],
      );
      call(gl, 'glTexImage2D(IIIIIIIILjava/nio/Buffer;)V', [
        3553,
        0,
        6408,
        1,
        2,
        0,
        6408,
        32820,
        buffer,
      ]);
      expect(renderer.texture(id).pixels, [255, 0, 0, 255, 0, 0, 255, 255]);
    },
  );

  test(
    'surface renderer context reports truthful metadata and clears GL errors',
    () {
      final value = vm.call(
        'Ljavax/microedition/khronos/opengles/GL10;->glGetString(I)Ljava/lang/String;',
        [renderer.glContext, 7937],
        kind: 'interface',
      );
      expect(vm.string(value), 'Flutter runtime-effect renderer');
      expect(call(gl, 'glGetString(I)Ljava/lang/String;', [0]), isNull);
      expect(call(gl, 'glGetError()I', []), 1280);
      expect(call(gl, 'glGetError()I', []), 0);
    },
  );
}
