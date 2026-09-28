import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/domain/entities/contact.dart';
import 'package:akyl/domain/entities/intent.dart';
import 'package:akyl/domain/entities/skill_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Ветки отказа: именно здесь ассистент не должен «додумывать» и звонить
/// или писать наугад.
void main() {
  group('CallSkill', () {
    test('контакта нет в книге — сообщает и не звонит', () async {
      final a = await TestAssistant.build();

      final turn = await a.say('позвони бердымухамедову');

      expect(turn.status, SkillStatus.failed);
      expect(turn.response, contains('Не нашёл контакт'));
      expect(a.phone.calls, isEmpty);
    });

    test('у контакта нет запрошенного типа номера', () async {
      final a = await TestAssistant.build();

      // У «Мамы» в демо-книге только мобильный.
      final turn = await a.say('позвони маме на рабочий');

      expect(turn.status, SkillStatus.failed);
      expect(turn.response, 'У контакта Мама нет номера «рабочий»');
      expect(a.phone.calls, isEmpty);
    });

    test('без разрешения не звонит', () async {
      final a = await TestAssistant.build(
        phone: FakePhone(permissionsGranted: false),
      );

      final turn = await a.say('позвони маме');

      expect(turn.status, SkillStatus.failed);
      expect(a.phone.calls, isEmpty);
    });

    test('у контакта вообще нет номеров', () async {
      final a = await TestAssistant.build(
        contacts: const InMemoryContactsSource([
          Contact(id: '1', displayName: 'Сапар', phones: []),
        ]),
      );

      final turn = await a.say('позвони сапару');

      expect(turn.status, SkillStatus.failed);
      expect(turn.response, contains('нет номера'));
    });

    test('без типа номера берётся мобильный, а не первый в списке', () async {
      final a = await TestAssistant.build(
        contacts: const InMemoryContactsSource([
          Contact(
            id: '1',
            displayName: 'Сапар',
            phones: [
              PhoneNumber(number: '+993120000', type: PhoneType.work),
              PhoneNumber(number: '+993610000', type: PhoneType.mobile),
            ],
          ),
        ]),
      );

      await a.say('позвони сапару');

      expect(a.phone.lastCall, '+993610000');
    });

    test('«позвони» без имени — вопрос, а не звонок', () async {
      final a = await TestAssistant.build();

      final turn = await a.say('позвони');

      expect(turn.response, 'Кому позвонить?');
      expect(a.phone.calls, isEmpty);
    });
  });

  group('SmsSkill', () {
    test('контакта нет в книге — не спрашивает подтверждение', () async {
      final a = await TestAssistant.build();

      final turn = await a.say('напиши бердымухамедову что я опаздываю');

      expect(turn.status, SkillStatus.failed);
      expect(a.machine.context.pendingAction, isNull);
    });

    test('первая буква сообщения восстанавливается', () async {
      final a = await TestAssistant.build();
      await a.say('напиши маме что буду поздно');

      await a.say('да');

      expect(a.phone.sentSms.single.text, 'Буду поздно');
    });

    test('у контакта нет номера — не отправляет', () async {
      final a = await TestAssistant.build(
        contacts: const InMemoryContactsSource([
          Contact(id: '1', displayName: 'Сапар', phones: []),
        ]),
      );

      final turn = await a.say('напиши сапару что я в пути');

      expect(turn.status, SkillStatus.failed);
      expect(a.phone.sentSms, isEmpty);
    });

    test('уточнение адресата тоже требует подтверждения после выбора', () async {
      final a = await TestAssistant.build(
        contacts: InMemoryContactsSource.twoAhmeds(),
      );

      final ask = await a.say('напиши ахмеду что я опаздываю');
      expect(ask.status, SkillStatus.needsChoice);

      final afterChoice = await a.say('брату');
      expect(afterChoice.status, SkillStatus.needsConfirmation);
      expect(a.phone.sentSms, isEmpty);

      await a.say('да');
      expect(a.phone.sentSms.single.number, '+99361000003');
    });
  });
}
