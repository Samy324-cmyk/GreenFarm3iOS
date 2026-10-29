import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'java_files.dart';
import 'java_io.dart';
import 'android_intents.dart';
import 'android_packages.dart';
import 'cooperative.dart';
import 'numbers.dart';
import 'runtime.dart';

/// The original Android resource identifiers and decoded string values.
class AndroidResourceTable {
  AndroidResourceTable.fromJson(Map<String, dynamic> json)
    : source = json,
      packageName = json['package'] as String,
      versionName = json['versionName'] as String,
      versionCode = json['versionCode'] as int,
      minSdk = json['minSdk'] as int,
      targetSdk = json['targetSdk'] as int {
    for (final item in json['resources'] as List) {
      final row = Map<String, dynamic>.from(item as Map);
      byId[row['id'] as int] = row;
      byName['${row['type']}/${row['name']}'] = row['id'] as int;
    }
  }
  final String packageName, versionName;
  final Map<String, dynamic> source;
  final int versionCode, minSdk, targetSdk;
  final Map<int, Map<String, dynamic>> byId = {};
  final Map<String, int> byName = {};
  int identifier(String name, String? type, String? package) {
    var key = name, owner = package;
    if (key.contains(':')) {
      final parts = key.split(':');
      owner = parts.first;
      key = parts.skip(1).join(':');
    }
    if (owner != null && owner != packageName) return 0;
    if (!key.contains('/')) key = '$type/$key';
    return byName[key] ?? 0;
  }

  String? string(int id, String language) {
    final values = byId[id]?['values'] as Map?;
    return (values?[language] ?? values?['']) as String?;
  }
}

class AndroidDisplayMetrics {
  const AndroidDisplayMetrics({
    required this.width,
    required this.height,
    required this.density,
    required this.scaledDensity,
    required this.xdpi,
    required this.ydpi,
    this.rotation,
  });
  final int width, height;
  final double density, scaledDensity, xdpi, ydpi;
  final int? rotation;
  int get densityDpi => (density * 160).round();
}

class AndroidFileSystemStats {
  const AndroidFileSystemStats({
    required this.blockSize,
    required this.blockCount,
    required this.availableBlocks,
    required this.freeBlocks,
  });
  final int blockSize, blockCount, availableBlocks, freeBlocks;
}

class AndroidNetworkState {
  const AndroidNetworkState({
    required this.connected,
    required this.available,
    required this.type,
    this.subtype,
    this.transports,
    this.capabilities,
  });
  final bool connected, available;
  final int type;
  final int? subtype;
  final Set<int>? transports, capabilities;
}

/// Explicit values supplied by the Flutter host. Physical display density and
/// identity are never inferred from the logical game surface dimensions.
class AndroidContextEnvironment {
  AndroidContextEnvironment({
    required this.resources,
    required this.display,
    required this.filesDirectory,
    required this.cacheDirectory,
    required this.language,
    this.assetLoader,
    this.assetLister,
    this.rawResourceLoader,
    this.externalStorageDirectory,
    this.externalStorageState,
    this.fileSystemStats,
    this.networkState,
    this.networkStateForType,
    this.hasPermanentMenuKey,
    this.sourceArchivePath,
    this.signingCertificates,
  }) {
    if (!Directory(filesDirectory).isAbsolute ||
        !Directory(cacheDirectory).isAbsolute) {
      throw ArgumentError('Context storage directories must be absolute');
    }
    if (display.width <= 0 ||
        display.height <= 0 ||
        display.density <= 0 ||
        display.scaledDensity <= 0 ||
        display.xdpi <= 0 ||
        display.ydpi <= 0) {
      throw ArgumentError('Explicit positive display metrics required');
    }
  }
  final AndroidResourceTable resources;
  final AndroidDisplayMetrics display;
  final String filesDirectory, cacheDirectory, language;
  final List<int>? Function(String path)? assetLoader;
  final List<String> Function(String directory)? assetLister;
  final List<int>? Function(String resourcePath)? rawResourceLoader;
  final String? externalStorageDirectory;
  final String Function()? externalStorageState;
  final AndroidFileSystemStats Function(String path)? fileSystemStats;
  final AndroidNetworkState? Function()? networkState;
  final AndroidNetworkState? Function(int type)? networkStateForType;
  final bool? hasPermanentMenuKey;
  final String? sourceArchivePath;
  final List<List<int>>? signingCertificates;
  final Map<String, DalvikObject?> services = {};
  final Map<String, _Preferences> _preferences = {};
  final Map<DalvikObject, AndroidActivityState> activities = Map.identity();
  final Map<DalvikObject, AndroidViewState> views = Map.identity();
  final List<AndroidReceiverRegistration> receivers = [];
  DalvikObject? Function(Set<String> actions)? stickyBroadcast;
  void Function(DalvikObject activity, String lifecycle)? activityLifecycle;
  void Function(DalvikObject caller, DalvikObject intent, int? requestCode)?
  startActivity;
  void Function(DalvikObject activity)? finishActivity;
  void Function(AndroidWindowState window)? windowChanged;
  void Function(AndroidViewState view, int flags)? systemUiVisibilityChanged;
  void Function(AndroidViewState view, void Function() callback)?
  postViewCallback;
  void Function(AndroidViewState view)? insetsListenerChanged;
  void Function(AndroidSurfaceState surface)? bindSurface;
  void Function(AndroidViewState view)? requestFrame;
  void Function(DalvikObject activity, DalvikObject view)? setContentView;
  void Function(void Function())? postToUi;
  DalvikObject? applicationObject, resourcesObject, assetsObject, displayObject;

  /// Deliver a real host broadcast on the VM queue. Registration filters are
  /// snapshotted first, and every original receiver completes exactly once.
  Object? dispatchBroadcast(DalvikRuntime vm, DalvikObject intent) {
    final action = androidIntent(vm, intent).action;
    final targets = receivers.where((r) => r.actions.contains(action)).toList();
    Object? next(int index) {
      if (index == targets.length) return null;
      final target = targets[index];
      return dalvikThen(
        () => vm.call(
          'Landroid/content/BroadcastReceiver;->onReceive(Landroid/content/Context;Landroid/content/Intent;)V',
          [target.receiver, target.context, intent],
          kind: 'virtual',
        ),
        (_) => next(index + 1),
        methodKey: '<host broadcast $action>',
      );
    }

    return next(0);
  }
}

class AndroidViewState {
  AndroidViewState(this.object, this.context);
  final DalvikObject object, context;
  DalvikObject? parent, layoutParams;
  final List<DalvikObject> children = [];
  int width = 0, height = 0, visibility = 0, backgroundColor = 0;
  bool focused = false, focusable = false, focusableInTouchMode = false;
  int systemUiVisibility = 0;
  DalvikObject? systemUiVisibilityListener;
  DalvikObject? insetsListener;
  int orientation = 0;
}

/// Host renderer binding, retaining the original AndroidView_Renderer object.
/// Flutter dispatches its lifecycle/draw callbacks on the VM's execution queue.
class AndroidSurfaceState extends AndroidViewState {
  AndroidSurfaceState(super.object, super.context);
  final List<DalvikObject> callbacks = [];
  DalvikObject? renderer, holder;
  int clientVersion = 1, renderMode = 1, legacySurfaceType = 0;
  bool paused = false;
  void surfaceCreated(DalvikRuntime vm, DalvikObject gl, DalvikObject config) {
    final target = renderer;
    if (target == null) throw StateError('Surface has no renderer');
    vm.call(
      'Ld/b/b/m\$n;->onSurfaceCreated(Ljavax/microedition/khronos/opengles/GL10;Ljavax/microedition/khronos/egl/EGLConfig;)V',
      [target, gl, config],
      kind: 'virtual',
    );
  }

  void surfaceChanged(
    DalvikRuntime vm,
    DalvikObject gl,
    int width,
    int height,
  ) {
    this.width = width;
    this.height = height;
    final target = renderer;
    if (target == null) throw StateError('Surface has no renderer');
    vm.call(
      'Ld/b/b/m\$n;->onSurfaceChanged(Ljavax/microedition/khronos/opengles/GL10;II)V',
      [target, gl, width, height],
      kind: 'virtual',
    );
  }

  void drawFrame(DalvikRuntime vm, DalvikObject gl) {
    final target = renderer;
    if (target == null) throw StateError('Surface has no renderer');
    if (!paused) {
      vm.call(
        'Ld/b/b/m\$n;->onDrawFrame(Ljavax/microedition/khronos/opengles/GL10;)V',
        [target, gl],
        kind: 'virtual',
      );
    }
  }
}

class AndroidActivityState {
  AndroidActivityState(this.environment);
  final AndroidContextEnvironment environment;
  DalvikObject? contentView, intent;
  bool intentAssigned = false;
  bool created = false, destroyed = false, finishing = false;
  String lifecycle = 'initialized';
  AndroidWindowState? window;
  int resultCode = 0;
  DalvikObject? resultData;
  String? callingPackage;
}

class AndroidWindowState {
  AndroidWindowState(this.object, this.activity, this.decorView);
  final DalvikObject object, activity, decorView;
  int flags = 0, width = -1, height = -1;
}

class AndroidReceiverRegistration {
  AndroidReceiverRegistration(this.context, this.receiver, Set<String> actions)
    : actions = Set.unmodifiable(actions);
  final DalvikObject context, receiver;
  final Set<String> actions;
}

class _IntentFilter {
  final Set<String> actions = {};
}

class _Preferences {
  _Preferences(this.file) {
    final backup = File('${file.path}.bak');
    if (backup.existsSync()) {
      if (file.existsSync()) file.deleteSync();
      backup.renameSync(file.path);
    }
    if (file.existsSync()) {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      values.addAll(
        decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map))),
      );
    }
  }
  final File file;
  final Map<String, Map<String, dynamic>> values = {};
  bool save() {
    try {
      file.parent.createSync(recursive: true);
      final temp = File('${file.path}.tmp');
      temp.writeAsStringSync(jsonEncode(values), flush: true);
      final backup = File('${file.path}.bak');
      if (file.existsSync()) file.renameSync(backup.path);
      temp.renameSync(file.path);
      if (backup.existsSync()) backup.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

class _Editor {
  _Editor(this.preferences);
  final _Preferences preferences;
  final Map<String, Map<String, dynamic>?> pending = {};
  bool clear = false;
}

void registerAndroidContext(
  DalvikRuntime vm, {
  required AndroidContextEnvironment environment,
}) {
  const context = 'Landroid/content/Context;',
      wrapper = 'Landroid/content/ContextWrapper;',
      theme = 'Landroid/view/ContextThemeWrapper;',
      activity = 'Landroid/app/Activity;',
      resources = 'Landroid/content/res/Resources;',
      assets = 'Landroid/content/res/AssetManager;',
      metrics = 'Landroid/util/DisplayMetrics;',
      display = 'Landroid/view/Display;',
      manager = 'Landroid/view/WindowManager;',
      prefs = 'Landroid/content/SharedPreferences;',
      editor = 'Landroid/content/SharedPreferences\$Editor;';
  void cls(
    String name, {
    String? parent = 'Ljava/lang/Object;',
    List<String> interfaces = const [],
  }) => vm.registerExternalClass(
    name,
    superclass: parent,
    interfaces: interfaces,
  );
  void native(String owner, String method, DalvikBody body) =>
      vm.registerNative('$owner->$method', body);
  int integer(Object? v) => (v as int).toSigned(32);
  int bits(double d) =>
      (ByteData(4)..setFloat32(0, d, Endian.little)).getInt32(0, Endian.little);
  cls(context);
  cls(wrapper, parent: context);
  cls(theme, parent: wrapper);
  cls(activity, parent: theme);
  cls('Landroid/app/Application;', parent: wrapper);
  for (final name in [
    resources,
    assets,
    metrics,
    display,
    manager,
    prefs,
    editor,
    'Landroid/content/IntentFilter;',
    'Landroid/content/BroadcastReceiver;',
    'Landroid/content/Intent;',
  ]) {
    cls(name);
  }
  cls(
    'Landroid/content/res/Resources\$NotFoundException;',
    parent: 'Ljava/lang/RuntimeException;',
  );
  for (final field in ['widthPixels', 'heightPixels', 'densityDpi']) {
    vm.classes[metrics]!.instanceFields['$metrics->$field:I'] = 'I';
  }
  for (final field in ['density', 'scaledDensity', 'xdpi', 'ydpi']) {
    vm.classes[metrics]!.instanceFields['$metrics->$field:F'] = 'F';
  }
  DalvikObject metricObject() {
    final value = vm.allocate(metrics), d = environment.display;
    value.fields.addAll({
      '$metrics->widthPixels:I': d.width,
      '$metrics->heightPixels:I': d.height,
      '$metrics->densityDpi:I': d.densityDpi,
      '$metrics->density:F': bits(d.density),
      '$metrics->scaledDensity:F': bits(d.scaledDensity),
      '$metrics->xdpi:F': bits(d.xdpi),
      '$metrics->ydpi:F': bits(d.ydpi),
    });
    return value;
  }

  final currentMetrics = metricObject();
  // AOSP Android 11 DisplayMetrics constructor is empty; allocation supplies
  // JVM-zero fields, and Display.getMetrics subsequently fills host values.
  // https://github.com/aosp-mirror/platform_frameworks_base/blob/android-11.0.0_r1/core/java/android/util/DisplayMetrics.java
  native(metrics, '<init>()V', (_, a) {
    vm.object(a[0]);
    return null;
  });
  final resourceObject = DalvikObject(
    resources,
    nativeValue: environment.resources,
  );
  final assetObject = DalvikObject(assets, nativeValue: environment);
  final screen = DalvikObject(display, nativeValue: environment.display);
  final windowManager = DalvikObject(manager, nativeValue: screen);
  environment.resourcesObject = resourceObject;
  environment.assetsObject = assetObject;
  environment.displayObject = screen;
  environment.applicationObject = DalvikObject(
    'Landroid/app/Application;',
    nativeValue: environment,
  );
  environment.services['window'] = windowManager;
  native(activity, '<init>()V', (_, a) {
    final value = vm.object(a[0]);
    final state = AndroidActivityState(environment);
    environment.activities[value] = state;
    value.nativeValue = state;
    return null;
  });
  for (final event in [
    'onCreate',
    'onStart',
    'onResume',
    'onPause',
    'onStop',
    'onDestroy',
    'onRestart',
  ]) {
    native(
      activity,
      '$event(${event == 'onCreate' ? 'Landroid/os/Bundle;' : ''})V',
      (_, a) {
        final value = vm.object(a[0]),
            state = environment.activities[vm.object(a[0])];
        if (state == null) {
          throw MissingDalvikBridge('Activity native constructor not called');
        }
        state.lifecycle = event;
        if (event == 'onCreate') state.created = true;
        if (event == 'onDestroy') state.destroyed = true;
        environment.activityLifecycle?.call(value, event);
        return null;
      },
    );
  }
  native(
    activity,
    'isFinishing()Z',
    (_, a) => environment.activities[vm.object(a[0])]!.finishing ? 1 : 0,
  );
  native(
    activity,
    'isDestroyed()Z',
    (_, a) => environment.activities[vm.object(a[0])]!.destroyed ? 1 : 0,
  );
  AndroidActivityState activityState(Object? object) {
    final value = environment.activities[vm.object(object)];
    if (value == null) {
      throw MissingDalvikBridge('Activity native constructor not called');
    }
    return value;
  }

  native(activity, 'getIntent()Landroid/content/Intent;', (_, a) {
    final state = activityState(a[0]);
    if (state.intent == null && !state.intentAssigned) {
      state.intent = javaAndroidIntent();
      state.intentAssigned = true;
    }
    return state.intent;
  });
  native(activity, 'setIntent(Landroid/content/Intent;)V', (_, a) {
    final state = activityState(a[0]);
    state.intent = vm.isNull(a[1]) ? null : vm.object(a[1]);
    state.intentAssigned = true;
    return null;
  });
  native(activity, 'getCallingPackage()Ljava/lang/String;', (_, a) {
    final name = activityState(a[0]).callingPackage;
    return name == null ? null : vm.newString(name);
  });
  native(context, 'startActivity(Landroid/content/Intent;)V', (_, a) {
    final launch = environment.startActivity;
    if (launch == null) throw MissingDalvikBridge('Host Activity navigation');
    launch(vm.object(a[0]), vm.object(a[1]), null);
    return null;
  });
  native(activity, 'startActivityForResult(Landroid/content/Intent;I)V', (
    _,
    a,
  ) {
    final launch = environment.startActivity;
    if (launch == null) throw MissingDalvikBridge('Host Activity navigation');
    launch(vm.object(a[0]), vm.object(a[1]), a[2] as int);
    return null;
  });
  native(activity, 'finish()V', (_, a) {
    final finish = environment.finishActivity;
    if (finish == null) throw MissingDalvikBridge('Host Activity finish');
    activityState(a[0]).finishing = true;
    finish(vm.object(a[0]));
    return null;
  });
  native(activity, 'setResult(I)V', (_, a) {
    final state = activityState(a[0]);
    state.resultCode = a[1] as int;
    state.resultData = null;
    return null;
  });
  native(activity, 'setResult(ILandroid/content/Intent;)V', (_, a) {
    final state = activityState(a[0]);
    state.resultCode = a[1] as int;
    state.resultData = vm.isNull(a[2]) ? null : vm.object(a[2]);
    return null;
  });
  const window = 'Landroid/view/Window;',
      viewConfiguration = 'Landroid/view/ViewConfiguration;';
  cls(window);
  cls(viewConfiguration);
  native(
    viewConfiguration,
    'get(Landroid/content/Context;)$viewConfiguration',
    (_, a) {
      vm.object(a[0]);
      return DalvikObject(viewConfiguration, nativeValue: environment);
    },
  );
  native(viewConfiguration, 'hasPermanentMenuKey()Z', (_, a) {
    final value = environment.hasPermanentMenuKey;
    if (value == null) {
      throw MissingDalvikBridge('Host permanent-menu-key capability');
    }
    return value ? 1 : 0;
  });
  native(activity, 'getWindow()$window', (_, a) {
    final state = activityState(a[0]);
    if (state.window == null) {
      final object = DalvikObject(window),
          decor = DalvikObject('Landroid/view/View;');
      final decorState = AndroidViewState(decor, vm.object(a[0]));
      decor.nativeValue = decorState;
      environment.views[decor] = decorState;
      state.window = AndroidWindowState(object, vm.object(a[0]), decor);
      object.nativeValue = state.window;
    }
    return state.window!.object;
  });
  AndroidWindowState windowState(Object? value) =>
      vm.object(value).nativeValue as AndroidWindowState;
  void windowChange(AndroidWindowState value) {
    final change = environment.windowChanged;
    if (change == null) {
      throw MissingDalvikBridge('Host window flags/layout binding');
    }
    change(value);
  }

  native(
    window,
    'getDecorView()Landroid/view/View;',
    (_, a) => windowState(a[0]).decorView,
  );
  native(window, 'setFlags(II)V', (_, a) {
    final value = windowState(a[0]);
    value.flags =
        (value.flags & ~(a[2] as int)) | ((a[1] as int) & (a[2] as int));
    windowChange(value);
    return null;
  });
  native(window, 'addFlags(I)V', (_, a) {
    final value = windowState(a[0]);
    value.flags |= a[1] as int;
    windowChange(value);
    return null;
  });
  native(window, 'clearFlags(I)V', (_, a) {
    final value = windowState(a[0]);
    value.flags &= ~(a[1] as int);
    windowChange(value);
    return null;
  });
  native(window, 'setLayout(II)V', (_, a) {
    final value = windowState(a[0]);
    value.width = a[1] as int;
    value.height = a[2] as int;
    windowChange(value);
    return null;
  });
  native(wrapper, '<init>(Landroid/content/Context;)V', (_, a) {
    vm.object(a[1]);
    vm.object(a[0]).nativeValue = environment;
    return null;
  });
  native('Landroid/content/BroadcastReceiver;', '<init>()V', (_, a) {
    vm.object(a[0]).nativeValue = environment;
    return null;
  });
  native('Landroid/content/IntentFilter;', '<init>()V', (_, a) {
    vm.object(a[0]).nativeValue = _IntentFilter();
    return null;
  });
  native('Landroid/content/IntentFilter;', '<init>(Ljava/lang/String;)V', (
    _,
    a,
  ) {
    vm.object(a[0]).nativeValue = _IntentFilter()..actions.add(vm.string(a[1]));
    return null;
  });
  native('Landroid/content/IntentFilter;', 'addAction(Ljava/lang/String;)V', (
    _,
    a,
  ) {
    (vm.object(a[0]).nativeValue as _IntentFilter).actions.add(vm.string(a[1]));
    return null;
  });
  native(
    'Landroid/content/IntentFilter;',
    'hasAction(Ljava/lang/String;)Z',
    (_, a) =>
        (vm.object(a[0]).nativeValue as _IntentFilter).actions.contains(
          vm.string(a[1]),
        )
        ? 1
        : 0,
  );
  native(
    'Landroid/content/IntentFilter;',
    'countActions()I',
    (_, a) => (vm.object(a[0]).nativeValue as _IntentFilter).actions.length,
  );
  native(
    context,
    'registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;',
    (_, a) {
      final actions = (vm.object(a[2]).nativeValue as _IntentFilter).actions;
      final sticky = environment.stickyBroadcast;
      if (sticky == null &&
          (vm.isNull(a[1]) ||
              actions.any((action) => action.startsWith('android.')))) {
        throw MissingDalvikBridge(
          'Host sticky-broadcast facts for ${actions.join(',')}',
        );
      }
      if (!vm.isNull(a[1])) {
        environment.receivers.add(
          AndroidReceiverRegistration(
            vm.object(a[0]),
            vm.object(a[1]),
            actions,
          ),
        );
      }
      return sticky?.call(actions);
    },
  );
  native(context, 'unregisterReceiver(Landroid/content/BroadcastReceiver;)V', (
    _,
    a,
  ) {
    final receiver = vm.object(a[1]), before = environment.receivers.length;
    environment.receivers.removeWhere(
      (registration) =>
          identical(registration.context, a[0]) &&
          identical(registration.receiver, receiver),
    );
    if (before == environment.receivers.length) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'Receiver not registered',
      );
    }
    return null;
  });
  native(resources, 'getSystem()$resources', (_, a) => resourceObject);
  native(resources, 'getDisplayMetrics()$metrics', (_, a) => currentMetrics);
  native(context, 'getResources()$resources', (_, a) {
    vm.object(a[0]);
    return resourceObject;
  });
  native(
    activity,
    'getApplication()Landroid/app/Application;',
    (_, a) => environment.applicationObject,
  );
  String localActivityName(Object? value) {
    final descriptor = vm.object(value).className;
    final name = descriptor
        .substring(1, descriptor.length - 1)
        .replaceAll('/', '.');
    final prefix = '${environment.resources.packageName}.';
    return name.startsWith(prefix) ? name.substring(prefix.length) : name;
  }

  native(
    activity,
    'getLocalClassName()Ljava/lang/String;',
    (_, a) => vm.newString(localActivityName(a[0])),
  );
  native(
    activity,
    'getPreferences(I)$prefs',
    (_, a) => vm.call(
      '$context->getSharedPreferences(Ljava/lang/String;I)$prefs',
      [a[0], vm.newString(localActivityName(a[0])), a[1]],
      kind: 'virtual',
    ),
  );
  native(context, 'getAssets()$assets', (_, a) {
    vm.object(a[0]);
    return assetObject;
  });
  native(context, 'getPackageName()Ljava/lang/String;', (_, a) {
    vm.object(a[0]);
    return vm.newString(environment.resources.packageName);
  });
  native(context, 'getApplicationContext()$context', (_, a) {
    vm.object(a[0]);
    return environment.applicationObject;
  });
  native(context, 'getSystemService(Ljava/lang/String;)Ljava/lang/Object;', (
    _,
    a,
  ) {
    vm.object(a[0]);
    final name = vm.string(a[1]);
    if (!environment.services.containsKey(name)) {
      throw MissingDalvikBridge('Context system service $name');
    }
    return environment.services[name];
  });
  native(activity, 'getWindowManager()$manager', (_, a) {
    vm.object(a[0]);
    return windowManager;
  });
  native(manager, 'getDefaultDisplay()$display', (_, a) => screen);
  native(display, 'getWidth()I', (_, a) => environment.display.width);
  native(display, 'getHeight()I', (_, a) => environment.display.height);
  for (final method in ['getOrientation', 'getRotation']) {
    native(display, '$method()I', (_, a) {
      final rotation = environment.display.rotation;
      if (rotation == null) {
        throw MissingDalvikBridge('Logical display rotation');
      }
      return rotation;
    });
  }
  for (final method in ['getSize', 'getRealSize']) {
    native(display, '$method(Landroid/graphics/Point;)V', (_, a) {
      final point = vm.object(a[1]);
      point.fields['Landroid/graphics/Point;->x:I'] = environment.display.width;
      point.fields['Landroid/graphics/Point;->y:I'] =
          environment.display.height;
      return null;
    });
  }
  for (final method in ['getMetrics', 'getRealMetrics']) {
    native(display, '$method($metrics)V', (_, a) {
      vm.object(a[1]).fields.addAll(currentMetrics.fields);
      return null;
    });
  }
  native(
    resources,
    'getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I',
    (_, a) => environment.resources.identifier(
      vm.string(a[1]),
      vm.isNull(a[2]) ? null : vm.string(a[2]),
      vm.isNull(a[3]) ? null : vm.string(a[3]),
    ),
  );
  native(resources, 'getString(I)Ljava/lang/String;', (_, a) {
    final id = integer(a[1]),
        value = environment.resources.string(id, environment.language);
    if (value == null) {
      vm.throwJava(
        'Landroid/content/res/Resources\$NotFoundException;',
        'String resource #0x${id.toRadixString(16)}',
      );
    }
    return vm.newString(value);
  });
  native(
    context,
    'getString(I)Ljava/lang/String;',
    (_, a) => vm.call('$resources->getString(I)Ljava/lang/String;', [
      resourceObject,
      a[1],
    ], kind: 'virtual'),
  );
  native(resources, 'openRawResource(I)Ljava/io/InputStream;', (_, a) {
    final id = integer(a[1]),
        row = environment.resources.byId[id],
        paths = row?['paths'] as Map?;
    final path = (paths?[environment.language] ?? paths?['']) as String?;
    if (path == null) {
      vm.throwJava(
        'Landroid/content/res/Resources\$NotFoundException;',
        'Raw resource #0x${id.toRadixString(16)}',
      );
    }
    final load = environment.rawResourceLoader;
    if (load == null) {
      throw MissingDalvikBridge('Android raw resource loader for $path');
    }
    final bytes = load(path);
    if (bytes == null) {
      vm.throwJava('Landroid/content/res/Resources\$NotFoundException;', path);
    }
    return javaByteArrayInputStream(vm, bytes);
  });
  for (final mode in [false, true]) {
    native(
      assets,
      'open(Ljava/lang/String;${mode ? 'I' : ''})Ljava/io/InputStream;',
      (_, a) {
        final path = vm.string(a[1]), load = environment.assetLoader;
        if (load == null) throw MissingDalvikBridge('Android asset loader');
        final bytes = load(path);
        if (bytes == null) {
          vm.throwJava('Ljava/io/FileNotFoundException;', path);
        }
        return javaByteArrayInputStream(vm, bytes);
      },
    );
  }
  native(assets, 'list(Ljava/lang/String;)[Ljava/lang/String;', (_, a) {
    final list = environment.assetLister;
    if (list == null) {
      throw MissingDalvikBridge('Android asset directory listing');
    }
    final names = list(vm.string(a[1]));
    return vm.array('[Ljava/lang/String;', names.length)
      ..values.setAll(0, names.map(vm.newString));
  });
  DalvikObject file(String path) =>
      DalvikObject('Ljava/io/File;', nativeValue: JavaFilePath(path));
  String child(String name) {
    if (name.contains('/') || name.contains('\\')) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'File $name contains a path separator',
      );
    }
    return '${environment.filesDirectory}/$name';
  }

  native(context, 'getFilesDir()Ljava/io/File;', (_, a) {
    Directory(environment.filesDirectory).createSync(recursive: true);
    return file(environment.filesDirectory);
  });
  native(context, 'getCacheDir()Ljava/io/File;', (_, a) {
    Directory(environment.cacheDirectory).createSync(recursive: true);
    return file(environment.cacheDirectory);
  });
  native(
    context,
    'getFileStreamPath(Ljava/lang/String;)Ljava/io/File;',
    (_, a) => file(child(vm.string(a[1]))),
  );
  native(context, 'deleteFile(Ljava/lang/String;)Z', (_, a) {
    try {
      File(child(vm.string(a[1]))).deleteSync();
      return 1;
    } on FileSystemException {
      return 0;
    }
  });
  native(
    context,
    'openFileInput(Ljava/lang/String;)Ljava/io/FileInputStream;',
    (_, a) {
      final object = vm.allocate('Ljava/io/FileInputStream;');
      vm.call('Ljava/io/FileInputStream;-><init>(Ljava/lang/String;)V', [
        object,
        vm.newString(child(vm.string(a[1]))),
      ], kind: 'direct');
      return object;
    },
  );
  native(
    context,
    'openFileOutput(Ljava/lang/String;I)Ljava/io/FileOutputStream;',
    (_, a) {
      final mode = integer(a[2]);
      if (mode != 0 && mode != 32768) {
        throw MissingDalvikBridge('Android file mode $mode');
      }
      Directory(environment.filesDirectory).createSync(recursive: true);
      final object = vm.allocate('Ljava/io/FileOutputStream;');
      vm.call('Ljava/io/FileOutputStream;-><init>(Ljava/lang/String;Z)V', [
        object,
        vm.newString(child(vm.string(a[1]))),
        mode == 32768 ? 1 : 0,
      ], kind: 'direct');
      return object;
    },
  );
  _Preferences store(String name, int mode) {
    if (mode != 0) {
      throw MissingDalvikBridge('Android shared preferences mode $mode');
    }
    if (name.contains('/') || name.contains('\\')) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'Preference name has path separator',
      );
    }
    return environment._preferences.putIfAbsent(
      name,
      () => _Preferences(
        File(
          '${environment.filesDirectory}/shared_prefs/${Uri.encodeComponent(name)}.json',
        ),
      ),
    );
  }

  native(
    context,
    'getSharedPreferences(Ljava/lang/String;I)$prefs',
    (_, a) =>
        DalvikObject(prefs, nativeValue: store(vm.string(a[1]), integer(a[2]))),
  );
  _Preferences preference(Object? v) =>
      vm.object(v).nativeValue as _Preferences;
  native(
    prefs,
    'contains(Ljava/lang/String;)Z',
    (_, a) => preference(a[0]).values.containsKey(vm.string(a[1])) ? 1 : 0,
  );
  native(
    prefs,
    'edit()$editor',
    (_, a) => DalvikObject(editor, nativeValue: _Editor(preference(a[0]))),
  );
  for (final spec in {
    'String': 'Ljava/lang/String;',
    'Int': 'I',
    'Long': 'J',
    'Float': 'F',
    'Boolean': 'Z',
  }.entries) {
    final name = spec.key, type = spec.value;
    native(prefs, 'get$name(Ljava/lang/String;$type)$type', (_, a) {
      final entry = preference(a[0]).values[vm.string(a[1])];
      if (entry == null) return type == 'J' ? JBits.wide(a, 2) : a[2];
      if (entry['type'] != type) {
        vm.throwJava('Ljava/lang/ClassCastException;', vm.string(a[1]));
      }
      return type == 'Ljava/lang/String;'
          ? vm.newString(entry['value'] as String)
          : type == 'J'
          ? int.parse(entry['value'] as String)
          : entry['value'];
    });
    native(editor, 'put$name(Ljava/lang/String;$type)$editor', (_, a) {
      final value = type == 'J'
          ? JBits.wide(a, 2).toString()
          : type == 'Ljava/lang/String;'
          ? (vm.isNull(a[2]) ? null : vm.string(a[2]))
          : integer(a[2]);
      (vm.object(a[0]).nativeValue as _Editor).pending[vm.string(a[1])] =
          value == null ? null : {'type': type, 'value': value};
      return a[0];
    });
  }
  native(editor, 'remove(Ljava/lang/String;)$editor', (_, a) {
    (vm.object(a[0]).nativeValue as _Editor).pending[vm.string(a[1])] = null;
    return a[0];
  });
  native(editor, 'clear()$editor', (_, a) {
    (vm.object(a[0]).nativeValue as _Editor).clear = true;
    return a[0];
  });
  Object? commit(DalvikRuntime _, List<Object?> a) {
    final e = vm.object(a[0]).nativeValue as _Editor;
    if (e.clear) e.preferences.values.clear();
    for (final entry in e.pending.entries) {
      if (entry.value == null) {
        e.preferences.values.remove(entry.key);
      } else {
        e.preferences.values[entry.key] = entry.value!;
      }
    }
    e.pending.clear();
    e.clear = false;
    return e.preferences.save() ? 1 : 0;
  }

  native(editor, 'commit()Z', commit);
  native(editor, 'apply()V', (_, a) {
    commit(vm, a);
    return null;
  });
  native(activity, 'runOnUiThread(Ljava/lang/Runnable;)V', (_, a) {
    final runnable = vm.object(a[1]), post = environment.postToUi;
    if (post == null) throw MissingDalvikBridge('Flutter UI dispatcher');
    post(
      () =>
          vm.call('Ljava/lang/Runnable;->run()V', [runnable], kind: 'virtual'),
    );
    return null;
  });
  native(activity, 'setContentView(Landroid/view/View;)V', (_, a) {
    final state = environment.activities[vm.object(a[0])];
    if (state == null) {
      throw MissingDalvikBridge('Activity native constructor not called');
    }
    final view = vm.object(a[1]), attach = environment.setContentView;
    if (attach == null) {
      throw MissingDalvikBridge('Flutter content view attachment');
    }
    attach(vm.object(a[0]), view);
    state.contentView = view;
    return null;
  });
  registerAndroidPackages(
    vm,
    environment: AndroidPackageEnvironment(
      manifest: environment.resources.source,
      dataDirectory: Directory(environment.filesDirectory).parent.path,
      sourceArchivePath: environment.sourceArchivePath,
      signingCertificates: environment.signingCertificates,
      resourceId: (reference) =>
          environment.resources.byName[reference.replaceFirst('@', '')] ?? 0,
      resourceValue: (reference) {
        final id =
            environment.resources.byName[reference.replaceFirst('@', '')];
        final values = environment.resources.byId[id]?['values'] as Map?;
        return values?[environment.language] ?? values?[''];
      },
    ),
  );
  _registerStorageAndConnectivity(vm, environment);
  _registerAndroidViews(vm, environment);
}

class _AndroidStatFs {
  _AndroidStatFs(this.path, this.stats);
  String path;
  AndroidFileSystemStats stats;
}

void _registerStorageAndConnectivity(
  DalvikRuntime vm,
  AndroidContextEnvironment environment,
) {
  registerAndroidIntents(vm);
  const storage = 'Landroid/os/Environment;', statfs = 'Landroid/os/StatFs;';
  const manager = 'Landroid/net/ConnectivityManager;',
      info = 'Landroid/net/NetworkInfo;',
      network = 'Landroid/net/Network;',
      capabilities = 'Landroid/net/NetworkCapabilities;';
  for (final owner in [storage, statfs, manager, info, network, capabilities]) {
    vm.registerExternalClass(owner);
  }
  void native(String owner, String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);
  DalvikObject file(String path) =>
      DalvikObject('Ljava/io/File;', nativeValue: JavaFilePath(path));
  String external() {
    final path = environment.externalStorageDirectory;
    if (path == null) {
      throw MissingDalvikBridge('Host external-storage namespace');
    }
    return path;
  }

  native(storage, 'getExternalStorageState()Ljava/lang/String;', (_, a) {
    final state = environment.externalStorageState;
    if (state == null) {
      throw MissingDalvikBridge('External-storage mount/access state');
    }
    return vm.intern(state());
  });
  native(
    storage,
    'getExternalStorageDirectory()Ljava/io/File;',
    (_, a) => file(external()),
  );
  native(
    storage,
    'getDownloadCacheDirectory()Ljava/io/File;',
    (_, a) => file(environment.cacheDirectory),
  );
  native(
    'Landroid/content/Context;',
    'getExternalFilesDir(Ljava/lang/String;)Ljava/io/File;',
    (_, a) {
      var path =
          '${external()}/Android/data/${environment.resources.packageName}/files';
      if (!vm.isNull(a[1])) path += '/${vm.string(a[1])}';
      try {
        Directory(path).createSync(recursive: true);
        return file(path);
      } on FileSystemException {
        return null;
      }
    },
  );
  AndroidFileSystemStats stats(String path) {
    final get = environment.fileSystemStats;
    if (get == null) {
      throw MissingDalvikBridge('Filesystem allocation statistics for $path');
    }
    try {
      return get(path);
    } on FileSystemException catch (error) {
      vm.throwJava('Ljava/lang/IllegalArgumentException;', error.message);
    }
  }

  native(statfs, '<init>(Ljava/lang/String;)V', (_, a) {
    final path = vm.string(a[1]);
    vm.object(a[0]).nativeValue = _AndroidStatFs(path, stats(path));
    return null;
  });
  native(statfs, 'restat(Ljava/lang/String;)V', (_, a) {
    final path = vm.string(a[1]), result = stats(path);
    final state = vm.object(a[0]).nativeValue as _AndroidStatFs;
    state.path = path;
    state.stats = result;
    return null;
  });
  final fields = <String, int Function(AndroidFileSystemStats)>{
    'BlockSize': (s) => s.blockSize,
    'BlockCount': (s) => s.blockCount,
    'AvailableBlocks': (s) => s.availableBlocks,
    'FreeBlocks': (s) => s.freeBlocks,
  };
  for (final field in fields.entries) {
    native(
      statfs,
      'get${field.key}()I',
      (_, a) => field
          .value((vm.object(a[0]).nativeValue as _AndroidStatFs).stats)
          .toSigned(32),
    );
    native(
      statfs,
      'get${field.key}Long()J',
      (_, a) =>
          field.value((vm.object(a[0]).nativeValue as _AndroidStatFs).stats),
    );
  }
  for (final field in ['Available', 'Free', 'Total']) {
    native(statfs, 'get${field}Bytes()J', (_, a) {
      final value = (vm.object(a[0]).nativeValue as _AndroidStatFs).stats;
      return value.blockSize *
          (field == 'Available'
              ? value.availableBlocks
              : field == 'Free'
              ? value.freeBlocks
              : value.blockCount);
    });
  }
  AndroidNetworkState? active() {
    final get = environment.networkState;
    if (get == null) throw MissingDalvikBridge('Host active-network snapshot');
    return get();
  }

  if (environment.networkState != null) {
    environment.services.putIfAbsent(
      'connectivity',
      () => DalvikObject(manager, nativeValue: environment),
    );
  }
  native(manager, 'getActiveNetworkInfo()$info', (_, a) {
    final state = active();
    return state == null ? null : DalvikObject(info, nativeValue: state);
  });
  native(manager, 'getNetworkInfo(I)$info', (_, a) {
    final type = a[1] as int, get = environment.networkStateForType;
    AndroidNetworkState? state;
    if (get != null) {
      state = get(type);
    } else {
      state = active();
      if (state == null || state.type != type) {
        throw MissingDalvikBridge(
          'Host network snapshot for transport type $type',
        );
      }
    }
    return state == null ? null : DalvikObject(info, nativeValue: state);
  });
  native(manager, 'getActiveNetwork()$network', (_, a) {
    final state = active();
    return state == null ? null : DalvikObject(network, nativeValue: state);
  });
  native(manager, 'getNetworkCapabilities($network)$capabilities', (_, a) {
    if (vm.isNull(a[1])) return null;
    return DalvikObject(capabilities, nativeValue: vm.object(a[1]).nativeValue);
  });
  native(
    info,
    'getType()I',
    (_, a) => (vm.object(a[0]).nativeValue as AndroidNetworkState).type,
  );
  native(info, 'getSubtype()I', (_, a) {
    final subtype =
        (vm.object(a[0]).nativeValue as AndroidNetworkState).subtype;
    if (subtype == null) {
      throw MissingDalvikBridge('Host cellular radio subtype');
    }
    return subtype;
  });
  native(
    info,
    'isConnected()Z',
    (_, a) =>
        (vm.object(a[0]).nativeValue as AndroidNetworkState).connected ? 1 : 0,
  );
  native(
    info,
    'isAvailable()Z',
    (_, a) =>
        (vm.object(a[0]).nativeValue as AndroidNetworkState).available ? 1 : 0,
  );
  for (final method in ['hasTransport', 'hasCapability']) {
    native(capabilities, '$method(I)Z', (_, a) {
      final state = vm.object(a[0]).nativeValue as AndroidNetworkState;
      final values = method == 'hasTransport'
          ? state.transports
          : state.capabilities;
      if (values == null) {
        throw MissingDalvikBridge('Host network $method facts');
      }
      return values.contains(a[1]) ? 1 : 0;
    });
  }
}

void _registerAndroidViews(
  DalvikRuntime vm,
  AndroidContextEnvironment environment,
) {
  const view = 'Landroid/view/View;',
      group = 'Landroid/view/ViewGroup;',
      surface = 'Landroid/view/SurfaceView;',
      holder = 'Landroid/view/SurfaceHolder;',
      frame = 'Landroid/widget/FrameLayout;',
      params = 'Landroid/view/ViewGroup\$LayoutParams;',
      margin = 'Landroid/view/ViewGroup\$MarginLayoutParams;',
      frameParams = 'Landroid/widget/FrameLayout\$LayoutParams;';
  void native(String owner, String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);
  vm.registerExternalClass(view);
  vm.registerExternalClass(group, superclass: view);
  vm.registerExternalClass(surface, superclass: view);
  vm.registerExternalClass(frame, superclass: group);
  vm.registerExternalClass('Landroid/widget/LinearLayout;', superclass: group);
  vm.registerExternalClass('Landroid/widget/TextView;', superclass: view);
  vm.registerExternalClass(holder);
  vm.registerExternalClass(
    'Landroid/view/SurfaceHolder\$Callback;',
    superclass: null,
  );
  vm.registerExternalClass('Landroid/view/ViewParent;');
  vm.registerExternalClass(params);
  vm.registerExternalClass(margin, superclass: params);
  vm.registerExternalClass(frameParams, superclass: margin);
  for (final name in ['width', 'height']) {
    vm.classes[params]!.instanceFields['$params->$name:I'] = 'I';
  }
  for (final name in [
    'leftMargin',
    'topMargin',
    'rightMargin',
    'bottomMargin',
  ]) {
    vm.classes[margin]!.instanceFields['$margin->$name:I'] = 'I';
  }
  AndroidViewState state(Object? o) =>
      environment.views[vm.object(o)] ??
      (throw MissingDalvikBridge('Android View native constructor missing'));
  for (final owner in [
    view,
    group,
    frame,
    surface,
    'Landroid/widget/LinearLayout;',
    'Landroid/widget/TextView;',
  ]) {
    native(owner, '<init>(Landroid/content/Context;)V', (_, a) {
      final object = vm.object(a[0]), context = vm.object(a[1]);
      final value = owner == surface
          ? AndroidSurfaceState(object, context)
          : AndroidViewState(object, context);
      environment.views[object] = value;
      object.nativeValue = value;
      if (value is AndroidSurfaceState) {
        value.holder = DalvikObject(holder, nativeValue: value);
      }
      return null;
    });
  }
  native(
    view,
    'getContext()Landroid/content/Context;',
    (_, a) => state(a[0]).context,
  );
  native(view, 'getWidth()I', (_, a) => state(a[0]).width);
  native(view, 'getHeight()I', (_, a) => state(a[0]).height);
  native('Landroid/widget/LinearLayout;', 'setOrientation(I)V', (_, a) {
    final value = a[1] as int;
    if (value != 0 && value != 1) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'Invalid orientation',
      );
    }
    state(a[0]).orientation = value;
    return null;
  });
  native(view, 'post(Ljava/lang/Runnable;)Z', (_, a) {
    final post = environment.postViewCallback;
    if (post == null) throw MissingDalvikBridge('Host View.post after layout');
    final runnable = vm.object(a[1]);
    post(
      state(a[0]),
      () =>
          vm.call('Ljava/lang/Runnable;->run()V', [runnable], kind: 'virtual'),
    );
    return 1;
  });
  native(
    view,
    'setOnApplyWindowInsetsListener(Landroid/view/View\$OnApplyWindowInsetsListener;)V',
    (_, a) {
      final change = environment.insetsListenerChanged;
      if (change == null) {
        throw MissingDalvikBridge('Host window-insets callback binding');
      }
      final value = state(a[0]);
      value.insetsListener = vm.isNull(a[1]) ? null : vm.object(a[1]);
      change(value);
      return null;
    },
  );
  native(
    view,
    'getParent()Landroid/view/ViewParent;',
    (_, a) => state(a[0]).parent,
  );
  native(view, 'getVisibility()I', (_, a) => state(a[0]).visibility);
  native(view, 'setVisibility(I)V', (_, a) {
    state(a[0]).visibility = a[1] as int;
    return null;
  });
  native(view, 'setBackgroundColor(I)V', (_, a) {
    state(a[0]).backgroundColor = a[1] as int;
    return null;
  });
  native(
    view,
    'getSystemUiVisibility()I',
    (_, a) => state(a[0]).systemUiVisibility,
  );
  native(view, 'setSystemUiVisibility(I)V', (_, a) {
    final value = state(a[0]), change = environment.systemUiVisibilityChanged;
    if (change == null) {
      throw MissingDalvikBridge('Host system-UI visibility binding');
    }
    value.systemUiVisibility = a[1] as int;
    change(value, value.systemUiVisibility);
    return null;
  });
  native(
    view,
    'setOnSystemUiVisibilityChangeListener(Landroid/view/View\$OnSystemUiVisibilityChangeListener;)V',
    (_, a) {
      state(a[0]).systemUiVisibilityListener = vm.isNull(a[1])
          ? null
          : vm.object(a[1]);
      return null;
    },
  );
  for (final field in ['Focusable', 'FocusableInTouchMode']) {
    native(view, 'set$field(Z)V', (_, a) {
      final s = state(a[0]);
      if (field == 'Focusable') {
        s.focusable = a[1] != 0;
      } else {
        s.focusableInTouchMode = a[1] != 0;
      }
      return null;
    });
  }
  native(view, 'requestFocus()Z', (_, a) {
    final s = state(a[0]);
    s.focused = s.focusable && s.visibility == 0;
    return s.focused ? 1 : 0;
  });
  native(view, 'setLayoutParams($params)V', (_, a) {
    state(a[0]).layoutParams = vm.object(a[1]);
    return null;
  });
  for (final method in ['invalidate', 'postInvalidate']) {
    native(view, '$method()V', (_, a) {
      final request = environment.requestFrame;
      if (request == null) {
        throw MissingDalvikBridge('Flutter frame invalidation');
      }
      request(state(a[0]));
      return null;
    });
  }
  native(
    group,
    'indexOfChild($view)I',
    (_, a) => state(a[0]).children.indexOf(vm.object(a[1])),
  );
  native(group, 'removeView($view)V', (_, a) {
    final parent = state(a[0]), child = state(a[1]);
    if (parent.children.remove(child.object)) {
      child.parent = null;
    }
    return null;
  });
  native(group, 'addView($view$params)V', (_, a) {
    final parent = state(a[0]), child = state(a[1]);
    if (child.parent != null) {
      vm.throwJava(
        'Ljava/lang/IllegalStateException;',
        'Child already has a parent',
      );
    }
    child.parent = parent.object;
    child.layoutParams = vm.object(a[2]);
    parent.children.add(child.object);
    return null;
  });
  native(params, '<init>(II)V', (_, a) {
    vm.object(a[0]).fields['$params->width:I'] = a[1];
    vm.object(a[0]).fields['$params->height:I'] = a[2];
    return null;
  });
  native(frameParams, '<init>($params)V', (_, a) {
    vm.object(a[0]).fields['$params->width:I'] = vm.getField(
      a[1],
      '$params->width:I',
    );
    vm.object(a[0]).fields['$params->height:I'] = vm.getField(
      a[1],
      '$params->height:I',
    );
    return null;
  });
  native(margin, 'setMargins(IIII)V', (_, a) {
    final obj = vm.object(a[0]);
    for (var i = 0; i < 4; i++) {
      obj.fields['$margin->${['left', 'top', 'right', 'bottom'][i]}Margin:I'] =
          a[i + 1];
    }
    return null;
  });
  native(
    surface,
    'getHolder()$holder',
    (_, a) => (state(a[0]) as AndroidSurfaceState).holder,
  );
  native(holder, 'addCallback(Landroid/view/SurfaceHolder\$Callback;)V', (
    _,
    a,
  ) {
    final s = vm.object(a[0]).nativeValue as AndroidSurfaceState,
        callback = vm.object(a[1]);
    if (!s.callbacks.contains(callback)) s.callbacks.add(callback);
    return null;
  });
  native(holder, 'removeCallback(Landroid/view/SurfaceHolder\$Callback;)V', (
    _,
    a,
  ) {
    (vm.object(a[0]).nativeValue as AndroidSurfaceState).callbacks.remove(
      vm.object(a[1]),
    );
    return null;
  });
  native(holder, 'setType(I)V', (_, a) {
    (vm.object(a[0]).nativeValue as AndroidSurfaceState).legacySurfaceType =
        a[1] as int;
    return null;
  });
}

/// Replaces only the custom Android GLSurfaceView's EGL-thread management.
/// Source evidence: d/b/b/m.java setRenderer creates/configures EGL, creates
/// GLThread j and starts it. Flutter owns that surface/thread; the original
/// renderer d and all its calls into GLLib/cGame remain generated bytecode.
void registerOriginalSurfaceBinding(
  DalvikRuntime vm, {
  required AndroidContextEnvironment environment,
}) {
  const owner = 'Ld/b/b/m;';
  AndroidSurfaceState state(Object? object) {
    final value = environment.views[vm.object(object)];
    if (value is! AndroidSurfaceState) {
      throw MissingDalvikBridge('Original GLSurfaceView native state missing');
    }
    return value;
  }

  void native(String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);
  void unbound(AndroidSurfaceState s) {
    if (s.renderer != null) {
      vm.throwJava(
        'Ljava/lang/IllegalStateException;',
        'setRenderer has already been called for this instance.',
      );
    }
  }

  native('m()V', (_, a) {
    unbound(state(a[0]));
    return null;
  });
  native('setEGLContextClientVersion(I)V', (_, a) {
    final s = state(a[0]);
    unbound(s);
    s.clientVersion = a[1] as int;
    vm.putField(a[0], '$owner->y:I', s.clientVersion);
    return null;
  });
  native('setRenderer(Ld/b/b/m\$n;)V', (_, a) {
    final s = state(a[0]);
    unbound(s);
    final bind = environment.bindSurface;
    if (bind == null) {
      throw MissingDalvikBridge('Flutter renderer surface binding');
    }
    s.renderer = vm.object(a[1]);
    bind(s);
    return null;
  });
  native('setRenderMode(I)V', (_, a) {
    final mode = a[1] as int;
    if (mode != 0 && mode != 1) {
      vm.throwJava('Ljava/lang/IllegalArgumentException;', 'renderMode');
    }
    state(a[0]).renderMode = mode;
    return null;
  });
  native('getRenderMode()I', (_, a) => state(a[0]).renderMode);
  native('onPause()V', (_, a) {
    state(a[0]).paused = true;
    return null;
  });
  native('onResume()V', (_, a) {
    state(a[0]).paused = false;
    return null;
  });
}
