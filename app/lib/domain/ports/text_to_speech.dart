/// Голос синтеза, установленный на телефоне.
class TtsVoice {
  const TtsVoice({
    required this.name,
    required this.quality,
    this.local = true,
    this.gender,
  });

  final String name;

  /// Заявленное движком качество, 100–500.
  final int quality;

  /// Работает без сети.
  final bool local;
  final String? gender;
}

/// Голосовой ответ. Можно отключить в настройках (ТЗ, FR-11).
abstract class TextToSpeech {
  Future<void> init();

  /// Завершается, когда фраза договорена (или прервана [stop]).
  Future<void> speak(String text);

  Future<void> stop();

  /// false — ассистент отвечает только текстом на экране.
  bool get enabled;

  set enabled(bool value);

  /// Ритм речи для анимации: 1 на начале каждого слова.
  Stream<double> get speechPulses;

  /// Установленные офлайн-голоса языка ответа.
  Future<List<TtsVoice>> voices();

  /// null — лучший офлайн-голос.
  Future<void> setVoice(String? name);
}
