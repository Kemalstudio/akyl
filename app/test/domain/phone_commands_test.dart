import 'package:akyl/data/contacts/family_names.dart';
import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/data/nlu/device_commands.dart';
import 'package:akyl/domain/dialog/dialog_state.dart';
import 'package:akyl/domain/entities/intent.dart';
import 'package:akyl/domain/entities/skill_result.dart';
import 'package:akyl/skills/phone_control_skills.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('разбор команд телефона', () {
    void expectCommand(String phrase, Intent intent, [String? value]) {
      final r = DeviceCommands.parse(phrase);
      expect(r?.intent, intent, reason: phrase);
      if (value != null) expect(r!.slot(Slot.value), value, reason: phrase);
    }

    test('будильник', () {
      expectCommand('поставь будильник на 7:30', Intent.alarm, '07:30');
      expectCommand('заведи будильник на 6 утра', Intent.alarm, '06:00');
      expectCommand('будильник на семь тридцать', Intent.alarm, '07:30');
      expectCommand('разбуди меня в 8 вечера', Intent.alarm, '20:00');
      expectCommand(
        'поставь будильник на 7 часов 15 минут',
        Intent.alarm,
        '07:15',
      );
    });

    test('таймер', () {
      expectCommand('поставь таймер на 5 минут', Intent.timer, '300');
      expectCommand('таймер на полчаса', Intent.timer, '1800');
      expectCommand('засеки 1 час 20 минут', Intent.timer, '4800');
      expectCommand('таймер на тридцать секунд', Intent.timer, '30');
      expectCommand('поставь таймер на минуту', Intent.timer, '60');
    });

    test('фонарик и громкость', () {
      expectCommand('включи фонарик', Intent.flashlight, 'on');
      expectCommand('выключи фонарик', Intent.flashlight, 'off');
      expectCommand('сделай громче', Intent.volume, 'up');
      expectCommand('потише пожалуйста', Intent.volume, 'down');
      expectCommand('выключи звук', Intent.volume, 'mute');
      expectCommand('включи звук', Intent.volume, 'unmute');
      expectCommand('громкость на максимум', Intent.volume, 'max');
      expect(DeviceCommands.parse('позвони маме по громкой связи'), isNull);
    });

    test('SMS, звонки, приложения', () {
      expectCommand('прочитай последнее сообщение', Intent.readSms);
      expectCommand('кто мне написал', Intent.readSms);
      expectCommand('кто звонил', Intent.recentCalls);
      expectCommand('пропущенные звонки', Intent.recentCalls);
      expectCommand('открой ватсап', Intent.openApp, 'whatsapp|ватсап');
      expectCommand('запусти камеру', Intent.openApp, 'camera|камеру');
    });
  });

  group('навыки через диалог', () {
    test('будильник и таймер доходят до телефона', () async {
      final a = await TestAssistant.build();
      expect(
        (await a.say('Макс, поставь будильник на 7:30')).response,
        'Будильник на 07:30',
      );
      expect(
        (await a.say('поставь таймер на 5 минут')).response,
        'Таймер на 5 минут',
      );
      expect(a.device.actions, ['alarm 7:30', 'timer 300']);
    });

    test('чтение SMS и звонков', () async {
      final a = await TestAssistant.build();
      expect(
        (await a.say('прочитай последнее смс')).response,
        'Сообщение от Мама: Позвони мне',
      );
      expect(
        (await a.say('кто звонил')).response,
        'Последние звонки: пропущенный от Мама; входящий от Ахмед',
      );
    });

    test('незнакомое приложение — честный отказ', () async {
      final a = await TestAssistant.build();
      expect((await a.say('открой ватсап')).response, 'Открываю WhatsApp');
      final turn = await a.say('открой абракадабру');
      expect(turn.status, SkillStatus.failed);
    });
  });

  group('повтор и поправка', () {
    test('«повтори» говорит последний ответ', () async {
      final a = await TestAssistant.build();
      await a.say('который час');
      expect((await a.say('повтори')).response, 'Сейчас 16:45');
    });

    test('«повтори» не сбивает ожидание подтверждения', () async {
      final a = await TestAssistant.build();
      final ask = await a.say('напиши мерет что я опаздываю');
      final again = await a.say('повтори');
      expect(again.response, ask.response);
      expect(a.machine.state, DialogState.awaitingConfirmation);
    });

    test('«нет, не ему, а …» перезванивает другому', () async {
      final a = await TestAssistant.build();
      await a.say('позвони маме');
      final turn = await a.say('нет не ей а мерет');
      expect(turn.response, contains('Мерет'));
      expect(a.phone.calls.last, '+99361000003');
    });

    test('поправка адресата SMS снова спрашивает подтверждение', () async {
      final a = await TestAssistant.build();
      await a.say('напиши мерет что я опаздываю');
      final turn = await a.say('нет, маме');
      expect(turn.status, SkillStatus.needsConfirmation);
      expect(turn.response, contains('Мам'));
      expect(a.phone.sentSms, isEmpty);
      await a.say('да');
      expect(a.phone.sentSms.single.number, '+99361000001');
    });

    test('«нет, не надо» — по-прежнему отмена', () async {
      final a = await TestAssistant.build();
      await a.say('напиши мерет что я опаздываю');
      await a.say('нет не надо');
      expect(a.machine.state, DialogState.idle);
      expect(a.phone.sentSms, isEmpty);
    });

    test('поправка при выборе из двух Ахмедов', () async {
      final a = await TestAssistant.build(
        contacts: InMemoryContactsSource.twoAhmeds(),
      );
      await a.say('позвони ахмеду');
      await a.say('нет не ахмеду а маме');
      expect(a.phone.calls.last, '+99361000001');
    });
  });

  test('роли близких узнаются в любом падеже', () {
    expect(FamilyNames.roleOf('брату'), 'брат');
    expect(FamilyNames.roleOf('сестренке'), 'сестра');
    expect(FamilyNames.roleOf('бабушке'), 'бабушка');
    expect(FamilyNames.roleOf('agam'), 'брат');
    expect(FamilyNames.roleOf('ахмеду'), isNull);
  });

  test('длительность вслух', () {
    expect(spokenDuration(60), '1 минуту');
    expect(spokenDuration(4800), '1 час 20 минут');
    expect(spokenDuration(125), '2 минуты 5 секунд');
  });

  test('приветствие вместе с вопросом — это разговор', () async {
    final a = await TestAssistant.build();
    for (final phrase in [
      'привет как дела',
      'Привет, как дела?',
      'здравствуйте',
      'добрый день как ты',
      'как у тебя дела',
    ]) {
      final turn = await a.say(phrase);
      expect(turn.status, SkillStatus.done, reason: phrase);
      expect(turn.response, contains('хорошо'), reason: phrase);
    }
    expect((await a.say('спасибо большое')).response, contains('Пожалуйста'));
  });
}
