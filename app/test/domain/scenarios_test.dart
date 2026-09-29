import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/domain/dialog/dialog_state.dart';
import 'package:akyl/domain/entities/skill_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Сценарии С1–С8 из ТЗ (раздел 2) как исполняемая спецификация.
/// Если какой-то из этих тестов падает, приложение не соответствует ТЗ —
/// независимо от того, что показывает экран.
void main() {
  group('Сценарии ТЗ', () {
    test('С1: «Позвони маме» — звонит сразу', () async {
      final a = await TestAssistant.build();

      final turn = await a.say('позвони маме');

      expect(a.phone.lastCall, '+99361000001');
      expect(turn.response, 'Звоню Маме');
      expect(turn.status, SkillStatus.done);
      expect(turn.state, DialogState.idle);
    });

    test('С2: «Набери Ахмеда на рабочий» — выбирает рабочий номер', () async {
      final a = await TestAssistant.build();

      final turn = await a.say('набери ахмеда на рабочий');

      expect(a.phone.lastCall, '+99312000002');
      expect(turn.response, 'Звоню Ахмеду, рабочий');
    });

    test(
      'С3: «Напиши Мерет что я опаздываю» — спрашивает подтверждение',
      () async {
        final a = await TestAssistant.build();

        final turn = await a.say('напиши мерет что я опаздываю');

        expect(turn.status, SkillStatus.needsConfirmation);
        expect(turn.response, 'Отправить Мерет: я опаздываю?');
        expect(turn.state, DialogState.awaitingConfirmation);
        // ТЗ, FR-7: до подтверждения ничего не уходит.
        expect(a.phone.sentSms, isEmpty);
      },
    );

    test('С4: «Да» — отправляет SMS', () async {
      final a = await TestAssistant.build();
      await a.say('напиши мерет что я опаздываю');

      final turn = await a.say('да');

      expect(turn.response, 'Отправлено');
      expect(a.phone.sentSms.single.number, '+99361000003');
      expect(a.phone.sentSms.single.text, 'Я опаздываю');
      expect(turn.state, DialogState.idle);
    });

    test('С4b: «Отправь» тоже подтверждает', () async {
      final a = await TestAssistant.build();
      await a.say('напиши мерет что я опаздываю');

      await a.say('отправь');

      expect(a.phone.sentSms, hasLength(1));
    });

    test('С5: два Ахмеда — показывает оба, не звонит', () async {
      final a = await TestAssistant.build(
        contacts: InMemoryContactsSource.twoAhmeds(),
      );

      final turn = await a.say('позвони ахмеду');

      expect(turn.status, SkillStatus.needsChoice);
      expect(turn.state, DialogState.awaitingChoice);
      expect(turn.response, contains('Ахмед Работа'));
      expect(turn.response, contains('Ахмед Брат'));
      expect(a.phone.calls, isEmpty);
    });

    test('С6: «Брату» — звонит выбранному', () async {
      final a = await TestAssistant.build(
        contacts: InMemoryContactsSource.twoAhmeds(),
      );
      await a.say('позвони ахмеду');

      final turn = await a.say('брату');

      expect(a.phone.lastCall, '+99361000003');
      expect(turn.status, SkillStatus.done);
    });

    test('С6b: «Первому» — звонит первому из списка', () async {
      final a = await TestAssistant.build(
        contacts: InMemoryContactsSource.twoAhmeds(),
      );
      final ask = await a.say('позвони ахмеду');
      // Порядок вариантов задаёт сам ответ — проверяем, что «первому»
      // означает именно того, кого назвали первым.
      expect(ask.response, startsWith('Кому звонить: Ахмед Работа'));

      await a.say('первому');

      expect(a.phone.lastCall, '+99361000002');
    });

    test('С7: «Позвони ему ещё раз» — берёт контакт из контекста', () async {
      final a = await TestAssistant.build();
      await a.say('позвони маме');

      final turn = await a.say('позвони ему еще раз');

      expect(a.phone.calls, ['+99361000001', '+99361000001']);
      expect(turn.response, 'Звоню Маме');
    });

    test('С8: непонятная фраза — ничего не выполняет', () async {
      final a = await TestAssistant.build();

      final turn = await a.say('какая сегодня погода в ашхабаде');

      expect(turn.response, 'Не понял. Скажите, например: позвони маме');
      expect(a.phone.calls, isEmpty);
      expect(a.phone.sentSms, isEmpty);
    });
  });

  group('Громкая связь', () {
    test('«позвони пожалуйста маме по громкой связи»', () async {
      final a = await TestAssistant.build();

      final turn = await a.say('позвони пожалуйста маме по громкой связи');

      expect(a.phone.lastCall, '+99361000001');
      expect(a.phone.lastCallOnSpeaker, isTrue);
      expect(turn.response, 'Звоню Маме, по громкой связи');
    });

    test('«набери ахмеда на громкую связь»', () async {
      final a = await TestAssistant.build();

      await a.say('набери ахмеда на громкую связь');

      expect(a.phone.lastCallOnSpeaker, isTrue);
    });

    test('вместе с типом номера', () async {
      final a = await TestAssistant.build();

      final turn = await a.say('набери ахмеда на рабочий по громкой связи');

      expect(a.phone.lastCall, '+99312000002');
      expect(a.phone.lastCallOnSpeaker, isTrue);
      expect(turn.response, 'Звоню Ахмеду, рабочий, по громкой связи');
    });

    test('обычный звонок динамик не включает', () async {
      final a = await TestAssistant.build();

      await a.say('позвони маме');

      expect(a.phone.lastCallOnSpeaker, isFalse);
    });
  });

  group('Вопросы о телефоне', () {
    test('«скажи время»', () async {
      final a = await TestAssistant.build();

      final turn = await a.say('скажи время');

      expect(turn.status, SkillStatus.done);
      expect(turn.response, 'Сейчас 16:45');
    });

    test('«алым который час» — обращение не мешает', () async {
      final a = await TestAssistant.build();

      expect((await a.say('алым который час')).response, 'Сейчас 16:45');
    });

    test('«какое сегодня число»', () async {
      final a = await TestAssistant.build();

      final turn = await a.say('какое сегодня число');

      expect(turn.response, 'Сегодня 28 сентября, понедельник');
    });

    test('«сколько заряда»', () async {
      final a = await TestAssistant.build();

      expect((await a.say('сколько заряда')).response, 'Заряд 73 процентов');
    });

    test('вопрос не требует контакта и не переспрашивает', () async {
      final a = await TestAssistant.build();

      final turn = await a.say('сколько времени');

      expect(turn.state, DialogState.idle);
      expect(a.phone.calls, isEmpty);
    });
  });

  group('Отмена (ТЗ, FR-9)', () {
    test('отменяет отложенную SMS', () async {
      final a = await TestAssistant.build();
      await a.say('напиши мерет что я опаздываю');

      final turn = await a.say('отмена');

      expect(turn.response, 'Отменено');
      expect(a.phone.sentSms, isEmpty);
      expect(a.machine.state, DialogState.idle);
    });

    test('отменяет уточняющий вопрос', () async {
      final a = await TestAssistant.build(
        contacts: InMemoryContactsSource.twoAhmeds(),
      );
      await a.say('позвони ахмеду');

      await a.say('стоп');

      expect(a.machine.context.choices, isEmpty);
      expect(a.phone.calls, isEmpty);
    });

    test('после отмены «да» уже ничего не отправляет', () async {
      final a = await TestAssistant.build();
      await a.say('напиши мерет что я опаздываю');
      await a.say('отмена');

      final turn = await a.say('да');

      expect(a.phone.sentSms, isEmpty);
      expect(turn.status, SkillStatus.failed);
    });
  });

  group('Безопасность SMS (ТЗ, FR-7)', () {
    test(
      'новая команда во время ожидания не считается подтверждением',
      () async {
        final a = await TestAssistant.build();
        await a.say('напиши мерет что я опаздываю');

        // «отправь» здесь — начало новой команды, а не согласие.
        final turn = await a.say('отправь маме что буду поздно');

        expect(turn.status, SkillStatus.needsConfirmation);
        expect(turn.response, 'Отправить Мама: буду поздно?');
        expect(a.phone.sentSms, isEmpty);
      },
    );

    test('без разрешения SMS не уходит', () async {
      final a = await TestAssistant.build(
        phone: FakePhone(permissionsGranted: false),
      );
      await a.say('напиши мерет что я опаздываю');

      final turn = await a.say('да');

      expect(a.phone.sentSms, isEmpty);
      expect(turn.status, SkillStatus.failed);
    });
  });
}
