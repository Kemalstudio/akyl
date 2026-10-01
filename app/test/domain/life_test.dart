import 'package:akyl/data/nlu/life_commands.dart';
import 'package:akyl/data/nlu/turkmen_commands.dart';
import 'package:akyl/domain/entities/intent.dart';
import 'package:akyl/domain/entities/skill_result.dart';
import 'package:akyl/skills/life_skills.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 28, 16, 45);

  group('память', () {
    test('запомнить и найти по другим словам', () async {
      final a = await TestAssistant.build();
      final saved = await a.say('Макс, запомни: ключи от гаража у Ахмеда');
      expect(saved.response, 'Запомнил: ключи от гаража у Ахмеда');

      await a.say('запомни что пароль от вайфая на холодильнике');
      final found = await a.say('где ключи от гаража');
      expect(found.response, contains('ключи от гаража у Ахмеда'));
      expect(found.response, startsWith('Вы говорили сегодня'));
    });

    test('«что ты помнишь» и «забудь»', () async {
      final a = await TestAssistant.build();
      await a.say('запомни машина стоит у третьего подъезда');
      expect((await a.say('что ты помнишь')).response, contains('подъезда'));
      expect(
        (await a.say('забудь про машину')).response,
        'Забыл: машина стоит у третьего подъезда',
      );
      expect(a.memory.notes, isEmpty);
    });

    test('«забудь про…» — не отмена', () async {
      final a = await TestAssistant.build();
      await a.say('запомни ключи в сумке');
      final turn = await a.say('забудь про ключи');
      expect(turn.nlu?.intent, Intent.forget);
    });
  });

  group('напоминания', () {
    test('разбор времени', () {
      String? when(String phrase) =>
          LifeCommands.parse(phrase, now: now)?.slot(Slot.value);
      String? what(String phrase) =>
          LifeCommands.parse(phrase, now: now)?.slot(Slot.message);

      expect(when('напомни через 10 минут позвонить маме'), 'in|600');
      expect(what('напомни через 10 минут позвонить маме'), 'позвонить маме');
      expect(
        when('напоминай каждый день в 9 утра выпить таблетку'),
        'daily|09:00',
      );
      expect(
        what('напоминай каждый день в 9 утра выпить таблетку'),
        'выпить таблетку',
      );
      expect(
        when('напомни в 21:30 выпить лекарство'),
        'once|${DateTime(2026, 9, 28, 21, 30).toIso8601String()}',
      );
      expect(
        when('напомни завтра в 8 про врача'),
        'once|${DateTime(2026, 9, 29, 8).toIso8601String()}',
      );
      expect(what('напомни завтра в 8 про врача'), 'врача');
      expect(when('напомни в 7 вечера полить цветы'), contains('T19:00'));
      // Уже прошло сегодня — значит, завтра.
      expect(when('напомни в 9 утра зарядку'), contains('2026-09-29T09:00'));
    });

    test('поставить, перечислить, удалить', () async {
      final a = await TestAssistant.build();
      final set = await a.say(
        'Макс, напоминай каждый день в 9 утра выпить таблетку',
      );
      expect(set.response, 'Напомню каждый день в 09:00: выпить таблетку');
      await a.say('напомни через 10 минут позвонить маме');
      expect(a.reminders.scheduled, hasLength(2));

      final list = await a.say('какие у меня напоминания');
      expect(list.response, contains('позвонить маме'));
      expect(list.response, contains('выпить таблетку'));

      final removed = await a.say('удали напоминание про таблетку');
      expect(removed.response, 'Удалил напоминание: выпить таблетку');
      expect(a.reminders.scheduled, hasLength(1));
    });

    test('без времени — переспрашивает', () async {
      final a = await TestAssistant.build();
      final turn = await a.say('напомни выпить таблетку');
      expect(turn.status, SkillStatus.failed);
      expect(turn.response, startsWith('Когда напомнить?'));
    });
  });

  group('SOS', () {
    test('без назначенных близких — подсказка, ничего не отправлено', () async {
      final a = await TestAssistant.build();
      final turn = await a.say('помогите');
      expect(turn.status, SkillStatus.failed);
      expect(turn.response, contains('112'));
      expect(a.phone.sentSms, isEmpty);
    });

    test('звонок первому близкому и SMS всем с местом', () async {
      final a = await TestAssistant.build();
      await a.index.rememberRelationship('мама', '1');
      await a.index.rememberRelationship('брат', '3');

      final turn = await a.say('Макс, мне плохо');
      expect(turn.nlu?.intent, Intent.sos);
      expect(a.phone.calls.single, '+99361000001');
      expect(a.phone.sentSms, hasLength(2));
      expect(a.phone.sentSms.first.text, contains('maps.google.com/?q=37.95'));
      expect(turn.response, startsWith('Звоню: Мама'));
    });
  });

  test('когда последний раз звонил', () async {
    final a = await TestAssistant.build();
    a.device.lastCall = (at: DateTime(2026, 9, 23, 18, 5), type: 'outgoing');
    final turn = await a.say('когда я последний раз звонил маме');
    expect(turn.response, contains('Вы звонили: Мама 5 дней назад в 18:05'));
    expect(turn.response, contains('Давно не созванивались'));
  });

  group('туркменский', () {
    test('перевод команд', () {
      expect(TurkmenCommands.toRussian('Ejeme jaň et'), 'позвони ejem');
      expect(TurkmenCommands.toRussian('Kakama jan et'), 'позвони kakam');
      expect(TurkmenCommands.toRussian('Sagat näçe?'), 'который час');
      expect(TurkmenCommands.toRussian('Salam, nähili?'), 'привет как дела');
      expect(TurkmenCommands.toRussian('Fonary ýak'), 'включи фонарик');
      expect(TurkmenCommands.toRussian('Kömek ediň!'), 'помогите');
      expect(
        TurkmenCommands.toRussian('Merede hat ýaz: gijä galýaryn'),
        'напиши Mered что gijä galýaryn',
      );
      expect(TurkmenCommands.toRussian('позвони маме'), isNull);
    });

    test('«Maks, ejeme jaň et» звонит маме', () async {
      final a = await TestAssistant.build();
      final turn = await a.say('Maks, ejeme jaň et');
      expect(turn.nlu?.intent, Intent.call);
      expect(a.phone.calls.single, '+99361000001');
    });

    test('«Sagat näçe» — время', () async {
      final a = await TestAssistant.build();
      expect((await a.say('Sagat näçe')).response, 'Сейчас 16:45');
    });
  });

  test('«назад» вслух', () {
    expect(spokenAgo(DateTime(2026, 9, 28, 1), now), 'сегодня');
    expect(spokenAgo(DateTime(2026, 9, 27), now), 'вчера');
    expect(spokenAgo(DateTime(2026, 9, 14), now), '2 недели назад');
  });
}
