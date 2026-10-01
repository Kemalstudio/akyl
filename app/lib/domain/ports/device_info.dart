/// Сведения о телефоне, которые ассистент умеет сообщать вслух.
abstract class DeviceInfo {
  /// Заряд в процентах, null — если узнать не удалось.
  Future<int?> batteryLevel();

  Future<bool> isCharging();
}
