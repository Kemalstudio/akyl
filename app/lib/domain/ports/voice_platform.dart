/// Системные события, от которых зависит микрофон.
sealed class PlatformVoiceEvent {
  const PlatformVoiceEvent();
}

/// Экран заблокирован или разблокирован.
class LockChanged extends PlatformVoiceEvent {
  const LockChanged(this.locked);
  final bool locked;
}

/// Начался или кончился телефонный/VoIP-разговор.
class CallChanged extends PlatformVoiceEvent {
  const CallChanged(this.active);
  final bool active;
}

/// Android заглушил нашу запись: микрофон забрало другое приложение.
class MicSilenced extends PlatformVoiceEvent {
  const MicSilenced(this.silenced);
  final bool silenced;
}

/// Фоновая служба запущена или остановлена (в том числе из уведомления).
class ServiceChanged extends PlatformVoiceEvent {
  const ServiceChanged({required this.running, this.userStopped = false});
  final bool running;

  /// Человек нажал «Выключить» в уведомлении.
  final bool userStopped;
}

/// Помощника вызвали жестом Android: надо слушать команду.
class AssistInvoked extends PlatformVoiceEvent {
  const AssistInvoked();
}

/// Другое приложение распознаёт речь через наш сервис.
class ExternalRecognition extends PlatformVoiceEvent {
  const ExternalRecognition(this.active);
  final bool active;
}

/// Снимок системного состояния — для настроек и отладки.
class PlatformVoiceStatus {
  const PlatformVoiceStatus({
    this.serviceRunning = false,
    this.assistantSelected = false,
    this.locked = false,
    this.callActive = false,
    this.micSilenced = false,
    this.ignoringBatteryOptimizations = false,
    this.echoCancellerAvailable = false,
    this.echoCancellerActive = false,
    this.noiseSuppressorActive = false,
    this.audioSource = '',
    this.notificationsAllowed = true,
  });

  final bool serviceRunning;
  final bool assistantSelected;
  final bool locked;
  final bool callActive;
  final bool micSilenced;

  /// Приложение исключено из оптимизации батареи — Android реже убьёт службу.
  final bool ignoringBatteryOptimizations;

  final bool echoCancellerAvailable;
  final bool echoCancellerActive;
  final bool noiseSuppressorActive;

  /// VOICE_RECOGNITION или VOICE_COMMUNICATION.
  final String audioSource;

  final bool notificationsAllowed;
}

/// Звук-подтверждение «слушаю».
enum VoiceCue { listening, done, error }

/// Всё системное вокруг голоса: фоновая служба, события телефона, сигналы.
abstract class VoicePlatform {
  Stream<PlatformVoiceEvent> get events;

  Future<PlatformVoiceStatus> status();

  /// Запустить foreground-службу микрофона. Android разрешает это, пока
  /// приложение на экране или когда оно — выбранный помощник.
  Future<bool> startService();

  Future<void> stopService();

  /// Текст в уведомлении службы — то же состояние, что на экране.
  Future<void> updateNotification(String text);

  /// Флаг для перезапуска после перезагрузки: его читает AssistantVoiceService.
  Future<void> setBackgroundEnabled(bool enabled);

  Future<void> playCue(VoiceCue cue);

  Future<void> selectAssistant();

  Future<void> openBatterySettings();

  /// Команда, пришедшая через системный жест помощника, если есть.
  Future<String?> takeCommand();
}

/// Для тестов и не-Android платформ: ничего не умеет, ничего не ломает.
class NoopVoicePlatform implements VoicePlatform {
  const NoopVoicePlatform();

  @override
  Stream<PlatformVoiceEvent> get events => const Stream.empty();

  @override
  Future<PlatformVoiceStatus> status() async => const PlatformVoiceStatus();

  @override
  Future<bool> startService() async => false;

  @override
  Future<void> stopService() async {}

  @override
  Future<void> updateNotification(String text) async {}

  @override
  Future<void> setBackgroundEnabled(bool enabled) async {}

  @override
  Future<void> playCue(VoiceCue cue) async {}

  @override
  Future<void> selectAssistant() async {}

  @override
  Future<void> openBatterySettings() async {}

  @override
  Future<String?> takeCommand() async => null;
}
