import 'dart:async';

import 'package:flutter/services.dart';

class IosNetworkState {
  const IosNetworkState({
    required this.connected,
    required this.available,
    required this.kind,
    required this.expensive,
    required this.constrained,
  });
  factory IosNetworkState.fromMap(Map<Object?, Object?> value) =>
      IosNetworkState(
        connected: value['connected'] as bool,
        available: value['available'] as bool,
        kind: value['kind'] as String,
        expensive: value['expensive'] as bool,
        constrained: value['constrained'] as bool,
      );
  final bool connected, available, expensive, constrained;
  final String kind;
}

class IosHostInfo {
  IosHostInfo.fromMap(Map<Object?, Object?> value)
    : filesDirectory = value['filesDirectory'] as String,
      externalDirectory = value['externalDirectory'] as String,
      cacheDirectory = value['cacheDirectory'] as String,
      model = value['model'] as String,
      release = value['release'] as String,
      language = value['language'] as String,
      country = value['country'] as String,
      locale = value['locale'] as String,
      timeZone = value['timeZone'] as String,
      calendarFirstDayOfWeek = value['calendarFirstDayOfWeek'] as int,
      calendarMinimalDaysInFirstWeek =
          value['calendarMinimalDaysInFirstWeek'] as int,
      rotation = value['rotation'] as int?,
      vendorIdentifier = value['vendorIdentifier'] as String?;
  final String filesDirectory, externalDirectory, cacheDirectory;
  final String model, release, language, country, locale, timeZone;
  final int calendarFirstDayOfWeek, calendarMinimalDaysInFirstWeek;
  final int? rotation;
  final String? vendorIdentifier;
}

/// Owns the native host connection. Network queries wait for a real NWPath
/// observation; an uninitialized monitor is never reported as offline.
class IosHost {
  IosHost({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('green_farm/host') {
    _channel.setMethodCallHandler(_handleNative);
  }
  final MethodChannel _channel;
  final _networkChanges = StreamController<IosNetworkState>.broadcast();
  IosNetworkState? _network;
  IosNetworkState? get currentNetwork => _network;
  Stream<IosNetworkState> get networkChanges => _networkChanges.stream;

  Future<Object?> _handleNative(MethodCall call) async {
    if (call.method == 'networkChanged') {
      _network = IosNetworkState.fromMap(
        call.arguments as Map<Object?, Object?>,
      );
      _networkChanges.add(_network!);
      return null;
    }
    throw MissingPluginException('Unknown native host event: ${call.method}');
  }

  Future<IosHostInfo> information() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('info');
    if (result == null) throw StateError('Native host returned no information');
    return IosHostInfo.fromMap(result);
  }

  Future<IosNetworkState> networkState() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'networkState',
    );
    if (result == null) {
      throw StateError('Native host returned no network state');
    }
    return _network = IosNetworkState.fromMap(result);
  }

  Future<void> setIdleTimerDisabled(bool disabled) => _channel
      .invokeMethod<void>('setIdleTimerDisabled', {'disabled': disabled});

  Future<bool> openUrl(String url) async {
    final result = await _channel.invokeMethod<bool>('openUrl', {'url': url});
    if (result == null) throw StateError('Native URL open returned no result');
    return result;
  }

  Future<String> assetPath(String asset) async {
    final result = await _channel.invokeMethod<String>('assetPath', {
      'asset': asset,
    });
    if (result == null) {
      throw StateError('Native asset lookup returned no path');
    }
    return result;
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _networkChanges.close();
  }
}
