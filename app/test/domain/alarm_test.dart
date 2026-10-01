import 'package:akyl/domain/entities/intent.dart';
import 'package:akyl/domain/voice/wake_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// «Макс, ставь будильник в 7 утра» — так, как фразу пишет распознаватель:
/// без знаков, числа словами, иногда с неточным именем.
void main() {
  late TestAssistant a;
  final wake = WakeMatcher();

  setUp(() async => a = await TestAssistant.build());

  /// Как в голосовом конвейере: обращение отделяется, команда — в диалог.
  Future<String> say(String heard) async {
    final match = wake.match(heard);
    expect(match, isNotNull, reason: 'не услышал обращение в «$heard»');
    return (await a.say(match!.command)).response;
  }

  group('Будильник голосом', () {
    for (final (heard, alarm) in [
      ('макс ставь будильник в 7 утра', '7:0'),
      ('макс ставь будильник в семь утра', '7:0'),
      ('Макс, поставь будильник на 7 утра', '7:0'),
      ('макс поставь будильник на семь тридцать', '7:30'),
      ('макс разбуди меня в шесть', '6:0'),
      ('макс заведи будильник на 6:45', '6:45'),
      ('макс установи будильник на восемь', '8:0'),
      ('макс поставь будильник на семь вечера', '19:0'),
      ('макс ставь будильник на шесть сорок пять', '6:45'),
      ('макс разбуди меня завтра в семь утра', '7:0'),
      // Неточное имя, как его пишет T-one, перед «ставь» — тоже обращение.
      ('нась ставь будильник в семь утра', '7:0'),
      ('мак поставь будильник на семь', '7:0'),
      // «ставь» после имени T-one режет до «тавь» / «так».
      ('мась тавь будильник в семь утра', '7:0'),
      ('нась так будильник в семь утра', '7:0'),
      // Время по-разговорному.
      ('макс поставь будильник на половину восьмого', '7:30'),
      ('макс поставь будильник на полвосьмого', '7:30'),
      ('макс поставь будильник на четверть восьмого', '7:15'),
      ('макс поставь будильник без четверти восемь', '7:45'),
      ('макс поставь будильник без десяти семь вечера', '18:50'),
    ]) {
      test(heard, () async {
        final response = await say(heard);
        expect(a.device.actions.last, 'alarm $alarm');
        expect(response, startsWith('Будильник на'));
      });
    }

    test('«через 20 минут» — от текущего времени, а не на 20:00', () async {
      // Часы тестов: 16:45.
      final response = await say('макс поставь будильник через 20 минут');
      expect(a.device.actions.last, 'alarm 17:5');
      expect(response, 'Будильник на 17:05');
    });

    test('«через полтора часа»', () async {
      await say('макс поставь будильник через полтора часа');
      expect(a.device.actions.last, 'alarm 18:15');
    });

    test('ответ с двумя цифрами минут', () async {
      final response = await say('макс ставь будильник в 7 утра');
      expect(response, 'Будильник на 07:00');
    });

    test('«Часы» недоступны из фона — будильник ставит помощник и честно '
        'говорит об этом', () async {
      a.device.clockApp = false;
      final response = await say('макс ставь будильник в 7 утра');
      expect(a.device.actions.last, 'alarm 7:0');
      expect(response, 'Будильник на 07:00. Прозвеню сам');
    });

    test('без времени — переспрашивает', () async {
      final turn = await a.say('поставь будильник');
      expect(turn.nlu?.intent, Intent.alarm);
      expect(turn.response, 'На какое время поставить будильник?');
    });
  });
}
