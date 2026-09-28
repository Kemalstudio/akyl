import 'package:flutter/services.dart';

import '../../domain/ports/phone.dart';

/// Звонок и SMS через Kotlin (ТЗ, раздел 5: Kotlin только для системных вызовов).
class PhoneBridge implements Phone {
  const PhoneBridge();

  static const MethodChannel _channel = MethodChannel('dev.akyl/phone');

  @override
  Future<bool> hasPermissions() async =>
      await _channel.invokeMethod<bool>('hasPermissions') ?? false;

  @override
  Future<bool> requestPermissions() async =>
      await _channel.invokeMethod<bool>('requestPermissions') ?? false;

  @override
  Future<void> call(String number, {bool speaker = false}) =>
      _channel.invokeMethod('call', {'number': number, 'speaker': speaker});

  @override
  Future<void> sendSms({required String number, required String text}) =>
      _channel.invokeMethod('sendSms', {'number': number, 'text': text});
}
