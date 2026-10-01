import 'package:flutter/services.dart';

import '../../domain/ports/device_info.dart';

/// Заряд батареи через BatteryManager (Kotlin).
class DeviceInfoBridge implements DeviceInfo {
  const DeviceInfoBridge();

  static const MethodChannel _channel = MethodChannel('dev.akyl/device');

  @override
  Future<int?> batteryLevel() async {
    try {
      return await _channel.invokeMethod<int>('batteryLevel');
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> isCharging() async {
    try {
      return await _channel.invokeMethod<bool>('isCharging') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
