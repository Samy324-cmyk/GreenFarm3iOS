import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/android_context.dart';
import 'package:green_farm_port/engine/dalvik/android_insets.dart';
import 'package:green_farm_port/engine/dalvik/ios_calendar.dart';
import 'package:green_farm_port/engine/dalvik/java_audio.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/game/android_view_layout.dart';
import 'package:green_farm_port/game/original_assets.dart';
import 'package:green_farm_port/game/original_session.dart';
import 'package:green_farm_port/platform/host_clocks.dart';
import 'package:green_farm_port/platform/host_filesystem.dart';

/// Explicit production-entry integration probe, not a passing demo fixture.
/// Host audio is deliberately unavailable until a real Windows backend exists.
class _UnavailableWindowsAudio implements JavaAudioHost {
  Future<void> Function(String, Map<Object?, Object?>)? eventHandler;
  @override
  Future<Object?> call(String method, Map<String, Object?> arguments) async =>
      throw MissingDalvikBridge('Windows probe audio host: $method');
  @override
  void setEventHandler(
    Future<void> Function(String, Map<Object?, Object?>) handler,
  ) {
    eventHandler = handler;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('execute real OriginalGameSession launcher and Activity navigation', () async {
    final assets = await OriginalGameAssets.load();
    final clocks = HostClocks.open(), filesystem = HostFileSystem.open();
    final directory = Directory('.dart_tool/session-probe')
      ..createSync(recursive: true);
    final external = Directory('${directory.path}/external')
      ..createSync(recursive: true);
    final context = AndroidContextEnvironment(
      resources: assets.resourceTable,
      // Explicit integration-fixture viewport, independent of device claims.
      display: const AndroidDisplayMetrics(
        width: 800,
        height: 480,
        density: 1,
        scaledDensity: 1,
        xdpi: 160,
        ydpi: 160,
        rotation: 0,
      ),
      filesDirectory: Directory('${directory.path}/files').absolute.path,
      cacheDirectory: Directory('${directory.path}/cache').absolute.path,
      language: 'es',
      hasPermanentMenuKey: false,
      sourceArchivePath: File('assets/provenance/original.apk').absolute.path,
      signingCertificates: [
        File('assets/platform/apk_signer_0.der').readAsBytesSync(),
      ],
      assetLoader: assets.resource,
      assetLister: assets.listAssets,
      rawResourceLoader: assets.rawResource,
      externalStorageDirectory: external.absolute.path,
      externalStorageState: () {
        if (!external.existsSync()) return 'unmounted';
        final check = File('${external.path}/.access-probe');
        try {
          check.writeAsBytesSync([1]);
          check.deleteSync();
          return 'mounted';
        } on FileSystemException {
          return 'mounted_ro';
        }
      },
      fileSystemStats: filesystem.stats,
    );
    final requests = <String>[], failures = <(Object, StackTrace)>[];
    context.windowChanged = (window) => requests.add(
      'window flags=${window.flags} ${window.width}x${window.height}',
    );
    context.systemUiVisibilityChanged = (_, flags) =>
        requests.add('chrome=$flags');
    OriginalGameSession? session;
    try {
      session = await OriginalGameSession.load(
        context: context,
        assets: assets,
        clocks: clocks,
        model: 'Flutter Windows integration fixture',
        release: Platform.operatingSystemVersion,
        calendar: IosCalendarPlatform(
          timeZoneIdentifier: 'America/Mexico_City',
          firstDayOfWeek: 1,
          minimalDaysInFirstWeek: 1,
          clock: () => DateTime.now().millisecondsSinceEpoch,
        ),
        insets: const AndroidWindowInsetsState(
          left: 0,
          top: 0,
          right: 0,
          bottom: 0,
        ),
        onFrameRequested: () => requests.add('frame requested'),
        onViewAttached: (view) {
          requests.add('attached ${view.object.className}');
          AndroidViewLayout(session!.vm, context).layout(view, 800, 480);
        },
        onFailure: (error, stack) => failures.add((error, stack)),
        onExternalIntent: (_, intent, _) async => throw MissingDalvikBridge(
          'Windows probe external Activity navigation',
        ),
        onFinished: () => requests.add('finished'),
        audioHost: _UnavailableWindowsAudio(),
      );
      session.vm.instructionLimit = 20000000;
      await session.start();
      await session.afterLayout();
      if (failures.isNotEmpty)
        Error.throwWithStackTrace(failures.first.$1, failures.first.$2);
      final picture = await session.frame();
      picture?.dispose();
      File('../dex-ir/session-integration-probe.txt').writeAsStringSync(
        'Started original session; instructions=${session.vm.executedInstructions}; frame=${picture != null}\n${requests.join('\n')}',
      );
    } catch (error, stack) {
      File('../dex-ir/session-integration-probe.txt').writeAsStringSync(
        '$error\n${requests.join('\n')}\n${session?.vm.lastFailureStack.join('\n')}\n$stack',
      );
      rethrow;
    } finally {
      await session?.dispose();
      clocks.dispose();
      filesystem.dispose();
    }
  });
}
