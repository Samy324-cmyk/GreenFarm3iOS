import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/compat/java_numbers.dart';
import 'package:green_farm_port/engine/dalvik/cooperative.dart';
import 'package:green_farm_port/engine/dalvik/java_audio.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_files.dart';
import 'package:green_farm_port/engine/dalvik/java_io.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/generated/c0058.dart';
import 'package:green_farm_port/generated/c0071.dart';
import 'package:green_farm_port/generated/c0073.dart';

const media = 'Landroid/media/MediaPlayer;';
const input = 'Ljava/io/FileInputStream;';
const audio = 'Lc/c/a/a/a/w/u;';
const manager = 'Landroid/media/AudioManager;';

class RecordingAudioHost implements JavaAudioHost {
  final List<(String, Map<String, Object?>)> calls = [];
  final Map<int, bool> playing = {};
  late Future<void> Function(String, Map<Object?, Object?>) event;
  bool failLoad = false;
  @override
  void setEventHandler(
    Future<void> Function(String, Map<Object?, Object?>) handler,
  ) => event = handler;
  @override
  Future<Object?> call(String method, Map<String, Object?> args) async {
    calls.add((method, args));
    final id = args['id'] as int?;
    switch (method) {
      case 'load':
        if (failLoad) {
          throw PlatformException(
            code: 'decode',
            message: 'Decoder rejected source',
          );
        }
        playing[id!] = false;
        return {'durationMs': 500};
      case 'play':
        playing[id!] = true;
        return null;
      case 'pause':
      case 'stop':
        playing[id!] = false;
        return null;
      case 'release':
        playing.remove(id);
        return null;
      case 'status':
        return {'playing': playing[id], 'positionMs': 123, 'durationMs': 500};
      case 'setLooping':
      case 'setVolume':
      case 'seek':
        return null;
      case 'requestFocus':
        return true;
      case 'systemStatus':
        return {'musicActive': true, 'outputVolume': 0.4};
      default:
        throw StateError('Unexpected host call $method');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DalvikRuntime vm;
  late RecordingAudioHost host;
  late JavaAudioEnvironment env;
  late Directory directory;
  final executor = DalvikExecutor();
  final opened = <DalvikObject>[];
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
    DalvikObject p,
    String method, [
    List<Object?> args = const [],
  ]) => vm.call('${p.className}->$method', [p, ...args], kind: 'virtual');
  Future<Object?> run(
    DalvikObject p,
    String method, [
    List<Object?> args = const [],
  ]) => executor.run(() => call(p, method, args));
  DalvikObject descriptor(String filename) {
    final stream = make(input, '(Ljava/lang/String;)V', [
      vm.newString(filename),
    ]);
    opened.add(stream);
    return call(stream, 'getFD()Ljava/io/FileDescriptor;') as DalvikObject;
  }

  Future<DalvikObject> prepared() async {
    final p = make(media);
    call(p, 'setDataSource(Ljava/io/FileDescriptor;)V', [
      descriptor('22.snddmp'),
    ]);
    await run(p, 'prepare()V');
    return p;
  }

  setUp(() {
    vm = DalvikRuntime()..wallClockMillis = () => 123456789;
    registerJavaCore(vm);
    registerJavaIo(vm);
    final root = Directory('.dart_tool/audio-bridge-tests')
      ..createSync(recursive: true);
    directory = root.createTempSync('case-');
    registerJavaFiles(vm, workingDirectory: directory.absolute.path);
    final pack = File('assets/original/800x480/8').readAsBytesSync();
    final view = ByteData.sublistView(pack);
    final start = view.getUint32(6 + 22 * 4, Endian.little);
    final end = view.getUint32(6 + 23 * 4, Endian.little);
    File('${directory.path}/22.snddmp')
        .writeAsBytesSync(pack.sublist(start + 1, end));
    host = RecordingAudioHost();
    env = JavaAudioEnvironment(
      manifest: jsonDecode(
        File('assets/audio/manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>,
      host: host,
      dispatch: executor.run,
    );
    registerJavaAudio(vm, environment: env);
    addTearDown(() async {
      await env.dispose();
      for (final stream in opened) {
        call(stream, 'close()V');
      }
      opened.clear();
      final target = directory.resolveSymbolicLinksSync();
      final parent = root.resolveSymbolicLinksSync();
      if (!target.startsWith('$parent${Platform.pathSeparator}')) {
        throw StateError('Cleanup escaped root');
      }
      Directory(target).deleteSync(recursive: true);
    });
  });

  test('original DEX u.F prepares and plays a real pack entry across native pauses', () async {
    registerClass58(vm);
    registerClass71(vm);
    registerClass73(vm);
    // Fixture supplies the already-initialized game's channel arrays. The
    // actual original F -> G -> m -> MediaPlayer call graph executes unchanged.
    vm.classes[audio]!.initialization = 2;
    vm.putStatic(audio, '$audio->A:Z', 1);
    vm.putStatic(
      audio,
      '$audio->C:[Landroid/media/MediaPlayer;',
      vm.array('[Landroid/media/MediaPlayer;', 1),
    );
    vm.putStatic(audio, '$audio->B:[Z', vm.array('[Z', 82)..values[22] = 1);
    for (final name in ['G', 'E', 'F', 'H', 'I', 'V']) {
      vm.putStatic(audio, '$audio->$name:[I', vm.array('[I', 1));
    }
    vm.putStatic(audio, '$audio->D:[J', vm.array('[J', 1));
    const context = 'Landroid/content/Context;';
    vm.registerExternalClass(context);
    vm.putStatic(audio, '$audio->h0:$context', DalvikObject(context));
    vm.registerNative(
      '$context->openFileInput(Ljava/lang/String;)Ljava/io/FileInputStream;',
      (_, a) {
        final stream = make(input, '(Ljava/lang/String;)V', [a[1]]);
        opened.add(stream);
        return stream;
      },
    );
    const gl = 'Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/GLLib;';
    vm.registerExternalClass(gl);
    vm.classes[gl]!.staticFields['$gl->W:Z'] = 0;
    await executor.run(
      () => vm.call('$audio->F(IIIII)V', [0, 22, 4, 0, 37], kind: 'static'),
    );
    expect(host.calls.map((c) => c.$1), [
      'load',
      'setLooping',
      'setVolume',
      'play',
    ]);
    expect(host.calls.first.$2['asset'], 'assets/audio/audio_022.wav');
    expect(host.calls.last.$2['looping'], true);
    expect(
      host.calls.last.$2['left'],
      JavaNumbers.floatFromBits(JavaNumbers.floatBits(0.37)),
    );
    expect((vm.getStatic(audio, '$audio->G:[I') as DalvikArray).values, [2]);
    expect((vm.getStatic(audio, '$audio->H:[I') as DalvikArray).values, [37]);
    expect((vm.getStatic(audio, '$audio->D:[J') as DalvikArray).values, [
      123456789,
    ]);
    expect(vm.executedInstructions, greaterThan(100));
  });

  test('descriptor lookup preserves cursor, unknown bytes fail, native load failure is IOException', () async {
    final fd = descriptor('22.snddmp');
    final stream = opened.last;
    call(stream, 'read()I');
    final available = call(stream, 'available()I');
    final p = make(media);
    call(p, 'setDataSource(Ljava/io/FileDescriptor;)V', [fd]);
    expect(call(stream, 'available()I'), available);
    host.failLoad = true;
    await expectLater(
      run(p, 'prepare()V'),
      throwsA(
        isA<DalvikThrown>().having(
          (e) => e.object.className,
          'type',
          'Ljava/io/IOException;',
        ),
      ),
    );
    host.failLoad = false;
    await run(p, 'prepare()V');
    File('${directory.path}/invalid').writeAsBytesSync([1, 2, 3]);
    expect(
      () => call(make(media), 'setDataSource(Ljava/io/FileDescriptor;)V', [
        descriptor('invalid'),
      ]),
      throwsA(isA<MissingDalvikBridge>()),
    );
  });

  test('completion is dispatched through original listener once and ignores stopped/released voices', () async {
    final p = await prepared();
    var completions = 0;
    const callback = 'Ltest/Completion;';
    vm.registerExternalClass(
      callback,
      interfaces: ['Landroid/media/MediaPlayer\$OnCompletionListener;'],
    );
    vm.registerNative('$callback->onCompletion(Landroid/media/MediaPlayer;)V', (
      _,
      a,
    ) {
      expect(a[1], same(p));
      completions++;
      return null;
    });
    call(
      p,
      'setOnCompletionListener(Landroid/media/MediaPlayer\$OnCompletionListener;)V',
      [DalvikObject(callback)],
    );
    await run(p, 'start()V');
    final id = call(p, 'getAudioSessionId()I');
    await host.event('completed', {'id': id});
    await host.event('completed', {'id': id});
    expect(completions, 1);
    await run(p, 'start()V');
    await run(p, 'stop()V');
    await host.event('completed', {'id': id});
    expect(completions, 1);
    await run(p, 'prepare()V');
    await run(p, 'setLooping(Z)V', [1]);
    await run(p, 'start()V');
    await host.event('completed', {'id': id});
    expect(completions, 1);
    await run(p, 'release()V');
    await host.event('completed', {'id': id});
    expect(completions, 1);
  });

  test(
    'queries reflect host state and seek/volume preserve parameters',
    () async {
      final p = await prepared();
      await run(p, 'start()V');
      expect(await run(p, 'isPlaying()Z'), 1);
      final id = call(p, 'getAudioSessionId()I') as int;
      host.playing[id] = false;
      expect(await run(p, 'isPlaying()Z'), 0);
      expect(await run(p, 'getCurrentPosition()I'), 123);
      expect(await run(p, 'getDuration()I'), 500);
      await run(p, 'seekTo(I)V', [900]);
      expect(host.calls.last.$2['positionMs'], 500);
      await run(p, 'setVolume(FF)V', [
        JavaNumbers.floatBits(0.25),
        JavaNumbers.floatBits(0.25),
      ]);
      expect(host.calls.last.$2['left'], 0.25);
      expect(
        () => call(p, 'setVolume(FF)V', [
          JavaNumbers.floatBits(0.2),
          JavaNumbers.floatBits(0.3),
        ]),
        throwsA(isA<MissingDalvikBridge>()),
      );
    },
  );

  test(
    'state machine rejects starting idle/stopped/released players',
    () async {
      final idle = make(media);
      expect(await run(idle, 'isPlaying()Z'), 0);
      await expectLater(run(idle, 'start()V'), throwsA(isA<DalvikThrown>()));
      final p = await prepared();
      await run(p, 'stop()V');
      await expectLater(run(p, 'start()V'), throwsA(isA<DalvikThrown>()));
      await run(p, 'prepare()V');
      await run(p, 'start()V');
      await run(p, 'pause()V');
      expect(await run(p, 'isPlaying()Z'), 0);
      await run(p, 'release()V');
      await run(p, 'release()V');
      await expectLater(run(p, 'isPlaying()Z'), throwsA(isA<DalvikThrown>()));
    },
  );

  test('system music/focus use native results; unsupported system operations fail explicitly', () async {
    final m = env.audioManager;
    expect(await run(m, 'isMusicActive()Z'), 1);
    expect(await run(m, 'getStreamVolume(I)I', [3]), 6);
    final changes = <int>[];
    const callback = 'Ltest/Focus;';
    vm.registerExternalClass(
      callback,
      interfaces: ['Landroid/media/AudioManager\$OnAudioFocusChangeListener;'],
    );
    vm.registerNative('$callback->onAudioFocusChange(I)V', (_, a) {
      changes.add(a[1] as int);
      return null;
    });
    expect(
      await run(
        m,
        'requestAudioFocus(Landroid/media/AudioManager\$OnAudioFocusChangeListener;II)I',
        [DalvikObject(callback), 3, 1],
      ),
      1,
    );
    await host.event('focusChanged', {'change': -2});
    await host.event('focusChanged', {'change': 1});
    expect(changes, [-2, 1]);
    expect(
      () => call(m, 'getRingerMode()I'),
      throwsA(isA<MissingDalvikBridge>()),
    );
  });

  test(
    'unused original SoundPool can hold its listener; playback is never faked',
    () {
      final pool = make('Landroid/media/SoundPool;', '(III)V', [4, 3, 100]);
      call(
        pool,
        'setOnLoadCompleteListener(Landroid/media/SoundPool\$OnLoadCompleteListener;)V',
        [null],
      );
      expect(host.calls, isEmpty);
      expect(
        () => call(pool, 'load(Ljava/lang/String;I)I', [
          vm.newString('sound'),
          1,
        ]),
        throwsA(isA<MissingDalvikBridge>()),
      );
      call(pool, 'release()V');
    },
  );
}
