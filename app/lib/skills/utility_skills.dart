import '../domain/entities/dialog_context.dart';
import '../domain/entities/intent.dart';
import '../domain/entities/nlu_result.dart';
import '../domain/entities/skill_result.dart';
import '../domain/ports/device_control.dart';
import '../domain/ports/skill.dart';

/// «Сколько будет двадцать пять умножить на четыре» — «100».
class CalculatorSkill implements Skill {
  @override
  Intent get intent => Intent.calculate;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final parts = (result.slot(Slot.value) ?? '').split('|');
    if (parts.length != 3) {
      return SkillResult.failed(
        'Не понял пример. Скажите, например: сколько будет 25 умножить на 4',
      );
    }
    final a = num.parse(parts[0]);
    final op = parts[1];
    final b = num.parse(parts[2]);
    final num value;
    switch (op) {
      case '+':
        value = a + b;
      case '-':
        value = a - b;
      case '*':
        value = a * b;
      case '/':
        if (b == 0) return SkillResult.failed('На ноль делить нельзя');
        value = a / b;
      case '%':
        value = a * b / 100;
      default:
        return SkillResult.failed('Не понял действие');
    }
    final words = switch (op) {
      '+' => 'плюс',
      '-' => 'минус',
      '*' => 'умножить на',
      '/' => 'разделить на',
      _ => 'процентов от',
    };
    return SkillResult.done(
      '${format(a)} $words ${format(b)} — ${format(value)}',
    );
  }

  /// Целое — без дробной части, дробное — до четырёх знаков, через запятую.
  static String format(num v) {
    if (v == v.roundToDouble()) return v.round().toString();
    var s = v.toStringAsFixed(4);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s.replaceAll('.', ',');
  }
}

/// «Пауза», «следующий трек» — кнопки плеера голосом.
class MediaSkill implements Skill {
  MediaSkill({required DeviceControl device}) : _device = device;

  final DeviceControl _device;

  @override
  Intent get intent => Intent.media;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final action = result.slot(Slot.value) ?? 'play';
    try {
      await _device.media(action);
    } on DeviceControlError catch (e) {
      return SkillResult.failed(e.message);
    }
    return SkillResult.done(switch (action) {
      'pause' => 'Пауза',
      'next' => 'Следующий трек',
      'previous' => 'Предыдущий трек',
      _ => 'Продолжаю',
    });
  }
}

/// Погода, новости, поиск — честно: без интернета не узнать.
class InternetOnlySkill implements Skill {
  @override
  Intent get intent => Intent.needsInternet;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final what = switch (result.slot(Slot.value)) {
      'weather' => 'Погоду',
      'news' => 'Новости',
      'rates' => 'Курс валют',
      'traffic' => 'Пробки',
      _ => 'Это',
    };
    return SkillResult.failed(
      '$what без интернета не узнать: я работаю полностью на телефоне. '
      'Могу позвонить, написать, напомнить или посчитать.',
    );
  }
}
