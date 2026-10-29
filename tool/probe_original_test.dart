import 'dart:io';

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

// Explicit integration probe. Kept outside test/ until all platform operations
// reached by the real original startup path have implementations.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('execute original class initialization in Flutter', () async {
    final graphics = AndroidGraphicsEnvironment();
    await graphics.loadFonts();
    final vm = DalvikRuntime()
      ..instructionLimit = 2000000
      ..wallClockMillis = (() => DateTime.now().millisecondsSinceEpoch)
      ..randomSeedSource = (() => DateTime.now().microsecondsSinceEpoch)
      ..defaultLocaleLanguage = 'es';
    final watch = Stopwatch()..start();
    vm.monotonicMillis = () => watch.elapsedMilliseconds;
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
    final directory = Directory('.dart_tool/probe-data')
      ..createSync(recursive: true);
    registerJavaFiles(vm, workingDirectory: directory.absolute.path);
    registerAndroidGraphics(vm, environment: graphics);
    registerAndroidPlatform(vm);
    registerOriginalProgram(vm);
    final target =
        Platform.environment['PORT_PROBE_TARGET'] ??
        'Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/cGame;';
    try {
      vm.initialize(target);
      File('../dex-ir/last-integration-probe.txt').writeAsStringSync(
        'INITIALIZED $target\nInstructions: ${vm.executedInstructions}\n',
      );
    } catch (error, trace) {
      File(
        '../dex-ir/last-integration-probe.txt',
      ).writeAsStringSync('$error\n${vm.lastFailureStack.join('\n')}\n$trace');
      rethrow;
    }
  });
}
