import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import '../engine/dalvik/android_context.dart';
import '../engine/dalvik/android_graphics.dart';
import '../engine/dalvik/android_handlers.dart';
import '../engine/dalvik/android_input.dart';
import '../engine/dalvik/android_insets.dart';
import '../engine/dalvik/android_intents.dart';
import '../engine/dalvik/android_platform.dart';
import '../engine/dalvik/java_audio.dart';
import '../engine/dalvik/java_collections.dart';
import '../engine/dalvik/java_core.dart';
import '../engine/dalvik/java_files.dart';
import '../engine/dalvik/java_io.dart';
import '../engine/dalvik/java_json.dart';
import '../engine/dalvik/java_nio.dart';
import '../engine/dalvik/java_reflection.dart';
import '../engine/dalvik/java_security.dart';
import '../engine/dalvik/java_threads.dart';
import '../engine/dalvik/java_zip.dart';
import '../engine/dalvik/native_utils.dart';
import '../engine/dalvik/runtime.dart';
import '../engine/render/legacy_renderer.dart';
import '../generated/program.dart';
import '../platform/host_clocks.dart';
import 'original_assets.dart';

const _activity = 'Landroid/app/Activity;';

class _ActivityEntry {
  _ActivityEntry(this.object, this.caller, this.requestCode);
  final DalvikObject object;
  final DalvikObject? caller;
  final int? requestCode;
}

/// Runs the recovered launcher and its actual Activity handoff. All game
/// constructors, configuration, resource selection and lifecycle remain in
/// generated original methods; this class supplies the Flutter host boundary.
class OriginalGameSession {
  OriginalGameSession._({
    required this.vm,
    required this.context,
    required this.scheduler,
    required this.renderer,
    required this.audio,
    required this.handlers,
    required AndroidWindowInsetsState insets,
    required this.onFrameRequested,
    required this.onViewAttached,
    required this.onFailure,
    required this.onExternalIntent,
    required this.onFinished,
  }) : _insets = insets;
  final DalvikRuntime vm;
  final AndroidContextEnvironment context;
  final JavaThreadScheduler scheduler;
  final LegacyRenderer renderer;
  final JavaAudioEnvironment audio;
  final AndroidHandlerEnvironment handlers;
  AndroidWindowInsetsState _insets;
  final void Function() onFrameRequested;
  final void Function(AndroidViewState) onViewAttached;
  final void Function(Object, StackTrace) onFailure;
  final Future<void> Function(
    DalvikObject caller,
    DalvikObject intent,
    int? requestCode,
  )
  onExternalIntent;
  final void Function() onFinished;
  final List<_ActivityEntry> _activities = [];
  final List<AndroidSurfaceState> _surfaces = [];
  final Set<AndroidSurfaceState> _createdSurfaces = {};
  final Queue<void Function()> _afterLayout = Queue();
  Future<void> _navigation = Future.value();
  bool _foreground = true, _drawing = false, _closed = false;
  int _seenThreadFailures = 0;

  DalvikObject? get activeActivity =>
      _activities.isEmpty ? null : _activities.last.object;
  AndroidViewState? get contentView {
    final current = activeActivity;
    final object = current == null
        ? null
        : context.activities[current]?.contentView;
    return object == null ? null : context.views[object];
  }

  static Future<OriginalGameSession> load({
    required AndroidContextEnvironment context,
    required OriginalGameAssets assets,
    required HostClocks clocks,
    required String model,
    required String release,
    required JavaCalendarPlatform calendar,
    required AndroidWindowInsetsState insets,
    required void Function() onFrameRequested,
    required void Function(AndroidViewState) onViewAttached,
    required void Function(Object, StackTrace) onFailure,
    required Future<void> Function(
      DalvikObject caller,
      DalvikObject intent,
      int? requestCode,
    )
    onExternalIntent,
    required void Function() onFinished,
    JavaAudioHost? audioHost,
  }) async {
    final random = Random.secure();
    final vm = DalvikRuntime()
      ..wallClockMillis = (() => DateTime.now().millisecondsSinceEpoch)
      ..monotonicMillis = clocks.elapsedRealtimeMillis
      ..randomSeedSource = (() =>
          (random.nextInt(1 << 32) << 32) | random.nextInt(1 << 32))
      ..defaultLocaleLanguage = context.language
      ..resourceLoader = assets.resource;
    registerJavaCore(vm);
    registerJavaCollections(vm, calendarPlatform: calendar);
    registerJavaIo(vm);
    registerJavaFiles(vm, workingDirectory: context.filesDirectory);
    registerJavaZip(vm, workingDirectory: context.filesDirectory);
    registerJavaJson(vm);
    registerJavaNio(vm);
    registerJavaSecurity(vm);
    registerJavaReflection(vm);
    registerNativeUtils(
      vm,
      environment: NativeUtilsEnvironment(
        monotonicNanos: clocks.monotonicNanos,
        processCpuClockTicks: clocks.processCpuClockTicks,
      ),
    );
    registerAndroidPlatform(
      vm,
      model: model,
      release: release,
      compatibilitySdk: 30,
    );
    final graphics = AndroidGraphicsEnvironment();
    await graphics.loadFonts();
    registerAndroidGraphics(vm, environment: graphics);
    registerAndroidInput(vm);
    registerAndroidInsets(vm);
    final scheduler = registerJavaThreads(vm);
    vm.monitorEnterHook = scheduler.monitorEnter;
    vm.monitorExitHook = scheduler.monitorExit;
    vm.currentThreadHook = () => scheduler.currentThread;
    final handlers = AndroidHandlerEnvironment(
      vm: vm,
      scheduler: scheduler,
      uptimeMillis: () => clocks.monotonicNanos() ~/ 1000000,
      onError: onFailure,
    );
    registerAndroidHandlers(vm, environment: handlers);
    final audio = await JavaAudioEnvironment.load(
      dispatch: scheduler.runMain,
      host: audioHost,
    );
    registerJavaAudio(vm, environment: audio);
    context.services['audio'] = audio.audioManager;
    registerAndroidContext(vm, environment: context);
    registerOriginalSurfaceBinding(vm, environment: context);
    final renderer = LegacyRenderer();
    await renderer.load();
    registerLegacyRenderer(vm, renderer: renderer);
    registerOriginalProgram(vm);
    final session = OriginalGameSession._(
      vm: vm,
      context: context,
      scheduler: scheduler,
      renderer: renderer,
      audio: audio,
      handlers: handlers,
      insets: insets,
      onFrameRequested: onFrameRequested,
      onViewAttached: onViewAttached,
      onFailure: onFailure,
      onExternalIntent: onExternalIntent,
      onFinished: onFinished,
    );
    session._bind();
    return session;
  }

  void _bind() {
    context.startActivity = (caller, intent, requestCode) =>
        _queueNavigation(() => _launch(intent, caller, requestCode));
    context.finishActivity = (activity) =>
        _queueNavigation(() => _finish(activity));
    context.bindSurface = (surface) {
      _surfaces.add(surface);
      onFrameRequested();
    };
    context.requestFrame = (_) => onFrameRequested();
    context.setContentView = (_, view) {
      final state = context.views[view];
      if (state == null) {
        throw MissingDalvikBridge('Attached view has no native state');
      }
      onViewAttached(state);
      onFrameRequested();
    };
    final mainThread = scheduler.currentThread;
    context.postToUi = (callback) {
      if (identical(scheduler.currentThread, mainThread)) {
        callback();
      } else {
        unawaited(
          scheduler
              .runMain(() {
                callback();
                return null;
              })
              .catchError((Object error, StackTrace stack) {
                onFailure(error, stack);
                return null;
              }),
        );
      }
    };
    context.postViewCallback = (_, callback) {
      _afterLayout.add(callback);
      onFrameRequested();
    };
    context.insetsListenerChanged = _scheduleInsets;
  }

  void _scheduleInsets(AndroidViewState view) {
    _afterLayout.add(() {
      final listener = view.insetsListener;
      if (listener != null) {
        vm.call(
          'Landroid/view/View\$OnApplyWindowInsetsListener;->onApplyWindowInsets(Landroid/view/View;Landroid/view/WindowInsets;)Landroid/view/WindowInsets;',
          [listener, view.object, _insets.asObject()],
          kind: 'interface',
        );
      }
    });
    onFrameRequested();
  }

  void updateInsets(AndroidWindowInsetsState insets) {
    _insets = insets;
    for (final view in context.views.values) {
      if (view.insetsListener != null) _scheduleInsets(view);
    }
  }

  Future<void> start() => _launch(
    javaAndroidIntent(
      action: 'android.intent.action.MAIN',
      packageName: context.resources.packageName,
      className: 'com.gameloft.android.ANMP.GloftGF2F.Start',
    ),
    null,
    null,
  );

  void _queueNavigation(Future<void> Function() action) {
    _navigation = _navigation
        .then((_) async {
          if (!_closed) await action();
        })
        .catchError((Object error, StackTrace stack) {
          onFailure(error, stack);
        });
  }

  Future<Object?> _call(
    DalvikObject receiver,
    String member, [
    List<Object?> args = const [],
  ]) => scheduler.runMain(
    () => vm.call('$_activity->$member', [receiver, ...args], kind: 'virtual'),
  );

  Future<void> _launch(
    DalvikObject intent,
    DalvikObject? caller,
    int? requestCode,
  ) async {
    final value = androidIntent(vm, intent);
    final name = value.className;
    if (name == null) {
      if (caller == null) {
        throw StateError('Initial launch must name its Activity');
      }
      await onExternalIntent(caller, intent, requestCode);
      return;
    }
    final fullName = name.startsWith('.')
        ? '${value.componentPackageName}$name'
        : name;
    final descriptor = 'L${fullName.replaceAll('.', '/')};';
    if (!vm.classes.containsKey(descriptor)) {
      throw MissingDalvikBridge('Activity $descriptor');
    }
    final previous = activeActivity;
    if (previous != null &&
        context.activities[previous]!.lifecycle == 'onResume') {
      await _call(previous, 'onPause()V');
    }
    final activity =
        await scheduler.runMain(() => vm.allocate(descriptor)) as DalvikObject;
    await scheduler.runMain(
      () => vm.call('$descriptor-><init>()V', [activity], kind: 'direct'),
    );
    final state = context.activities[activity];
    if (state == null) {
      throw StateError('Activity constructor did not initialize native state');
    }
    state.intent = intent;
    state.intentAssigned = true;
    state.callingPackage = caller == null || requestCode == null
        ? null
        : context.resources.packageName;
    _activities.add(_ActivityEntry(activity, caller, requestCode));
    await _call(activity, 'onCreate(Landroid/os/Bundle;)V', [null]);
    if (!state.finishing) {
      await _call(activity, 'onStart()V');
      if (_foreground) await _call(activity, 'onResume()V');
    }
    if (previous != null && !context.activities[previous]!.destroyed) {
      await _call(previous, 'onStop()V');
    }
    onFrameRequested();
  }

  Future<void> _finish(DalvikObject activity) async {
    final index = _activities.indexWhere(
      (entry) => identical(entry.object, activity),
    );
    if (index < 0) return;
    final entry = _activities[index], state = context.activities[activity]!;
    final wasTop = identical(activeActivity, activity);
    if (state.lifecycle == 'onResume') await _call(activity, 'onPause()V');
    if (state.lifecycle != 'onStop' && state.lifecycle != 'onDestroy') {
      await _call(activity, 'onStop()V');
    }
    if (!state.destroyed) await _call(activity, 'onDestroy()V');
    _activities.removeAt(index);
    if (entry.caller != null &&
        entry.requestCode != null &&
        !context.activities[entry.caller]!.destroyed) {
      await _call(
        entry.caller!,
        'onActivityResult(IILandroid/content/Intent;)V',
        [entry.requestCode!, state.resultCode, state.resultData],
      );
    }
    final current = activeActivity;
    if (wasTop && current != null) {
      await _call(current, 'onRestart()V');
      await _call(current, 'onStart()V');
      if (_foreground) await _call(current, 'onResume()V');
      final view = contentView;
      if (view != null) onViewAttached(view);
    }
    if (_activities.isEmpty) onFinished();
  }

  /// Called by Flutter after the attached Android view tree has been laid out.
  Future<void> afterLayout() async {
    final pending = List<void Function()>.from(_afterLayout);
    _afterLayout.clear();
    for (final callback in pending) {
      await scheduler.runMain(() {
        callback();
        return null;
      });
    }
    await _navigation;
  }

  Future<ui.Picture?> frame() async {
    if (_closed || !_foreground || _drawing) return null;
    _drawing = true;
    try {
      while (_seenThreadFailures < scheduler.failures.length) {
        final failure = scheduler.failures[_seenThreadFailures++];
        if (failure.error is! DalvikThrown) {
          Error.throwWithStackTrace(failure.error, failure.stackTrace);
        }
      }
      final current = activeActivity;
      final visible = _surfaces
          .where(
            (s) =>
                identical(s.context, current) &&
                !s.paused &&
                s.width > 0 &&
                s.height > 0,
          )
          .toList();
      if (visible.isEmpty) return null;
      if (visible.length != 1) {
        throw MissingDalvikBridge(
          'Composition of multiple simultaneous game surfaces',
        );
      }
      final surface = visible.single;
      if (_createdSurfaces.add(surface)) {
        await scheduler.runMain(() {
          surface.surfaceCreated(vm, renderer.glContext, renderer.eglConfig);
          return null;
        });
        await scheduler.runMain(() {
          surface.surfaceChanged(
            vm,
            renderer.glContext,
            surface.width,
            surface.height,
          );
          return null;
        });
      }
      renderer.beginFrame(surface.width, surface.height);
      await scheduler.runMain(() {
        surface.drawFrame(vm, renderer.glContext);
        return null;
      });
      return await renderer.renderFrame();
    } finally {
      _drawing = false;
    }
  }

  Future<void> touch(AndroidMotionState event) async {
    if (_closed || !_foreground) return;
    final current = activeActivity;
    final visible = _surfaces
        .where((s) => identical(s.context, current) && !s.paused)
        .toList();
    if (visible.isEmpty) return;
    await scheduler.runMain(
      () => vm.call(
        'Landroid/view/View;->onTouchEvent(Landroid/view/MotionEvent;)Z',
        [visible.last.object, event.asObject()],
        kind: 'virtual',
      ),
    );
  }

  Future<void> setForeground(bool foreground) async {
    if (_foreground == foreground || _closed) return;
    _foreground = foreground;
    final current = activeActivity;
    if (current == null) return;
    if (foreground) {
      await _call(current, 'onRestart()V');
      await _call(current, 'onStart()V');
      await _call(current, 'onResume()V');
      onFrameRequested();
    } else {
      await _call(current, 'onPause()V');
      await _call(current, 'onStop()V');
    }
  }

  Future<void> dispose() async {
    _closed = true;
    handlers.dispose();
    await audio.dispose();
    renderer.dispose();
    _afterLayout.clear();
  }
}
