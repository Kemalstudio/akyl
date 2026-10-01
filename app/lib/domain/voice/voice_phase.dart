/// Состояние голосового конвейера. Единственный источник правды — VoiceManager:
/// экран, уведомление службы и панель отладки показывают именно это значение.
///
/// ```
/// disabled → starting → listeningForWake → wakeDetected → listeningForCommand
///                ↑                                               ↓
///                └──────── speaking ←──────── processing ←───────┘
/// error → recovering → listeningForWake
/// ```
enum VoicePhase {
  /// Микрофон закрыт: обращение выключено или приложение в фоне без службы.
  disabled,

  /// Модель грузится или микрофон открывается.
  starting,

  /// Микрофон открыт, VAD ждёт речь, T-one ищет в ней «Макс».
  listeningForWake,

  /// Обращение услышано — короткое состояние для анимации и сигнала.
  wakeDetected,

  /// Слушаю команду: после обращения, кнопки или в продолжении разговора.
  listeningForCommand,

  /// Команда разбирается и выполняется.
  processing,

  /// Ответ звучит; обращение в это время заглушено или слушает перебивание.
  speaking,

  /// Микрофон временно отдан: звонок, другое приложение, фон.
  paused,

  /// Сбой, который не лечится повтором (нет разрешения, нет модели).
  error,

  /// Сбой микрофона — повторная попытка по нарастающей задержке.
  recovering;

  /// Микрофон открыт приложением прямо сейчас.
  bool get micActive => switch (this) {
    listeningForWake ||
    wakeDetected ||
    listeningForCommand ||
    processing ||
    speaking => true,
    _ => false,
  };

  /// Идёт разговор с человеком — не фоновое ожидание.
  bool get inSession => switch (this) {
    wakeDetected || listeningForCommand || processing || speaking => true,
    _ => false,
  };
}

/// Почему микрофон отдан.
enum VoicePauseReason {
  none,

  /// Телефонный или VoIP-разговор.
  call,

  /// Android заглушил запись: микрофон занят другим приложением.
  micBusy,

  /// Приложение свёрнуто, а фоновый режим выключен.
  background,

  /// Другое приложение распознаёт речь через наш сервис помощника.
  externalRecognition,
}
