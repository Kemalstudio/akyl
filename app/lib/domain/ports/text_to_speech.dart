/// Голосовой ответ. Можно отключить в настройках (ТЗ, FR-11).
/// Этап 1 — системный Android TextToSpeech, v1.0 — Piper ru_RU.
abstract class TextToSpeech {
  Future<void> init();

  Future<void> speak(String text);

  Future<void> stop();

  /// false — ассистент отвечает только текстом на экране.
  bool get enabled;

  set enabled(bool value);
}
