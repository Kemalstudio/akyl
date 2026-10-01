import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/ports/voice_platform.dart';

/// Мост к VoiceBridge.kt: служба микрофона, события телефона, сигналы.
class AndroidVoicePlatform implements VoicePlatform {
  AndroidVoicePlatform();

  static const _channel = MethodChannel('dev.akyl/voice');
  static const _eventChannel = EventChannel('dev.akyl/voice_events');

  late final Stream<PlatformVoiceEvent> _events = _eventChannel
      .receiveBroadcastStream()
      .map(_parse)
      .where((e) => e != null)
      .cast<PlatformVoiceEvent>()
      .asBroadcastStream();

  static PlatformVoiceEvent? _parse(Object? raw) {
    if (raw is! Map) return null;
    final value = raw['value'] == true;
    return switch (raw['type']) {
      'lock' => LockChanged(value),
      'call' => CallChanged(value),
      'silenced' => MicSilenced(value),
      'service' => ServiceChanged(
        running: value,
        userStopped: raw['user'] == true,
      ),
      'assist' => const AssistInvoked(),
      'recognition' => ExternalRecognition(value),
      _ => null,
    };
  }

  @override
  Stream<PlatformVoiceEvent> get events => _events;

  @override
  Future<PlatformVoiceStatus> status() async {
    final m = await _channel.invokeMapMethod<String, Object?>('status') ?? {};
    bool flag(String key) => m[key] == true;
    return PlatformVoiceStatus(
      serviceRunning: flag('serviceRunning'),
      assistantSelected: flag('assistantSelected'),
      locked: flag('locked'),
      callActive: flag('callActive'),
      micSilenced: flag('micSilenced'),
      ignoringBatteryOptimizations: flag('ignoringBatteryOptimizations'),
      echoCancellerAvailable: flag('aecAvailable'),
      echoCancellerActive: flag('aecActive'),
      noiseSuppressorActive: flag('nsActive'),
      audioSource: m['audioSource'] as String? ?? '',
      notificationsAllowed: m['notificationsAllowed'] != false,
    );
  }

  @override
  Future<bool> startService() async =>
      await _channel.invokeMethod<bool>('startService') ?? false;

  @override
  Future<void> stopService() => _channel.invokeMethod('stopService');

  @override
  Future<void> updateNotification(String text) =>
      _channel.invokeMethod('updateNotification', {'text': text});

  @override
  Future<void> setBackgroundEnabled(bool enabled) =>
      _channel.invokeMethod('setBackgroundEnabled', {'enabled': enabled});

  @override
  Future<void> playCue(VoiceCue cue) =>
      _channel.invokeMethod('playCue', {'cue': cue.name});

  @override
  Future<void> selectAssistant() => _channel.invokeMethod('selectAssistant');

  @override
  Future<void> openBatterySettings() =>
      _channel.invokeMethod('openBatterySettings');

  @override
  Future<String?> takeCommand() => _channel.invokeMethod<String>('takeCommand');
}
