/// Потоковое распознавание речи (ТЗ, FR-2).
/// Реализации: VoskStt (прототип), TOneStt (v1.0) — обе через sherpa-onnx.
abstract class SpeechToText {
  /// Загрузить модель. Вызывается один раз при старте, не на каждую фразу.
  Future<void> init();

  /// Промежуточный текст, пока человек говорит — выводится на экран (ТЗ, FR-2).
  Stream<String> partialResults();

  /// Громкость голоса 0..1, пока микрофон открыт: экран дышит в такт речи.
  Stream<double> soundLevels();

  /// Начать слушать. Завершается, когда VAD поймал конец фразы.
  Future<void> start();

  /// Ожидание обращения: движок может не завершать сеанс из-за одной тишины.
  /// Обычные распознаватели используют тот же start().
  Future<void> startWake() => start();

  /// Финальный текст фразы.
  Future<String> finalResult();

  /// Прервать распознавание («отмена», ТЗ FR-9).
  Future<void> stop();

  Future<void> dispose();
}

/// Сбой распознавания с понятным человеку текстом.
class SpeechError implements Exception {
  const SpeechError(this.message);
  final String message;

  @override
  String toString() => message;
}
