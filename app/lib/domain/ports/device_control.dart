/// Управление телефоном голосом: будильник, фонарик, громкость, приложения.
///
/// Каждый метод либо делает дело, либо бросает [DeviceControlError] с текстом,
/// который можно сказать человеку вслух.
abstract class DeviceControl {
  /// true — будильник в приложении «Часы», false — его поставил сам
  /// помощник (из фона Android не даёт открыть «Часы»).
  Future<bool> setAlarm(int hour, int minute);

  Future<void> setTimer(int seconds);

  Future<void> setTorch(bool on);

  /// up | down | mute | unmute | max
  Future<void> changeVolume(String change);

  /// Последнее входящее SMS или null, если сообщений нет.
  Future<({String from, String body})?> lastSms();

  /// Последние звонки, свежие первыми.
  Future<List<({String name, String type})>> recentCalls({int limit = 3});

  /// Открывает приложение по произнесённому названию. Возвращает, как оно
  /// называется на телефоне, или null, если такого нет.
  Future<String?> openApp(String spokenName);

  /// Последний звонок с любым из номеров: когда и кто звонил.
  /// type: incoming | outgoing | missed. null — звонков не было.
  Future<({DateTime at, String type})?> lastCallWith(List<String> numbers);

  /// Управление плеером, который сейчас играет: play | pause | next | previous.
  Future<void> media(String action);

  /// Где телефон сейчас — для SOS. Работает без интернета, по GPS.
  /// null — место неизвестно или нет разрешения.
  Future<({double lat, double lon})?> location();
}

/// Сбой с понятным человеку объяснением.
class DeviceControlError implements Exception {
  const DeviceControlError(this.message);
  final String message;

  @override
  String toString() => message;
}
