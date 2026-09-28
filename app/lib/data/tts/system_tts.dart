import 'package:flutter/services.dart';

import '../../domain/ports/text_to_speech.dart';

/// Голосовой ответ через встроенный Android TextToSpeech (ТЗ, раздел 4: TTS,
/// старт). Ничего не скачивает и не весит — на этом этапе этого достаточно.
/// Piper ru_RU приходит на замену в v1.0, интерфейс не меняется.
class SystemTts implements TextToSpeech {
  SystemTts({bool enabled = true}) : _enabled = enabled;

  static const MethodChannel _channel = MethodChannel('dev.akyl/tts');

  bool _enabled;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    _enabled = value;
    if (!value) stop();
  }

  @override
  Future<void> init() => _channel.invokeMethod('init', {'locale': 'ru_RU'});

  @override
  Future<void> speak(String text) async {
    if (!_enabled) return; // ТЗ, FR-11: ответ можно отключить в настройках
    await _channel.invokeMethod('speak', {'text': text});
  }

  @override
  Future<void> stop() => _channel.invokeMethod('stop');
}
