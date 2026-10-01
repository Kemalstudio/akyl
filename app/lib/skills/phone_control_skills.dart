import '../domain/entities/dialog_context.dart';
import '../domain/entities/intent.dart';
import '../domain/entities/nlu_result.dart';
import '../domain/entities/skill_result.dart';
import '../domain/ports/device_control.dart';
import '../domain/ports/skill.dart';

/// Общая часть навыков управления телефоном: ошибку устройства превращаем
/// в понятный ответ, а не в «не удалось завершить команду».
abstract class _DeviceSkill implements Skill {
  _DeviceSkill(this.device);

  final DeviceControl device;

  Future<SkillResult> run(NluResult result);

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    try {
      return await run(result);
    } on DeviceControlError catch (e) {
      return SkillResult.failed(e.message);
    }
  }
}

/// «Поставь будильник на 7:30».
class AlarmSkill extends _DeviceSkill {
  AlarmSkill({required DeviceControl device, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(device);

  final DateTime Function() _clock;

  @override
  Intent get intent => Intent.alarm;

  @override
  Future<SkillResult> run(NluResult result) async {
    final value = result.slot(Slot.value);
    int hour;
    int minute;
    if (value != null && value.startsWith('+')) {
      // «Через 20 минут» — от текущего времени.
      final at = _clock().add(Duration(minutes: int.parse(value.substring(1))));
      hour = at.hour;
      minute = at.minute;
    } else {
      final parts = value?.split(':');
      if (parts == null || parts.length != 2) {
        return SkillResult.failed('На какое время поставить будильник?');
      }
      hour = int.parse(parts[0]);
      minute = int.parse(parts[1]);
    }
    final inClock = await device.setAlarm(hour, minute);
    final time =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    return SkillResult.done(
      inClock ? 'Будильник на $time' : 'Будильник на $time. Прозвеню сам',
    );
  }
}

/// «Поставь таймер на 5 минут».
class TimerSkill extends _DeviceSkill {
  TimerSkill({required DeviceControl device}) : super(device);

  @override
  Intent get intent => Intent.timer;

  @override
  Future<SkillResult> run(NluResult result) async {
    final seconds = int.tryParse(result.slot(Slot.value) ?? '');
    if (seconds == null || seconds <= 0) {
      return SkillResult.failed('На сколько поставить таймер?');
    }
    await device.setTimer(seconds);
    return SkillResult.done('Таймер на ${spokenDuration(seconds)}');
  }
}

/// «Включи фонарик».
class FlashlightSkill extends _DeviceSkill {
  FlashlightSkill({required DeviceControl device}) : super(device);

  @override
  Intent get intent => Intent.flashlight;

  @override
  Future<SkillResult> run(NluResult result) async {
    final on = result.slot(Slot.value) != 'off';
    await device.setTorch(on);
    return SkillResult.done(on ? 'Фонарик включён' : 'Фонарик выключен');
  }
}

/// «Громче», «тише», «выключи звук».
class VolumeSkill extends _DeviceSkill {
  VolumeSkill({required DeviceControl device}) : super(device);

  @override
  Intent get intent => Intent.volume;

  @override
  Future<SkillResult> run(NluResult result) async {
    final change = result.slot(Slot.value) ?? 'up';
    await device.changeVolume(change);
    return SkillResult.done(switch (change) {
      'down' => 'Сделал тише',
      'mute' => 'Звук выключен',
      'unmute' => 'Звук включён',
      'max' => 'Громкость на максимум',
      _ => 'Сделал громче',
    });
  }
}

/// «Прочитай последнее сообщение».
class ReadSmsSkill extends _DeviceSkill {
  ReadSmsSkill({required DeviceControl device}) : super(device);

  @override
  Intent get intent => Intent.readSms;

  @override
  Future<SkillResult> run(NluResult result) async {
    final sms = await device.lastSms();
    if (sms == null) return SkillResult.done('Входящих сообщений нет');
    return SkillResult.done('Сообщение от ${sms.from}: ${sms.body}');
  }
}

/// «Кто звонил».
class RecentCallsSkill extends _DeviceSkill {
  RecentCallsSkill({required DeviceControl device}) : super(device);

  @override
  Intent get intent => Intent.recentCalls;

  @override
  Future<SkillResult> run(NluResult result) async {
    final calls = await device.recentCalls();
    if (calls.isEmpty) return SkillResult.done('Звонков не было');
    final spoken = calls
        .map(
          (c) => switch (c.type) {
            'missed' => 'пропущенный от ${c.name}',
            'outgoing' => 'вы звонили: ${c.name}',
            _ => 'входящий от ${c.name}',
          },
        )
        .join('; ');
    return SkillResult.done('Последние звонки: $spoken');
  }
}

/// «Открой ватсап».
class OpenAppSkill extends _DeviceSkill {
  OpenAppSkill({required DeviceControl device}) : super(device);

  @override
  Intent get intent => Intent.openApp;

  @override
  Future<SkillResult> run(NluResult result) async {
    final name = result.slot(Slot.value);
    if (name == null || name.isEmpty) {
      return SkillResult.failed('Какое приложение открыть?');
    }
    final opened = await device.openApp(name);
    if (opened == null) {
      return SkillResult.failed('Не нашёл приложение «$name»');
    }
    return SkillResult.done('Открываю $opened');
  }
}

/// «5 минут», «1 час 20 минут», «30 секунд».
String spokenDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = seconds % 3600 ~/ 60;
  final s = seconds % 60;
  return [
    if (h > 0) '$h ${_plural(h, 'час', 'часа', 'часов')}',
    if (m > 0) '$m ${_plural(m, 'минуту', 'минуты', 'минут')}',
    if (s > 0) '$s ${_plural(s, 'секунду', 'секунды', 'секунд')}',
  ].join(' ');
}

String _plural(int n, String one, String few, String many) {
  final mod100 = n % 100;
  final mod10 = n % 10;
  if (mod100 >= 11 && mod100 <= 14) return many;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}
