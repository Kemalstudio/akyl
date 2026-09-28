/// Потоковое распознавание речи (ТЗ, FR-2).
/// Реализации: VoskStt (прототип), TOneStt (v1.0) — обе через sherpa-onnx.
abstract class SpeechToText {
  /// Загрузить модель. Вызывается один раз при старте, не на каждую фразу.
  Future<void> init();

  /// Промежуточный текст, пока человек говорит — выводится на экран (ТЗ, FR-2).
  Stream<String> partialResults();

  /// Начать слушать. Завершается, когда VAD поймал конец фразы.
  Future<void> start();

  /// Финальный текст фразы.
  Future<String> finalResult();

  /// Прервать распознавание («отмена», ТЗ FR-9).
  Future<void> stop();

  Future<void> dispose();
}
