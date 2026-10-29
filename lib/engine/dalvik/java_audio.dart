import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'java_files.dart';
import 'numbers.dart';
import 'runtime.dart';

const _media = 'Landroid/media/MediaPlayer;';
const _pool = 'Landroid/media/SoundPool;';
const _manager = 'Landroid/media/AudioManager;';

abstract class JavaAudioHost {
  Future<Object?> call(String method, Map<String, Object?> arguments);
  void setEventHandler(
    Future<void> Function(String, Map<Object?, Object?>) handler,
  );
}

class MethodChannelAudioHost implements JavaAudioHost {
  MethodChannelAudioHost({
    this.channel = const MethodChannel('green_farm/audio'),
  });
  final MethodChannel channel;
  @override
  Future<Object?> call(String method, Map<String, Object?> arguments) =>
      channel.invokeMethod<Object?>(method, arguments);
  @override
  void setEventHandler(
    Future<void> Function(String, Map<Object?, Object?>) handler,
  ) {
    channel.setMethodCallHandler(
      (call) => handler(
        call.method,
        Map<Object?, Object?>.from(call.arguments as Map),
      ),
    );
  }
}

class JavaAudioEnvironment {
  JavaAudioEnvironment({
    required Map<String, dynamic> manifest,
    required this.dispatch,
    JavaAudioHost? host,
  }) : host = host ?? MethodChannelAudioHost() {
    if (manifest['schemaVersion'] != 1) {
      throw FormatException('Unknown audio manifest');
    }
    for (final row in manifest['tracks'] as List) {
      final key = row['sourceSha256'] as String;
      final asset = row['asset'] as String;
      if (!asset.startsWith('assets/audio/') || asset.contains('..')) {
        throw FormatException('Audio asset outside asset directory');
      }
      if (assets.containsKey(key) && assets[key] != asset) {
        // Identical original effects may occupy several pack slots. Their
        // content-identical conversion is interchangeable, verified at build.
        continue;
      }
      assets[key] = asset;
    }
  }
  static Future<JavaAudioEnvironment> load({
    required Future<Object?> Function(Object? Function()) dispatch,
    JavaAudioHost? host,
    AssetBundle? bundle,
  }) async => JavaAudioEnvironment(
    manifest: jsonDecode(
      await (bundle ?? rootBundle).loadString('assets/audio/manifest.json'),
    ) as Map<String, dynamic>,
    dispatch: dispatch,
    host: host,
  );
  final JavaAudioHost host;
  final Future<Object?> Function(Object? Function()) dispatch;
  final Map<String, String> assets = {};
  final DalvikObject audioManager = DalvikObject(_manager);
  final Map<int, _Player> _players = {};
  int _nextId = 1;
  Object? _focusListener;
  late DalvikRuntime _vm;
  Future<void> handleEvent(
    String event,
    Map<Object?, Object?> arguments,
  ) async {
    if (event == 'focusChanged') {
      if (!_vm.isNull(_focusListener)) {
        await dispatch(
          () => _vm.call(
            'Landroid/media/AudioManager\$OnAudioFocusChangeListener;->onAudioFocusChange(I)V',
            [_focusListener, arguments['change'] as int],
            kind: 'interface',
          ),
        );
      }
      return;
    }
    final player = _players[arguments['id']];
    if (player == null || player.state == _State.end) return;
    if (event == 'completed') {
      // Late callbacks from a stopped/restarted/released voice are stale.
      if (player.state != _State.started || player.looping) return;
      player.state = _State.completed;
      if (!_vm.isNull(player.completion)) {
        await dispatch(
          () => _vm.call(
            'Landroid/media/MediaPlayer\$OnCompletionListener;->onCompletion(Landroid/media/MediaPlayer;)V',
            [player.completion, player.object],
            kind: 'interface',
          ),
        );
      }
    } else if (event == 'error') {
      player.state = _State.error;
      throw StateError('Native audio ${player.id}: ${arguments['message']}');
    } else {
      throw MissingDalvikBridge('Audio callback $event');
    }
  }

  Future<void> dispose() async {
    for (final player in _players.values.toList()) {
      if (player.loaded) await host.call('release', {'id': player.id});
      player.state = _State.end;
    }
    _players.clear();
  }
}

enum _State {
  idle,
  initialized,
  prepared,
  started,
  paused,
  stopped,
  completed,
  error,
  end,
}

class _Player {
  _Player(this.object, this.id);
  final DalvikObject object;
  final int id;
  _State state = _State.idle;
  String? asset;
  bool looping = false, loaded = false;
  double left = 1, right = 1;
  int duration = 0;
  Object? completion;
}

class _SoundPool {
  _SoundPool(this.maxStreams, this.streamType, this.quality);
  final int maxStreams, streamType, quality;
  Object? listener;
  bool released = false;
}

void registerJavaAudio(
  DalvikRuntime vm, {
  required JavaAudioEnvironment environment,
}) {
  final env = environment;
  env._vm = vm;
  env.host.setEventHandler(env.handleEvent);
  for (final type in [
    _media,
    _pool,
    _manager,
    'Landroid/media/MediaPlayer\$OnCompletionListener;',
    'Landroid/media/SoundPool\$OnLoadCompleteListener;',
    'Landroid/media/AudioManager\$OnAudioFocusChangeListener;',
  ]) {
    vm.registerExternalClass(type);
  }
  _Player player(Object? value) {
    final state = vm.object(value).nativeValue;
    if (state is! _Player || state.state == _State.end) {
      vm.throwJava(
        'Ljava/lang/IllegalStateException;',
        'MediaPlayer is released',
      );
    }
    return state;
  }

  void require(_Player p, Set<_State> allowed) {
    if (!allowed.contains(p.state)) {
      vm.throwJava(
        'Ljava/lang/IllegalStateException;',
        'MediaPlayer state ${p.state.name}',
      );
    }
  }

  Future<Object?> invoke(
    String method,
    Map<String, Object?> args, {
    bool preparing = false,
  }) async {
    try {
      return await env.host.call(method, args);
    } on PlatformException catch (error) {
      if (error.code == 'unsupported') {
        throw MissingDalvikBridge(error.message ?? method);
      }
      vm.throwJava(
        preparing
            ? 'Ljava/io/IOException;'
            : 'Ljava/lang/IllegalStateException;',
        error.message,
      );
    } on MissingPluginException {
      throw MissingDalvikBridge('Native iOS audio channel $method');
    }
  }

  Object? command(
    _Player p,
    String method, {
    Map<String, Object?> args = const {},
    void Function()? after,
  }) {
    vm.suspendUntil(
      invoke(method, {'id': p.id, ...args}).then((_) {
        after?.call();
        return null;
      }),
    );
  }

  vm.registerNative('$_media-><init>()V', (_, a) {
    final object = vm.object(a[0]);
    final p = _Player(object, env._nextId++);
    object.nativeValue = p;
    env._players[p.id] = p;
    return null;
  });
  vm.registerNative(
    '$_media->setOnCompletionListener(Landroid/media/MediaPlayer\$OnCompletionListener;)V',
    (_, a) {
      player(a[0]).completion = a[1];
      return null;
    },
  );
  void dataSource(_Player p, List<int> bytes) {
    require(p, {_State.idle});
    final digest = sha256.convert(bytes).toString();
    final asset = env.assets[digest];
    if (asset == null) {
      throw MissingDalvikBridge(
        'MediaPlayer source SHA256 $digest is absent from verified audio manifest',
      );
    }
    p.asset = asset;
    p.state = _State.initialized;
  }

  vm.registerNative('$_media->setDataSource(Ljava/io/FileDescriptor;)V', (
    _,
    a,
  ) {
    final p = player(a[0]);
    require(p, {_State.idle});
    dataSource(p, javaFileDescriptorBytes(vm, a[1]));
    return null;
  });
  vm.registerNative('$_media->setDataSource(Ljava/io/FileDescriptor;JJ)V', (
    _,
    a,
  ) {
    final p = player(a[0]);
    require(p, {_State.idle});
    final data = javaFileDescriptorBytes(vm, a[1]);
    final offset = JBits.wide(a, 2), length = JBits.wide(a, 4);
    if (offset < 0 ||
        length < 0 ||
        offset > data.length ||
        length > data.length - offset) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'File descriptor range',
      );
    }
    dataSource(p, data.sublist(offset, offset + length));
    return null;
  });
  vm.registerNative('$_media->prepare()V', (_, a) {
    final p = player(a[0]);
    require(p, {_State.initialized, _State.stopped});
    vm.suspendUntil(
      invoke('load', {'id': p.id, 'asset': p.asset}, preparing: true).then((
        value,
      ) {
        p.duration = (value as Map)['durationMs'] as int;
        p.loaded = true;
        p.state = _State.prepared;
        return null;
      }),
    );
  });
  const ready = {
    _State.prepared,
    _State.started,
    _State.paused,
    _State.completed,
  };
  vm.registerNative('$_media->start()V', (_, a) {
    final p = player(a[0]);
    require(p, ready);
    return command(
      p,
      'play',
      args: {
        'looping': p.looping,
        'left': p.left,
        'right': p.right,
        'rate': 1.0,
      },
      after: () => p.state = _State.started,
    );
  });
  vm.registerNative('$_media->pause()V', (_, a) {
    final p = player(a[0]);
    require(p, {_State.started, _State.paused, _State.completed});
    return command(p, 'pause', after: () => p.state = _State.paused);
  });
  vm.registerNative('$_media->stop()V', (_, a) {
    final p = player(a[0]);
    require(p, {...ready, _State.stopped});
    return command(p, 'stop', after: () => p.state = _State.stopped);
  });
  vm.registerNative('$_media->release()V', (_, a) {
    final p = vm.object(a[0]).nativeValue as _Player;
    if (p.state == _State.end) return null;
    void finish() {
      p.state = _State.end;
      env._players.remove(p.id);
    }

    if (!p.loaded) {
      finish();
      return null;
    }
    return command(p, 'release', after: finish);
  });
  vm.registerNative('$_media->setLooping(Z)V', (_, a) {
    final p = player(a[0]);
    final looping = a[1] != 0;
    require(p, {_State.idle, _State.initialized, ...ready, _State.stopped});
    if (!p.loaded) {
      p.looping = looping;
      return null;
    }
    return command(
      p,
      'setLooping',
      args: {'looping': looping},
      after: () => p.looping = looping,
    );
  });
  vm.registerNative('$_media->setVolume(FF)V', (_, a) {
    final p = player(a[0]);
    final left = JBits.float(a, 1), right = JBits.float(a, 2);
    if (!left.isFinite || !right.isFinite) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'Nonfinite audio volume',
      );
    }
    final l = left.clamp(0.0, 1.0), r = right.clamp(0.0, 1.0);
    if (l != r) {
      throw MissingDalvikBridge(
        'Asymmetric MediaPlayer channel volume ($l/$r)',
      );
    }
    void finish() {
      p.left = l;
      p.right = r;
    }

    if (!p.loaded) {
      finish();
      return null;
    }
    return command(
      p,
      'setVolume',
      args: {'left': l, 'right': r},
      after: finish,
    );
  });
  for (final member in [
    'isPlaying()Z',
    'getCurrentPosition()I',
    'getDuration()I',
  ]) {
    vm.registerNative('$_media->$member', (_, a) {
      final p = player(a[0]);
      if (!p.loaded && member != 'getDuration()I') return 0;
      require(p, {...ready, _State.stopped});
      vm.suspendUntil(
        invoke('status', {'id': p.id}).then((value) {
          final status = value as Map;
          return switch (member) {
            'isPlaying()Z' => status['playing'] == true ? 1 : 0,
            'getCurrentPosition()I' => status['positionMs'] as int,
            _ => status['durationMs'] as int,
          };
        }),
      );
    });
  }
  vm.registerNative('$_media->getAudioSessionId()I', (_, a) => player(a[0]).id);
  vm.registerNative('$_media->seekTo(I)V', (_, a) {
    final p = player(a[0]);
    require(p, ready);
    return command(
      p,
      'seek',
      args: {'positionMs': (a[1] as int).clamp(0, p.duration)},
    );
  });
  vm.registerNative('$_pool-><init>(III)V', (_, a) {
    if ((a[1] as int) < 1) {
      vm.throwJava('Ljava/lang/IllegalArgumentException;', 'maxStreams');
    }
    vm.object(a[0]).nativeValue = _SoundPool(
      a[1] as int,
      a[2] as int,
      a[3] as int,
    );
    return null;
  });
  vm.registerNative(
    '$_pool->setOnLoadCompleteListener(Landroid/media/SoundPool\$OnLoadCompleteListener;)V',
    (_, a) {
      (vm.object(a[0]).nativeValue as _SoundPool).listener = a[1];
      return null;
    },
  );
  // Original u.Y is false and has no DEX writes. The game loads all 82 sounds
  // through MediaPlayer; retain the genuine unused SoundPool object's state.
  for (final member in [
    'load(Ljava/lang/String;I)I',
    'play(IFFIIF)I',
    'unload(I)Z',
    'setRate(IF)V',
    'resume(I)V',
    'pause(I)V',
    'stop(I)V',
  ]) {
    vm.registerNative(
      '$_pool->$member',
      (_, a) => throw MissingDalvikBridge(
        'SoundPool $member (original MediaPlayer routing expected)',
      ),
    );
  }
  vm.registerNative('$_pool->release()V', (_, a) {
    (vm.object(a[0]).nativeValue as _SoundPool).released = true;
    return null;
  });
  vm.registerNative('$_manager->isMusicActive()Z', (_, a) {
    vm.suspendUntil(
      invoke(
        'systemStatus',
        {},
      ).then((value) => (value as Map)['musicActive'] == true ? 1 : 0),
    );
  });
  vm.registerNative('$_manager->getStreamVolume(I)I', (_, a) {
    if (a[1] != 3) throw MissingDalvikBridge('AudioManager stream ${a[1]}');
    // iOS exposes a normalized hardware volume. Android's music index uses
    // the compatibility range 0..15; derive it from the actual native value.
    vm.suspendUntil(
      invoke('systemStatus', {}).then(
        (value) => (((value as Map)['outputVolume'] as num).toDouble() * 15)
            .round()
            .clamp(0, 15),
      ),
    );
  });
  vm.registerNative(
    '$_manager->requestAudioFocus(Landroid/media/AudioManager\$OnAudioFocusChangeListener;II)I',
    (_, a) {
      if (a[2] != 3 || a[3] != 1) {
        throw MissingDalvikBridge('Audio focus stream ${a[2]} gain ${a[3]}');
      }
      vm.suspendUntil(
        invoke('requestFocus', {}).then((value) {
          if (value == true) {
            env._focusListener = a[1];
            return 1;
          }
          return 0;
        }),
      );
    },
  );
  for (final member in [
    'getRingerMode()I',
    'adjustStreamVolume(III)V',
    'setStreamMute(IZ)V',
  ]) {
    vm.registerNative(
      '$_manager->$member',
      (_, a) => throw MissingDalvikBridge(
        'iOS has no public Android-equivalent $member',
      ),
    );
  }
}
