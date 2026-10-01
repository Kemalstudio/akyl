import '../domain/entities/dialog_context.dart';
import '../domain/entities/intent.dart';
import '../domain/entities/nlu_result.dart';
import '../domain/entities/skill_result.dart';
import '../domain/ports/device_info.dart';
import '../domain/ports/skill.dart';

class SmallTalkSkill implements Skill {
  @override
  Intent get intent => Intent.smallTalk;
  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final topic = result.slot(Slot.topic);
    return SkillResult.done(
      (topic ?? '').startsWith('спасибо') || topic == 'благодарю'
          ? 'Пожалуйста! Обращайтесь, я рядом.'
          : 'Спасибо, всё хорошо. Я готов помочь! Могу позвонить близким, написать сообщение или подсказать время.',
    );
  }
}

/// «Скажи время», «который час».
///
/// Первый навык, который ничего не делает с телефоном, а просто отвечает.
/// Ради него не понадобилось трогать ни диспетчер, ни экран: новая команда —
/// новый класс (ТЗ, раздел 5).
class TimeSkill implements Skill {
  TimeSkill({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  Intent get intent => Intent.time;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final now = _clock();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return SkillResult.done('Сейчас $hours:$minutes');
  }
}

/// «Какое сегодня число», «какой сегодня день».
class DateSkill implements Skill {
  DateSkill({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Родительный падеж: «28 сентября», а не «28 сентябрь».
  static const List<String> _months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  static const List<String> _weekdays = [
    'понедельник',
    'вторник',
    'среда',
    'четверг',
    'пятница',
    'суббота',
    'воскресенье',
  ];

  @override
  Intent get intent => Intent.date;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final now = _clock();
    final month = _months[now.month - 1];
    // DateTime.weekday: понедельник = 1.
    final weekday = _weekdays[now.weekday - 1];
    return SkillResult.done('Сегодня ${now.day} $month, $weekday');
  }
}

/// «Сколько заряда», «заряд батареи».
class BatterySkill implements Skill {
  BatterySkill({required DeviceInfo device}) : _device = device;

  final DeviceInfo _device;

  @override
  Intent get intent => Intent.battery;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final level = await _device.batteryLevel();
    if (level == null) {
      return SkillResult.failed('Не удалось узнать заряд');
    }
    final charging = await _device.isCharging();
    final suffix = charging ? ', заряжается' : '';
    return SkillResult.done('Заряд $level процентов$suffix');
  }
}
