import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/ports/text_to_speech.dart';

/// Голосовой ответ через встроенный Android TextToSpeech. TtsBridge.kt сам
/// берёт аудиофокус с приглушением: музыка стихает на время ответа.
class SystemTts implements TextToSpeech {
  SystemTts({bool enabled = true, this.rate = 0.94, this.pitch = 0.96})
    : _enabled = enabled;

  static const MethodChannel _channel = MethodChannel('dev.akyl/tts');
  static const EventChannel _events = EventChannel('dev.akyl/tts_events');

  /// Темп речи. Чуть медленнее обычного: ассистент говорит короткими
  /// фразами вроде «Звоню Маме», и на стандартной скорости они
  /// проглатываются.
  final double rate;

  /// Высота голоса. Чуть ниже обычной — звучит спокойнее.
  final double pitch;

  bool _enabled;

  late final Stream<double> _pulses = _events
      .receiveBroadcastStream()
      .where((e) => e is Map && e['type'] == 'word')
      .map((_) => 1.0)
      .asBroadcastStream();

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    _enabled = value;
    if (!value) unawaited(stop());
  }

  @override
  Future<void> init() => _channel.invokeMethod('init', {
    'locale': 'ru_RU',
    'rate': rate,
    'pitch': pitch,
  });

  /// Какой голос выбрала система — для экрана настроек.
  Future<String?> voiceName() => _channel.invokeMethod<String>('voiceName');

  @override
  Future<void> speak(String text) async {
    if (!_enabled) return; // ТЗ, FR-11: ответ можно отключить в настройках
    await _channel.invokeMethod('speak', {'text': text});
  }

  @override
  Future<void> stop() => _channel.invokeMethod('stop');

  @override
  Stream<double> get speechPulses => _pulses;

  @override
  Future<List<TtsVoice>> voices() async {
    final raw = await _channel.invokeListMethod<Object?>('voices') ?? const [];
    return [
      for (final v in raw.whereType<Map<Object?, Object?>>())
        TtsVoice(
          name: v['name'] as String? ?? '',
          quality: v['quality'] as int? ?? 300,
          local: v['local'] != false,
        ),
    ];
  }

  @override
  Future<void> setVoice(String? name) =>
      _channel.invokeMethod('setVoice', {'name': name});
}
