import 'package:akyl/domain/entities/intent.dart';
import 'package:akyl/skills/utility_skills.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Калькулятор, музыка, заряд и честный ответ про интернет — так, как фразы
/// приходят от распознавателя: без знаков, числа словами.
void main() {
  late TestAssistant a;
  setUp(() async => a = await TestAssistant.build());

  group('Калькулятор', () {
    for (final (phrase, answer) in [
      ('сколько будет двадцать пять умножить на четыре', '— 100'),
      ('сколько будет 25 умножить на 4', '— 100'),
      ('посчитай сто двадцать плюс тридцать пять', '— 155'),
      ('сколько будет десять разделить на четыре', '— 2,5'),
      ('сколько будет пятнадцать процентов от двухсот', '— 30'),
      ('сколько будет пятнадцать процентов от двести', '— 30'),
      ('сколько будет две тысячи минус триста', '— 1700'),
      ('сколько будет семь на восемь', '— 56'),
    ]) {
      test(phrase, () async {
        final turn = await a.say(phrase);
        expect(turn.nlu?.intent, Intent.calculate);
        expect(turn.response, endsWith(answer));
      });
    }

    test('на ноль делить нельзя', () async {
      final turn = await a.say('сколько будет пять разделить на ноль');
      expect(turn.response, 'На ноль делить нельзя');
    });

    test('числа, похожие на команды, не считаются примером', () async {
      final turn = await a.say('поставь будильник на семь');
      expect(turn.nlu?.intent, Intent.alarm);
    });

    test('формат ответа', () {
      expect(CalculatorSkill.format(100), '100');
      expect(CalculatorSkill.format(2.5), '2,5');
      expect(CalculatorSkill.format(1 / 3), '0,3333');
    });
  });

  group('Музыка', () {
    for (final (phrase, action) in [
      ('следующий трек', 'next'),
      ('следующая песня', 'next'),
      ('предыдущий трек', 'previous'),
      ('поставь на паузу', 'pause'),
      ('пауза', 'pause'),
      ('останови музыку', 'pause'),
      ('включи музыку', 'play'),
      ('продолжи музыку', 'play'),
    ]) {
      test(phrase, () async {
        final turn = await a.say(phrase);
        expect(turn.nlu?.intent, Intent.media);
        expect(a.device.actions.last, 'media $action');
      });
    }
  });

  test('заряд разными словами', () async {
    for (final phrase in [
      'сколько процентов батареи',
      'какой заряд',
      'проверь аккумулятор',
    ]) {
      final turn = await a.say(phrase);
      expect(turn.nlu?.intent, Intent.battery, reason: phrase);
    }
  });

  test('погода без интернета — честный ответ, а не «не понял»', () async {
    final turn = await a.say('какая сегодня погода');
    expect(turn.nlu?.intent, Intent.needsInternet);
    expect(turn.response, contains('без интернета'));
  });
}
