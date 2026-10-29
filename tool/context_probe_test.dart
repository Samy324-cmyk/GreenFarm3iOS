import 'dart:io';
import 'dart:convert';

import 'package:green_farm_port/engine/dalvik/android_context.dart';
import 'package:green_farm_port/engine/dalvik/android_handlers.dart';
import 'package:green_farm_port/engine/dalvik/java_nio.dart';
import 'package:green_farm_port/engine/dalvik/java_zip.dart';
import 'package:green_farm_port/engine/dalvik/java_security.dart';
import 'package:green_farm_port/engine/dalvik/java_reflection.dart';
import 'package:green_farm_port/engine/dalvik/native_utils.dart';
import 'package:green_farm_port/engine/dalvik/java_threads.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/android_graphics.dart';
import 'package:green_farm_port/engine/dalvik/android_platform.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_collections.dart';
import 'package:green_farm_port/engine/dalvik/java_files.dart';
import 'package:green_farm_port/engine/dalvik/java_io.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/generated/program.dart';
import 'package:green_farm_port/platform/host_clocks.dart';
import 'package:green_farm_port/platform/windows_filesystem.dart';

// Explicit integration probe. Kept outside test/ until all platform operations
// reached by the real original startup path have implementations.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('execute original class initialization in Flutter', () async {
    final graphics = AndroidGraphicsEnvironment();
    await graphics.loadFonts();
    final vm = _ContextProbeRuntime()
      ..instructionLimit = 2000000
      ..wallClockMillis = (() => DateTime.now().millisecondsSinceEpoch)
      ..randomSeedSource = (() => DateTime.now().microsecondsSinceEpoch)
      ..defaultLocaleLanguage = 'es';
    final clocks = HostClocks.open();
    addTearDown(clocks.dispose);
    vm.monotonicMillis = clocks.elapsedRealtimeMillis;
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final resources = <String, List<int>>{};
    for (final key in manifest.listAssets().where(
      (key) => key.startsWith('assets/original/'),
    )) {
      final data = await rootBundle.load(key);
      resources[key.substring('assets/original'.length)] = data.buffer
          .asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    vm.resourceLoader = (path) =>
        resources[path.startsWith('/') ? path : '/$path'];
    registerJavaCore(vm);
    registerJavaCollections(vm);
    registerJavaIo(vm);
    registerJavaSecurity(vm);
    registerJavaReflection(vm);
    registerJavaZip(vm);
    registerNativeUtils(
      vm,
      environment: NativeUtilsEnvironment(
        monotonicNanos: clocks.monotonicNanos,
        processCpuClockTicks: clocks.processCpuClockTicks,
      ),
    );
    final directory = Directory('.dart_tool/probe-data')
      ..createSync(recursive: true);
    final filesystem = WindowsFileSystem.open();
    addTearDown(filesystem.dispose);
    final external = Directory('.dart_tool/probe-external')
      ..createSync(recursive: true);
    registerJavaFiles(vm, workingDirectory: directory.absolute.path);
    registerAndroidGraphics(vm, environment: graphics);
    registerAndroidPlatform(
      vm,
      model: 'Flutter integration-test host',
      release: Platform.operatingSystemVersion,
      compatibilitySdk: 30,
    );
    registerJavaNio(vm);
    final scheduler = registerJavaThreads(vm);
    vm.monitorEnterHook = scheduler.monitorEnter;
    vm.monitorExitHook = scheduler.monitorExit;
    vm.currentThreadHook = () => scheduler.currentThread;
    final handlers = AndroidHandlerEnvironment(
      vm: vm,
      scheduler: scheduler,
      uptimeMillis: () => clocks.monotonicNanos() ~/ 1000000,
    );
    registerAndroidHandlers(vm, environment: handlers);
    addTearDown(handlers.dispose);
    final table = AndroidResourceTable.fromJson(
      jsonDecode(
        File('assets/platform/android_resources.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    final context = AndroidContextEnvironment(
      resources: table,
      display: const AndroidDisplayMetrics(
        width: 800,
        height: 480,
        density: 1,
        scaledDensity: 1,
        xdpi: 160,
        ydpi: 160,
        rotation: 0,
      ),
      filesDirectory: directory.absolute.path,
      cacheDirectory: Directory('.dart_tool/context-cache').absolute.path,
      language: 'es',
      hasPermanentMenuKey: false,
      sourceArchivePath: File('assets/provenance/original.apk').absolute.path,
      signingCertificates: [
        File('assets/platform/apk_signer_0.der').readAsBytesSync(),
      ],
      externalStorageDirectory: external.absolute.path,
      externalStorageState: () {
        if (!external.existsSync()) return 'unmounted';
        final access = File('${external.path}/.host-access-probe');
        try {
          access.writeAsBytesSync([1]);
          access.deleteSync();
          return 'mounted';
        } on FileSystemException {
          return 'mounted_ro';
        }
      },
      fileSystemStats: filesystem.stats,
      assetLoader: (path) => resources['/$path'],
      rawResourceLoader: (path) => path == 'res/raw/content.bin'
          ? File('assets/platform/content.bin').readAsBytesSync()
          : null,
      assetLister: (path) {
        final prefix = path.isEmpty ? '/' : '/$path/';
        return resources.keys
            .where((key) => key.startsWith(prefix))
            .map((key) => key.substring(prefix.length).split('/').first)
            .toSet()
            .toList()
          ..sort();
      },
    );
    context.postToUi = (callback) => callback();
    final windowRequests = <int>[];
    context.systemUiVisibilityChanged = (_, flags) => windowRequests.add(flags);
    context.windowChanged = (window) => windowRequests.add(window.flags);
    final boundSurfaces = <AndroidSurfaceState>[];
    context.bindSurface = boundSurfaces.add;
    final attachedViews = <DalvikObject>[];
    // Probe host records attachments; production supplies its actual Flutter view.
    context.setContentView = (_, view) => attachedViews.add(view);
    registerAndroidContext(vm, environment: context);
    registerOriginalSurfaceBinding(vm, environment: context);
    registerOriginalProgram(vm);
    final target =
        Platform.environment['PORT_PROBE_TARGET'] ??
        'Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/GloftGF2F;';
    try {
      vm.initialize(target);
      final mode = Platform.environment['CONTEXT_PROBE_ENTRY'] ?? 'clinit';
      if (mode == 'launcher') {
        const launcher = 'Lcom/gameloft/android/ANMP/GloftGF2F/Start;';
        await scheduler.runMain(() {
          final activity = vm.allocate(launcher);
          vm.call('$launcher-><init>()V', [activity], kind: 'direct');
          return vm.call('$launcher->onCreate(Landroid/os/Bundle;)V', [
            activity,
            null,
          ], kind: 'virtual');
        });
      } else if (mode != 'clinit') {
        const entry =
            'Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/GloftGF2F;';
        final game = vm.allocate(entry);
        vm.call('$entry-><init>()V', [game], kind: 'direct');
        if (mode == 'start') {
          vm.putStatic(
            'Ljavax/microedition/midlet/MIDlet;',
            'Ljavax/microedition/midlet/MIDlet;->e:Ljavax/microedition/midlet/MIDlet;',
            game,
          );
          vm.call('Lc/c/a/b/m;->a2(Landroid/content/Context;)V', [
            game,
          ], kind: 'static');
          await scheduler.runMain(
            () => vm.call('$entry->G()V', [game], kind: 'virtual'),
          );
        }
      }
      File('../dex-ir/context-integration-probe.txt').writeAsStringSync(
        'INITIALIZED $target\nInstructions: ${vm.executedInstructions}\n',
      );
    } catch (error, trace) {
      File('../dex-ir/context-integration-probe.txt').writeAsStringSync(
        '$error\nRecent PCs: ${vm.recent.join(', ')}\n${vm.lastFailureStack.join('\n')}\n$trace',
      );
      rethrow;
    }
  });
}

class _ContextProbeRuntime extends DalvikRuntime {
  final List<String> recent = [];
  @override
  void tick(String method, int pc) {
    recent.add('$method:$pc');
    if (recent.length > 16) recent.removeAt(0);
    super.tick(method, pc);
  }
}
