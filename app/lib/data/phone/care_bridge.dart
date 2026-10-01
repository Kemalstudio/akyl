import 'package:flutter/services.dart';

import '../../domain/ports/device_control.dart';
import '../../domain/ports/life_ports.dart';

/// Напоминания и присмотр за телефоном — через Kotlin (CareBridge.kt):
/// будильник Android срабатывает, даже если приложение закрыто, и
/// переживает перезагрузку.
class CareBridge implements ReminderScheduler {
  const CareBridge();

  static const MethodChannel _channel = MethodChannel('dev.akyl/care');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw DeviceControlError(e.message ?? 'Не получилось');
    } on MissingPluginException {
      throw const DeviceControlError('Работает только на Android');
    }
  }

  @override
  Future<void> schedule(Reminder reminder) => _call('schedule', {
    'id': reminder.id,
    'text': reminder.text,
    'at': reminder.at.millisecondsSinceEpoch,
    'daily': reminder.daily,
  });

  @override
  Future<void> cancel(int id) => _call('cancel', {'id': id});

  @override
  Future<List<Reminder>> list() async {
    final data = await _call<List<Object?>>('list') ?? const [];
    final reminders = [
      for (final item in data)
        if (item case {
          'id': final int id,
          'text': final String text,
          'at': final int at,
          'daily': final bool daily,
        })
          Reminder(
            id: id,
            text: text,
            at: DateTime.fromMillisecondsSinceEpoch(at),
            daily: daily,
          ),
    ];
    reminders.sort((a, b) => a.at.compareTo(b.at));
    return reminders;
  }

  /// Присмотр: при заряде ниже 15% телефон сам пишет близким. Пустой
  /// список — выключить.
  Future<void> setBatteryWatch(List<String> numbers) =>
      _call('setBatteryWatch', {'numbers': numbers});

  Future<bool> batteryWatchEnabled() async =>
      await _call<bool>('batteryWatchEnabled') ?? false;

  /// Разрешение на место — для SOS. Спрашивается заранее, в настройках:
  /// в экстренной ситуации системный диалог был бы помехой.
  Future<bool> requestLocationPermission() async =>
      await _call<bool>('requestLocation') ?? false;
}
