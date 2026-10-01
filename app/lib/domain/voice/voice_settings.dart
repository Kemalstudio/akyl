/// Насколько охотно помощник принимает похожее на обращение слово.
enum WakeSensitivity { low, medium, high }

/// Обработка звука платформой: авто — по возможностям устройства.
enum AudioProcessing { auto, on, off }

/// Чем помощник отвечает на одно лишь «Макс».
enum ActivationCue { tone, voice, silent }

/// Настройки голоса. Неизменяемые: VoiceManager сравнивает старые и новые
/// и перестраивает только то, что поменялось.
class VoiceSettings {
  const VoiceSettings({
    this.wakeEnabled = false,
    this.wakePhrase = WakePhrases.max,
    this.background = false,
    this.conversationSeconds = 10,
    this.autoSpeak = true,
    this.interrupt = true,
    this.sensitivity = WakeSensitivity.medium,
    this.noiseSuppression = AudioProcessing.auto,
    this.echoCancellation = AudioProcessing.auto,
    this.cue = ActivationCue.tone,
    this.personalOnLockScreen = false,
    this.voiceName,
    this.silenceMs = 700,
    this.maxUtteranceMs = 15000,
  });

  /// Слушать обращение. По умолчанию выключено: микрофон открывается только
  /// после явного выбора человека.
  final bool wakeEnabled;

  /// Каноническая форма фразы из [WakePhrases].
  final String wakePhrase;

  /// Продолжать слушать, когда приложение свёрнуто или экран заблокирован.
  final bool background;

  /// Сколько секунд после ответа ждать продолжения разговора без «Макс».
  /// 0 — после каждого ответа снова нужно обращение.
  final int conversationSeconds;

  /// Произносить ответы вслух.
  final bool autoSpeak;

  /// Можно перебить ответ словом «Макс» (и просто речью, если есть AEC).
  final bool interrupt;

  final WakeSensitivity sensitivity;
  final AudioProcessing noiseSuppression;
  final AudioProcessing echoCancellation;
  final ActivationCue cue;

  /// Читать SMS, журнал звонков и память при заблокированном экране.
  final bool personalOnLockScreen;

  /// Выбранный голос TTS; null — лучший офлайн-голос.
  final String? voiceName;

  /// Тишина после речи, которая считается концом команды.
  final int silenceMs;

  /// Предел одной команды.
  final int maxUtteranceMs;

  static const conversationChoices = [0, 5, 10, 15, 30];

  /// Порог Silero VAD: чем чувствительнее, тем тише речь он замечает.
  double get speechThreshold => switch (sensitivity) {
    WakeSensitivity.low => 0.6,
    WakeSensitivity.medium => 0.5,
    WakeSensitivity.high => 0.4,
  };

  VoiceSettings copyWith({
    bool? wakeEnabled,
    String? wakePhrase,
    bool? background,
    int? conversationSeconds,
    bool? autoSpeak,
    bool? interrupt,
    WakeSensitivity? sensitivity,
    AudioProcessing? noiseSuppression,
    AudioProcessing? echoCancellation,
    ActivationCue? cue,
    bool? personalOnLockScreen,
    String? voiceName,
    bool clearVoiceName = false,
    int? silenceMs,
    int? maxUtteranceMs,
  }) => VoiceSettings(
    wakeEnabled: wakeEnabled ?? this.wakeEnabled,
    wakePhrase: wakePhrase ?? this.wakePhrase,
    background: background ?? this.background,
    conversationSeconds: conversationSeconds ?? this.conversationSeconds,
    autoSpeak: autoSpeak ?? this.autoSpeak,
    interrupt: interrupt ?? this.interrupt,
    sensitivity: sensitivity ?? this.sensitivity,
    noiseSuppression: noiseSuppression ?? this.noiseSuppression,
    echoCancellation: echoCancellation ?? this.echoCancellation,
    cue: cue ?? this.cue,
    personalOnLockScreen: personalOnLockScreen ?? this.personalOnLockScreen,
    voiceName: clearVoiceName ? null : voiceName ?? this.voiceName,
    silenceMs: silenceMs ?? this.silenceMs,
    maxUtteranceMs: maxUtteranceMs ?? this.maxUtteranceMs,
  );

  Map<String, Object> toMap() => {
    'wakeEnabled': wakeEnabled,
    'wakePhrase': wakePhrase,
    'background': background,
    'conversationSeconds': conversationSeconds,
    'autoSpeak': autoSpeak,
    'interrupt': interrupt,
    'sensitivity': sensitivity.name,
    'noiseSuppression': noiseSuppression.name,
    'echoCancellation': echoCancellation.name,
    'cue': cue.name,
    'personalOnLockScreen': personalOnLockScreen,
    'voiceName': ?voiceName,
    'silenceMs': silenceMs,
    'maxUtteranceMs': maxUtteranceMs,
  };

  /// Незнакомые и испорченные значения заменяются умолчаниями: старая
  /// версия настроек не должна ронять запуск.
  factory VoiceSettings.fromMap(Map<String, Object?> m) {
    const d = VoiceSettings();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    final phrase = m['wakePhrase'];
    return VoiceSettings(
      wakeEnabled: m['wakeEnabled'] as bool? ?? d.wakeEnabled,
      wakePhrase: phrase is String && WakePhrases.all.contains(phrase)
          ? phrase
          : d.wakePhrase,
      background: m['background'] as bool? ?? d.background,
      conversationSeconds:
          (m['conversationSeconds'] as int? ?? d.conversationSeconds).clamp(
            0,
            120,
          ),
      autoSpeak: m['autoSpeak'] as bool? ?? d.autoSpeak,
      interrupt: m['interrupt'] as bool? ?? d.interrupt,
      sensitivity: pick(
        WakeSensitivity.values,
        m['sensitivity'],
        d.sensitivity,
      ),
      noiseSuppression: pick(
        AudioProcessing.values,
        m['noiseSuppression'],
        d.noiseSuppression,
      ),
      echoCancellation: pick(
        AudioProcessing.values,
        m['echoCancellation'],
        d.echoCancellation,
      ),
      cue: pick(ActivationCue.values, m['cue'], d.cue),
      personalOnLockScreen:
          m['personalOnLockScreen'] as bool? ?? d.personalOnLockScreen,
      voiceName: m['voiceName'] as String?,
      silenceMs: (m['silenceMs'] as int? ?? d.silenceMs).clamp(300, 3000),
      maxUtteranceMs: (m['maxUtteranceMs'] as int? ?? d.maxUtteranceMs).clamp(
        3000,
        60000,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceSettings && _mapEquals(toMap(), other.toMap());

  @override
  int get hashCode => Object.hashAll(toMap().entries.map((e) => e.value));
}

bool _mapEquals(Map<String, Object> a, Map<String, Object> b) =>
    a.length == b.length && a.keys.every((k) => a[k] == b[k]);

/// Фразы обращения, из которых человек выбирает.
abstract final class WakePhrases {
  static const max = 'макс';
  static const heyMax = 'эй макс';
  static const alym = 'алым';
  static const all = [max, heyMax, alym];

  static String title(String phrase) => switch (phrase) {
    heyMax => '«Эй, Макс»',
    alym => '«Алым»',
    _ => '«Макс»',
  };
}
