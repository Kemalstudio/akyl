import 'package:akyl/domain/dialog/conversation_titler.dart';
import 'package:akyl/domain/entities/conversation.dart';
import 'package:akyl/domain/entities/intent.dart';
import 'package:akyl/domain/entities/nlu_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

void main() {
  group('Заголовок разговора', () {
    const titler = ConversationTitler();

    test('описывает задачу, а не повторяет фразу', () {
      final title = titler.titleFor(
        const NluResult(
          intent: Intent.call,
          slots: {Slot.contact: 'маме', Slot.speaker: 'true'},
          confidence: 0.95,
        ),
        'позвони пожалуйста маме по громкой связи',
      );

      expect(title, 'Звонок: Маме');
    });

    test('сообщение', () {
      final title = titler.titleFor(
        const NluResult(
          intent: Intent.sms,
          slots: {Slot.contact: 'мерет', Slot.message: 'я опаздываю'},
          confidence: 0.95,
        ),
        'напиши мерет что я опаздываю',
      );

      expect(title, 'Сообщение: Мерет');
    });

    test('вопросы получают свои названия', () {
      const spoken = 'скажи время';
      expect(
        titler.titleFor(
          const NluResult(intent: Intent.time, confidence: 0.97),
          spoken,
        ),
        'Который час',
      );
      expect(
        titler.titleFor(
          const NluResult(intent: Intent.battery, confidence: 0.97),
          'сколько заряда',
        ),
        'Заряд батареи',
      );
    });

    test('непонятая команда: показываем саму фразу', () {
      final title = titler.titleFor(
        NluResult.unknown,
        'какая сегодня погода в ашхабаде',
      );

      expect(title, 'Какая сегодня погода в ашхабаде');
    });

    test('длинный заголовок обрезается по границе слова', () {
      final title = titler.titleFor(
        NluResult.unknown,
        'расскажи мне пожалуйста длинную историю про что угодно',
      );

      expect(title.length, lessThanOrEqualTo(ConversationTitler.maxLength + 1));
      expect(title, endsWith('…'));
      // Обрыв на середине слова читается хуже, чем на пробеле.
      expect(title, isNot(contains('  ')));
    });
  });

  group('История разговоров', () {
    test('первая команда даёт разговору название', () async {
      final store = FakeConversationStore();
      final c = await buildTestController(store: store);

      await c.submit('позвони маме');

      expect(c.current.title, 'Звонок: Маме');
      expect(store.stored, hasLength(1));
      expect(store.stored.first.messages, hasLength(2));
    });

    test('следующие команды название не меняют', () async {
      final c = await buildTestController();

      await c.submit('позвони маме');
      await c.submit('скажи время');

      expect(c.current.title, 'Звонок: Маме');
      expect(c.history, hasLength(4));
    });

    test('новый разговор отделяет историю', () async {
      final store = FakeConversationStore();
      final c = await buildTestController(store: store);

      await c.submit('позвони маме');
      c.startNewConversation();
      await c.submit('скажи время');

      expect(c.history, hasLength(2));
      expect(c.current.title, 'Который час');
      expect(store.stored, hasLength(2));
    });

    test('пустой разговор не плодится', () async {
      final c = await buildTestController();

      c.startNewConversation();
      c.startNewConversation();

      expect(c.conversations, isEmpty);
    });

    test('старый разговор открывается со своими репликами', () async {
      final c = await buildTestController();

      await c.submit('позвони маме');
      final first = c.current.id;
      c.startNewConversation();
      await c.submit('скажи время');

      c.openConversation(first);

      expect(c.current.title, 'Звонок: Маме');
      expect(c.history.first.text, 'позвони маме');
    });

    test('смена разговора забывает контекст', () async {
      final phone = FakePhone();
      final c = await buildTestController(phone: phone);

      await c.submit('позвони маме');
      c.startNewConversation();
      // «ему» в новом разговоре не должно ни на кого указывать.
      await c.submit('позвони ему еще раз');

      expect(phone.calls, hasLength(1));
      expect(c.history.last.text, 'Кому позвонить?');
    });

    test('удаление разговора', () async {
      final store = FakeConversationStore();
      final c = await buildTestController(store: store);

      await c.submit('позвони маме');
      final id = c.current.id;

      await c.deleteConversation(id);

      expect(c.conversations, isEmpty);
      expect(store.stored, isEmpty);
      expect(c.history, isEmpty);
    });

    test('очистка всей истории', () async {
      final store = FakeConversationStore();
      final c = await buildTestController(store: store);

      await c.submit('позвони маме');
      await c.clearAllConversations();

      expect(c.conversations, isEmpty);
      expect(store.cleared, isTrue);
    });

    test('сохранённая история читается при запуске', () async {
      final saved = Conversation(
        id: '1',
        title: 'Звонок: Маме',
        createdAt: DateTime(2026, 9, 27, 10),
        updatedAt: DateTime(2026, 9, 27, 10),
        messages: [
          ChatMessage(
            text: 'позвони маме',
            fromUser: true,
            at: DateTime(2026, 9, 27, 10),
          ),
        ],
      );

      final c = await buildTestController(
        store: FakeConversationStore([saved]),
      );

      expect(c.conversations, hasLength(1));
      expect(c.conversations.first.title, 'Звонок: Маме');
      // Открыт при этом новый пустой разговор, а не вчерашний.
      expect(c.history, isEmpty);
    });

    test('разговор переживает запись и чтение', () {
      final original = Conversation(
        id: '7',
        title: 'Сообщение: Мерет',
        createdAt: DateTime(2026, 9, 28, 12),
        updatedAt: DateTime(2026, 9, 28, 12, 5),
        messages: [
          ChatMessage(
            text: 'напиши мерет что я опаздываю',
            fromUser: true,
            at: DateTime(2026, 9, 28, 12),
          ),
        ],
      );

      final restored = Conversation.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.updatedAt, original.updatedAt);
      expect(restored.messages.single.text, original.messages.single.text);
    });
  });
}
