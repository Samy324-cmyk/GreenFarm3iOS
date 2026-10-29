import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/android_context.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_files.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/platform/windows_filesystem.dart';

void main() {
  const storage = 'Landroid/os/Environment;', statfs = 'Landroid/os/StatFs;';
  const manager = 'Landroid/net/ConnectivityManager;',
      info = 'Landroid/net/NetworkInfo;';
  late DalvikRuntime vm;
  late Directory directory;
  final resources = AndroidResourceTable.fromJson(
    jsonDecode(
      File('assets/platform/android_resources.json').readAsStringSync(),
    ) as Map<String, dynamic>,
  );
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'green-farm-services-test-',
    );
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaFiles(vm, workingDirectory: directory.absolute.path);
  });
  tearDown(() {
    final prefix =
        '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}green-farm-services-test-';
    if (!directory.absolute.path.startsWith(prefix)) {
      throw StateError('Unexpected fixture directory');
    }
    directory.deleteSync(recursive: true);
  });
  AndroidContextEnvironment environment({
    String Function()? storageState,
    AndroidFileSystemStats Function(String)? stats,
    AndroidNetworkState? Function()? network,
    AndroidNetworkState? Function(int)? networkByType,
    String? sourceArchivePath,
  }) => AndroidContextEnvironment(
    resources: resources,
    display: const AndroidDisplayMetrics(
      width: 800,
      height: 480,
      density: 1,
      scaledDensity: 1,
      xdpi: 160,
      ydpi: 160,
    ),
    filesDirectory: '${directory.path}/files',
    cacheDirectory: '${directory.path}/cache',
    language: 'en',
    hasPermanentMenuKey: false,
    externalStorageDirectory: '${directory.path}/external',
    externalStorageState: storageState,
    fileSystemStats: stats,
    networkState: network,
    networkStateForType: networkByType,
    sourceArchivePath: sourceArchivePath,
    signingCertificates: [
      File('assets/platform/apk_signer_0.der').readAsBytesSync(),
    ],
  );
  Object? invoke(
    String owner,
    String member,
    List<Object?> args, {
    String kind = 'virtual',
  }) => vm.call('$owner->$member', args, kind: kind);
  test(
    'PackageManager exposes actual manifest, archive and public signer bytes',
    () {
      const pm = 'Landroid/content/pm/PackageManager;',
          app = 'Landroid/content/pm/ApplicationInfo;',
          pkg = 'Landroid/content/pm/PackageInfo;';
      final archive = File('assets/provenance/original.apk').absolute.path;
      registerAndroidContext(
        vm,
        environment: environment(sourceArchivePath: archive),
      );
      final context = DalvikObject('Landroid/content/Context;');
      final manager = invoke(
        'Landroid/content/Context;',
        'getPackageManager()$pm',
        [context],
      );
      final info = invoke(pm, 'getPackageInfo(Ljava/lang/String;I)$pkg', [
        manager,
        vm.newString(resources.packageName),
        1 | 64 | 128 | 4096,
      ]);
      final application = vm.getField(info, '$pkg->applicationInfo:$app');
      expect(
        vm.string(
          vm.getField(application, '$app->sourceDir:Ljava/lang/String;'),
        ),
        archive,
      );
      expect(vm.getField(info, '$pkg->versionCode:I'), 44425);
      expect(
        vm
            .asArray(
              vm.getField(
                info,
                '$pkg->activities:[Landroid/content/pm/ActivityInfo;',
              ),
            )
            .values
            .length,
        36,
      );
      expect(
        vm
            .asArray(
              vm.getField(
                info,
                '$pkg->requestedPermissions:[Ljava/lang/String;',
              ),
            )
            .values
            .length,
        14,
      );
      final metadata = vm.getField(
        application,
        '$app->metaData:Landroid/os/Bundle;',
      );
      expect(
        invoke('Landroid/os/Bundle;', 'getInt(Ljava/lang/String;)I', [
          metadata,
          vm.newString('com.google.android.gms.version'),
        ]),
        12451000,
      );
      expect(
        vm.string(
          invoke(
            'Landroid/os/Bundle;',
            'getString(Ljava/lang/String;)Ljava/lang/String;',
            [metadata, vm.newString('com.facebook.sdk.ApplicationId')],
          ),
        ),
        '554013181278341',
      );
      final signatures = vm.asArray(
        vm.getField(info, '$pkg->signatures:[Landroid/content/pm/Signature;'),
      );
      expect(signatures.values.length, 1);
      final bytes = vm
          .asArray(
            invoke('Landroid/content/pm/Signature;', 'toByteArray()[B', [
              signatures.values.single,
            ]),
          )
          .values
          .map((v) => (v as int) & 255)
          .toList();
      expect(bytes, File('assets/platform/apk_signer_0.der').readAsBytesSync());
      expect(
        () => invoke(pm, 'getPackageInfo(Ljava/lang/String;I)$pkg', [
          manager,
          vm.newString('unknown.host.package'),
          0,
        ]),
        throwsA(isA<MissingDalvikBridge>()),
      );
    },
  );
  test('Activity lifecycle and navigation forward real Intent/state to host callbacks', () {
    final env = environment();
    registerAndroidContext(vm, environment: env);
    const owner = 'Landroid/app/Activity;';
    final activity = vm.allocate(owner);
    invoke(owner, '<init>()V', [activity], kind: 'direct');
    invoke(owner, 'onCreate(Landroid/os/Bundle;)V', [activity, null]);
    expect(env.activities[activity]!.created, true);
    final intent = invoke(owner, 'getIntent()Landroid/content/Intent;', [
      activity,
    ]) as DalvikObject;
    final launches = <Object?>[];
    env.startActivity = (caller, data, request) {
      launches.addAll([caller, data, request]);
    };
    invoke(owner, 'startActivityForResult(Landroid/content/Intent;I)V', [
      activity,
      intent,
      274,
    ]);
    expect(launches, [activity, intent, 274]);
    DalvikObject? finished;
    env.finishActivity = (value) => finished = value;
    invoke(owner, 'setResult(I)V', [activity, 274]);
    invoke(owner, 'finish()V', [activity]);
    expect(finished, same(activity));
    expect(env.activities[activity]!.resultCode, 274);
    expect(invoke(owner, 'isFinishing()Z', [activity]), 1);
    invoke(owner, 'setIntent(Landroid/content/Intent;)V', [activity, null]);
    expect(
      invoke(owner, 'getIntent()Landroid/content/Intent;', [activity]),
      null,
    );
  });
  test('Window and View.post retain host-visible flags and wait for actual layout dispatch', () {
    final env = environment();
    registerAndroidContext(vm, environment: env);
    const activityType = 'Landroid/app/Activity;',
        windowType = 'Landroid/view/Window;',
        viewType = 'Landroid/view/View;';
    final activity = vm.allocate(activityType);
    invoke(activityType, '<init>()V', [activity], kind: 'direct');
    final window = invoke(activityType, 'getWindow()$windowType', [activity]);
    expect(
      invoke(activityType, 'getWindow()$windowType', [activity]),
      same(window),
    );
    final flags = <int>[];
    env.windowChanged = (state) => flags.add(state.flags);
    invoke(windowType, 'setFlags(II)V', [window, 0xff, 0x0f]);
    invoke(windowType, 'addFlags(I)V', [window, 0x80]);
    invoke(windowType, 'clearFlags(I)V', [window, 0x03]);
    expect(flags, [0x0f, 0x8f, 0x8c]);
    final decor =
        invoke(windowType, 'getDecorView()$viewType', [window]) as DalvikObject;
    final chrome = <int>[];
    env.systemUiVisibilityChanged = (_, value) => chrome.add(value);
    invoke(viewType, 'setSystemUiVisibility(I)V', [decor, 5894]);
    expect(chrome, [5894]);
    vm.registerExternalClass('Lfixture/Posted;');
    var called = false;
    vm.registerNative('Lfixture/Posted;->run()V', (_, a) {
      called = true;
      expect(env.views[decor]!.width, 640);
      return null;
    });
    void Function()? pending;
    env.postViewCallback = (view, callback) => pending = callback;
    expect(
      invoke(viewType, 'post(Ljava/lang/Runnable;)Z', [
        decor,
        DalvikObject('Lfixture/Posted;'),
      ]),
      1,
    );
    expect(called, false);
    env.views[decor]!.width = 640;
    pending!();
    expect(called, true);
  });
  test('storage namespace is explicit and external app files use real directories', () {
    final env = environment(storageState: () => 'mounted');
    registerAndroidContext(vm, environment: env);
    expect(
      invoke(
        storage,
        'getExternalStorageState()Ljava/lang/String;',
        [],
        kind: 'static',
      ),
      same(vm.intern('mounted')),
    );
    final value = invoke(
      storage,
      'getExternalStorageDirectory()Ljava/io/File;',
      [],
      kind: 'static',
    ) as DalvikObject;
    expect(
      (value.nativeValue as JavaFilePath).path,
      env.externalStorageDirectory,
    );
    final context = DalvikObject('Landroid/content/Context;');
    final appFiles = invoke(
      'Landroid/content/Context;',
      'getExternalFilesDir(Ljava/lang/String;)Ljava/io/File;',
      [context, vm.newString('music')],
    ) as DalvikObject;
    final path = (appFiles.nativeValue as JavaFilePath).path;
    expect(
      path,
      '${env.externalStorageDirectory}/Android/data/${resources.packageName}/files/music',
    );
    expect(Directory(path).existsSync(), true);
  });
  test(
    'StatFs snapshots real provider results, narrows legacy ints and restats',
    () {
      var count = 0;
      registerAndroidContext(
        vm,
        environment: environment(
          stats: (path) {
            if (path == 'bad') {
              throw const FileSystemException('Invalid fixture path');
            }
            count++;
            return AndroidFileSystemStats(
              blockSize: 4096,
              blockCount: 1 << 33,
              availableBlocks: (1 << 31) + count,
              freeBlocks: 1 << 32,
            );
          },
        ),
      );
      final value = vm.allocate(statfs);
      invoke(statfs, '<init>(Ljava/lang/String;)V', [
        value,
        vm.newString('one'),
      ], kind: 'direct');
      expect(invoke(statfs, 'getAvailableBlocks()I', [value]), -2147483647);
      expect(invoke(statfs, 'getAvailableBlocksLong()J', [value]), 2147483649);
      expect(
        invoke(statfs, 'getAvailableBytes()J', [value]),
        4096 * 2147483649,
      );
      expect(count, 1);
      invoke(statfs, 'restat(Ljava/lang/String;)V', [
        value,
        vm.newString('two'),
      ]);
      expect(invoke(statfs, 'getAvailableBlocksLong()J', [value]), 2147483650);
      expect(
        () => invoke(statfs, 'restat(Ljava/lang/String;)V', [
          value,
          vm.newString('bad'),
        ]),
        throwsA(
          isA<DalvikThrown>().having(
            (e) => e.object.className,
            'type',
            'Ljava/lang/IllegalArgumentException;',
          ),
        ),
      );
      expect(invoke(statfs, 'getAvailableBlocksLong()J', [value]), 2147483650);
    },
  );
  test('missing host facts stay explicit instead of reporting free space or offline', () {
    registerAndroidContext(vm, environment: environment());
    expect(
      () => invoke(
        storage,
        'getExternalStorageState()Ljava/lang/String;',
        [],
        kind: 'static',
      ),
      throwsA(isA<MissingDalvikBridge>()),
    );
    expect(
      () => invoke(statfs, '<init>(Ljava/lang/String;)V', [
        vm.allocate(statfs),
        vm.newString(directory.path),
      ], kind: 'direct'),
      throwsA(isA<MissingDalvikBridge>()),
    );
    expect(
      () => invoke(manager, 'getActiveNetworkInfo()Landroid/net/NetworkInfo;', [
        DalvikObject(manager),
      ]),
      throwsA(isA<MissingDalvikBridge>()),
    );
  });
  test(
    'network objects reflect explicit host snapshots and transport facts',
    () {
      AndroidNetworkState? active = const AndroidNetworkState(
        connected: true,
        available: true,
        type: 1,
        subtype: 0,
        transports: {1},
        capabilities: {12, 16},
      );
      final env = environment(
        network: () => active,
        networkByType: (type) => type == active?.type ? active : null,
      );
      registerAndroidContext(vm, environment: env);
      final service = env.services['connectivity']!;
      final snapshot = invoke(manager, 'getActiveNetworkInfo()$info', [
        service,
      ]) as DalvikObject;
      expect(invoke(info, 'getType()I', [snapshot]), 1);
      expect(invoke(info, 'isConnected()Z', [snapshot]), 1);
      expect(invoke(manager, 'getNetworkInfo(I)$info', [service, 0]), null);
      final network = invoke(
        manager,
        'getActiveNetwork()Landroid/net/Network;',
        [service],
      );
      final capabilities = invoke(
        manager,
        'getNetworkCapabilities(Landroid/net/Network;)Landroid/net/NetworkCapabilities;',
        [service, network],
      );
      expect(
        invoke('Landroid/net/NetworkCapabilities;', 'hasTransport(I)Z', [
          capabilities,
          1,
        ]),
        1,
      );
      expect(
        invoke('Landroid/net/NetworkCapabilities;', 'hasCapability(I)Z', [
          capabilities,
          16,
        ]),
        1,
      );
      active = null;
      expect(invoke(manager, 'getActiveNetworkInfo()$info', [service]), null);
      expect(
        invoke(info, 'isConnected()Z', [snapshot]),
        1,
      ); // immutable prior snapshot
    },
  );
  test('Windows filesystem provider reads actual allocation counts', () {
    final host = WindowsFileSystem.open();
    final result = host.stats(directory.absolute.path);
    expect(result.blockSize, greaterThan(0));
    expect(result.blockCount, greaterThan(0));
    expect(result.availableBlocks, inInclusiveRange(0, result.blockCount));
    expect(
      result.freeBlocks,
      inInclusiveRange(result.availableBlocks, result.blockCount),
    );
    expect(
      () => host.stats('${directory.path}/missing'),
      throwsA(isA<FileSystemException>()),
    );
    host.dispose();
    expect(() => host.stats(directory.path), throwsStateError);
  }, skip: !Platform.isWindows);
}
