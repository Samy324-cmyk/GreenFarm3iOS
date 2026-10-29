import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/android_context.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_files.dart';
import 'package:green_farm_port/engine/dalvik/java_io.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

void main() {
  late DalvikRuntime vm;
  late AndroidContextEnvironment env;
  late Directory directory;
  late DalvikObject activity;
  const context = 'Landroid/content/Context;',
      activityClass = 'Landroid/app/Activity;',
      resources = 'Landroid/content/res/Resources;',
      assets = 'Landroid/content/res/AssetManager;',
      prefs = 'Landroid/content/SharedPreferences;',
      editor = 'Landroid/content/SharedPreferences\$Editor;';
  final table = AndroidResourceTable.fromJson(
    jsonDecode(
      File('assets/platform/android_resources.json').readAsStringSync(),
    ) as Map<String, dynamic>,
  );
  AndroidContextEnvironment environment() => AndroidContextEnvironment(
    resources: table,
    display: const AndroidDisplayMetrics(
      width: 800,
      height: 480,
      density: 2,
      scaledDensity: 2.5,
      xdpi: 320,
      ydpi: 321,
      rotation: 0,
    ),
    filesDirectory: directory.absolute.path,
    cacheDirectory: '${directory.absolute.path}/cache',
    language: 'es',
    assetLoader: (path) =>
        path == '800x480/fixture' ? [0, 127, 128, 255] : null,
    assetLister: (path) => path == ''
        ? ['800x480']
        : path == '800x480'
        ? ['fixture']
        : [],
  );
  Object? call(
    String owner,
    String member,
    List<Object?> args, {
    String kind = 'virtual',
  }) => vm.call('$owner->$member', args, kind: kind);
  DalvikObject construct(String owner, String descriptor, List<Object?> args) {
    final value = vm.allocate(owner);
    call(owner, '<init>$descriptor', [value, ...args], kind: 'direct');
    return value;
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('green-farm-context-test-');
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaIo(vm);
    registerJavaFiles(vm, workingDirectory: directory.absolute.path);
    env = environment();
    registerAndroidContext(vm, environment: env);
    activity = construct(activityClass, '()V', []);
  });
  tearDown(() {
    final absolute = directory.absolute.path,
        base = Directory.systemTemp.absolute.path;
    if (!absolute.startsWith(
      '$base${Platform.pathSeparator}green-farm-context-test-',
    )) {
      throw StateError('Unexpected test directory');
    }
    directory.deleteSync(recursive: true);
  });
  Matcher javaError(String type) =>
      isA<DalvikThrown>().having((e) => e.object.className, 'Java error', type);
  test(
    'Exact APK resource metadata and original MIDlet property identifiers',
    () {
      expect(table.packageName, 'com.gameloft.android.ANMP.GloftGF2F');
      expect(table.versionCode, 44425);
      expect(table.byId.length, 5153);
      final r = call(context, 'getResources()$resources', [activity]);
      expect(
        call(
          resources,
          'getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I',
          [
            r,
            vm.newString('MIDlet_Version'),
            vm.newString('string'),
            vm.newString(table.packageName),
          ],
        ),
        0x7f10043f,
      );
      expect(
        vm.string(
          call(resources, 'getString(I)Ljava/lang/String;', [r, 0x7f10043f]),
        ),
        '4.4.4',
      );
      expect(
        vm.string(
          call(resources, 'getString(I)Ljava/lang/String;', [r, 0x7f10043a]),
        ),
        'Green Farm 3',
      );
      expect(table.identifier('missing', 'string', table.packageName), 0);
      expect(
        () => call(resources, 'getString(I)Ljava/lang/String;', [r, 99]),
        throwsA(
          javaError('Landroid/content/res/Resources\$NotFoundException;'),
        ),
      );
    },
  );
  test(
    'Activity hierarchy, logical display metrics, explicit unknown services',
    () {
      expect(vm.instanceOf(activity, context), true);
      final r = call(context, 'getResources()$resources', [activity]),
          metrics = vm.object(
            call(
              resources,
              'getDisplayMetrics()Landroid/util/DisplayMetrics;',
              [r],
            ),
          );
      expect(
        vm.getField(metrics, 'Landroid/util/DisplayMetrics;->widthPixels:I'),
        800,
      );
      expect(
        vm.getField(metrics, 'Landroid/util/DisplayMetrics;->heightPixels:I'),
        480,
      );
      expect(
        vm.getField(metrics, 'Landroid/util/DisplayMetrics;->densityDpi:I'),
        320,
      );
      final manager = call(
        context,
        'getSystemService(Ljava/lang/String;)Ljava/lang/Object;',
        [activity, vm.newString('window')],
      );
      final display = call(
        'Landroid/view/WindowManager;',
        'getDefaultDisplay()Landroid/view/Display;',
        [manager],
      );
      expect(call('Landroid/view/Display;', 'getWidth()I', [display]), 800);
      expect(
        () => call(
          context,
          'getSystemService(Ljava/lang/String;)Ljava/lang/Object;',
          [activity, vm.newString('phone')],
        ),
        throwsA(isA<MissingDalvikBridge>()),
      );
    },
  );
  test('Asset streams and listing expose actual supplied bytes', () {
    final a = call(context, 'getAssets()$assets', [activity]);
    final stream = call(
      assets,
      'open(Ljava/lang/String;)Ljava/io/InputStream;',
      [a, vm.newString('800x480/fixture')],
    );
    expect(
      List.generate(
        5,
        (_) => call('Ljava/io/InputStream;', 'read()I', [stream]),
      ),
      [0, 127, 128, 255, -1],
    );
    final list = vm.asArray(
      call(assets, 'list(Ljava/lang/String;)[Ljava/lang/String;', [
        a,
        vm.newString('800x480'),
      ]),
    );
    expect(list.values.map(vm.string), ['fixture']);
    expect(
      () => call(assets, 'open(Ljava/lang/String;)Ljava/io/InputStream;', [
        a,
        vm.newString('missing'),
      ]),
      throwsA(javaError('Ljava/io/FileNotFoundException;')),
    );
  });
  test('SharedPreferences commit persists typed data and reloads without precision loss', () {
    final p = call(context, 'getSharedPreferences(Ljava/lang/String;I)$prefs', [
      activity,
      vm.newString('save'),
      0,
    ]);
    final e = call(prefs, 'edit()$editor', [p]);
    call(editor, 'putString(Ljava/lang/String;Ljava/lang/String;)$editor', [
      e,
      vm.newString('name'),
      vm.newString('granĳa'),
    ]);
    call(editor, 'putInt(Ljava/lang/String;I)$editor', [
      e,
      vm.newString('level'),
      31,
    ]);
    call(editor, 'putLong(Ljava/lang/String;J)$editor', [
      e,
      vm.newString('ticks'),
      -1,
      2147483647,
    ]);
    call(editor, 'putFloat(Ljava/lang/String;F)$editor', [
      e,
      vm.newString('negativeZero'),
      -2147483648,
    ]);
    expect(call(editor, 'commit()Z', [e]), 1);
    final another = DalvikRuntime();
    registerJavaCore(another);
    registerJavaIo(another);
    registerJavaFiles(another, workingDirectory: directory.absolute.path);
    registerAndroidContext(another, environment: environment());
    final native = another.allocate(activityClass);
    another.call('$activityClass-><init>()V', [native], kind: 'direct');
    final reopened = another.call(
      '$context->getSharedPreferences(Ljava/lang/String;I)$prefs',
      [native, another.newString('save'), 0],
      kind: 'virtual',
    );
    Object? read(String member, List<Object?> a) =>
        another.call('$prefs->$member', [reopened, ...a], kind: 'virtual');
    expect(
      another.string(
        read(
          'getString(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
          [another.newString('name'), null],
        ),
      ),
      'granĳa',
    );
    expect(
      read('getInt(Ljava/lang/String;I)I', [another.newString('level'), 0]),
      31,
    );
    expect(
      read('getLong(Ljava/lang/String;J)J', [another.newString('ticks'), 0, 0]),
      9223372036854775807,
    );
    expect(
      read('getFloat(Ljava/lang/String;F)F', [
        another.newString('negativeZero'),
        0,
      ]),
      -2147483648,
    );
  });
  test(
    'Preference clear/remove/default/type mismatch preserve Android semantics',
    () {
      final p = call(
            context,
            'getSharedPreferences(Ljava/lang/String;I)$prefs',
            [activity, vm.newString('save'), 0],
          ),
          e = call(prefs, 'edit()$editor', [
            call(context, 'getSharedPreferences(Ljava/lang/String;I)$prefs', [
              activity,
              vm.newString('save'),
              0,
            ]),
          ]);
      call(editor, 'putInt(Ljava/lang/String;I)$editor', [
        e,
        vm.newString('number'),
        7,
      ]);
      call(editor, 'commit()Z', [e]);
      expect(
        () => call(
          prefs,
          'getString(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
          [p, vm.newString('number'), null],
        ),
        throwsA(javaError('Ljava/lang/ClassCastException;')),
      );
      call(editor, 'putInt(Ljava/lang/String;I)$editor', [
        e,
        vm.newString('kept'),
        9,
      ]);
      call(editor, 'clear()$editor', [e]);
      call(editor, 'commit()Z', [e]);
      expect(
        call(prefs, 'contains(Ljava/lang/String;)Z', [
          p,
          vm.newString('number'),
        ]),
        0,
      );
      expect(
        call(prefs, 'getInt(Ljava/lang/String;I)I', [
          p,
          vm.newString('kept'),
          0,
        ]),
        9,
      );
      call(editor, 'remove(Ljava/lang/String;)$editor', [
        e,
        vm.newString('kept'),
      ]);
      call(editor, 'apply()V', [e]);
      expect(
        call(prefs, 'getInt(Ljava/lang/String;I)I', [
          p,
          vm.newString('kept'),
          52,
        ]),
        52,
      );
    },
  );
  test(
    'Context file I/O resolves real private files, rejects path traversal',
    () {
      final output = call(
        context,
        'openFileOutput(Ljava/lang/String;I)Ljava/io/FileOutputStream;',
        [activity, vm.newString('save.bin'), 0],
      );
      call('Ljava/io/OutputStream;', 'write(I)V', [output, 123]);
      call('Ljava/io/OutputStream;', 'close()V', [output]);
      expect(File('${directory.path}/save.bin').readAsBytesSync(), [123]);
      final input = call(
        context,
        'openFileInput(Ljava/lang/String;)Ljava/io/FileInputStream;',
        [activity, vm.newString('save.bin')],
      );
      expect(call('Ljava/io/InputStream;', 'read()I', [input]), 123);
      call('Ljava/io/InputStream;', 'close()V', [input]);
      expect(
        () => call(
          context,
          'getFileStreamPath(Ljava/lang/String;)Ljava/io/File;',
          [activity, vm.newString('../other')],
        ),
        throwsA(javaError('Ljava/lang/IllegalArgumentException;')),
      );
    },
  );
  test('View and surface bindings require host callbacks and retain original renderer', () {
    vm.registerExternalClass(
      'Ld/b/b/m;',
      superclass: 'Landroid/view/SurfaceView;',
    );
    vm.classes['Ld/b/b/m;']!.instanceFields['Ld/b/b/m;->y:I'] = 'I';
    registerOriginalSurfaceBinding(vm, environment: env);
    final surface = vm.allocate('Ld/b/b/m;');
    call('Landroid/view/SurfaceView;', '<init>(Landroid/content/Context;)V', [
      surface,
      activity,
    ], kind: 'direct');
    final renderer = DalvikObject('LTestRenderer;');
    expect(
      () =>
          call('Ld/b/b/m;', 'setRenderer(Ld/b/b/m\$n;)V', [surface, renderer]),
      throwsA(isA<MissingDalvikBridge>()),
    );
    final bound = <AndroidSurfaceState>[];
    env.bindSurface = bound.add;
    call('Ld/b/b/m;', 'setEGLContextClientVersion(I)V', [surface, 2]);
    call('Ld/b/b/m;', 'setRenderer(Ld/b/b/m\$n;)V', [surface, renderer]);
    expect(bound.single.renderer, same(renderer));
    expect(bound.single.clientVersion, 2);
    expect(
      () =>
          call('Ld/b/b/m;', 'setRenderer(Ld/b/b/m\$n;)V', [surface, renderer]),
      throwsA(javaError('Ljava/lang/IllegalStateException;')),
    );
    call('Ld/b/b/m;', 'onPause()V', [surface]);
    expect(bound.single.paused, true);
    call('Ld/b/b/m;', 'onResume()V', [surface]);
    expect(bound.single.paused, false);
  });
}
