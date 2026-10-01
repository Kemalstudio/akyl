import 'package:flutter/services.dart';

import '../../domain/ports/device_control.dart';

/// Будильник, фонарик, громкость, SMS, звонки и приложения — через Kotlin
/// (DeviceBridge.kt). Ошибки Android приходят с текстом для человека.
class DeviceControlBridge implements DeviceControl {
  const DeviceControlBridge();

  static const MethodChannel _channel = MethodChannel('dev.akyl/device');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw DeviceControlError(e.message ?? 'Не получилось');
    } on MissingPluginException {
      throw const DeviceControlError('Эта команда работает только на Android');
    }
  }

  @override
  Future<bool> setAlarm(int hour, int minute) async =>
      await _call<String>('setAlarm', {'hour': hour, 'minute': minute}) !=
      'own';

  @override
  Future<void> setTimer(int seconds) => _call('setTimer', {'seconds': seconds});

  @override
  Future<void> setTorch(bool on) => _call('setTorch', {'on': on});

  @override
  Future<void> media(String action) => _call('media', {'action': action});

  @override
  Future<void> changeVolume(String change) =>
      _call('changeVolume', {'change': change});

  @override
  Future<({String from, String body})?> lastSms() async {
    final data = await _call<Map<Object?, Object?>>('lastSms');
    if (data == null) return null;
    return (from: data['from'] as String, body: data['body'] as String);
  }

  @override
  Future<List<({String name, String type})>> recentCalls({
    int limit = 3,
  }) async {
    final data = await _call<List<Object?>>('recentCalls', {'limit': limit});
    return [
      for (final item in data ?? const [])
        if (item case {'name': final String name, 'type': final String type})
          (name: name, type: type),
    ];
  }

  @override
  Future<({DateTime at, String type})?> lastCallWith(
    List<String> numbers,
  ) async {
    final data = await _call<Map<Object?, Object?>>('lastCallWith', {
      'numbers': numbers,
    });
    if (data case {'at': final int at, 'type': final String type}) {
      return (at: DateTime.fromMillisecondsSinceEpoch(at), type: type);
    }
    return null;
  }

  @override
  Future<({double lat, double lon})?> location() async {
    final data = await _call<Map<Object?, Object?>>('location');
    if (data case {'lat': final double lat, 'lon': final double lon}) {
      return (lat: lat, lon: lon);
    }
    return null;
  }

  @override
  Future<String?> openApp(String spokenName) =>
      _call<String>('openApp', {'query': spokenName});
}
