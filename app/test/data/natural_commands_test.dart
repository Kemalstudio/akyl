import 'package:akyl/data/contacts/contact_index.dart';
import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/data/contacts/morphology.dart';
import 'package:akyl/data/nlu/rule_based_nlu.dart';
import 'package:akyl/domain/entities/contact.dart';
import 'package:akyl/domain/entities/dialog_context.dart';
import 'package:akyl/domain/entities/intent.dart';
import 'package:akyl/domain/ports/contact_alias_store.dart';
import 'package:akyl/skills/contact_lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';

class _MemoryAliases implements ContactAliasStore {
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> load() async => {...values};
  @override
  Future<void> save(Map<String, String> aliases) async {
    values = {...aliases};
  }
}

Contact person(String id, String name) => Contact(
  id: id,
  displayName: name,
  phones: [PhoneNumber(number: '+100$id', type: PhoneType.mobile)],
);

void main() {
  final nlu = RuleBasedNlu();
  group('Естественные команды', () {
    for (final phrase in [
      'Макс, напиши этому человеку сообщение Привет, как дела?',
      'напиши сообщение этому человеку вот это сообщение Привет, как дела?',
      'напиши этому человеку вот это сообщение Привет, как дела?',
      'напиши этому человеку это сообщение Привет, как дела?',
    ]) {
      test(phrase, () async {
        final ctx = DialogContext()..rememberContact(person('1', 'Ejemjan'));
        final result = await nlu.parse(phrase, ctx);
        expect(result.intent, Intent.sms);
        expect(result.slot(Slot.contact), 'Ejemjan');
        expect(result.slot(Slot.message), 'Привет, как дела?');
      });
    }

    test('без адресата просит уточнение и сохраняет текст', () async {
      final result = await nlu.parse(
        'напиши этому человеку сообщение привет',
        DialogContext(),
      );
      expect(result.slot(Slot.contact), isNull);
      expect(result.slot(Slot.message), 'привет');
    });
    test('сохраняет ё и служебные слова внутри сообщения', () async {
      final result = await nlu.parse(
        'напиши маме что Сообщение ещё не пришло!',
        DialogContext(),
      );
      expect(result.slot(Slot.message), 'Сообщение ещё не пришло!');
    });
    test('более позднее что не обрезает начало текста', () async {
      final result = await nlu.parse(
        'напиши маме сообщение Я знаю что ты дома',
        DialogContext(),
      );
      expect(result.slot(Slot.message), 'Я знаю что ты дома');
    });
    test('полное имя перед разделителем', () async {
      final result = await nlu.parse(
        'отправь сообщение для Ахмеда Работа о том что буду поздно',
        DialogContext(),
      );
      expect(result.slot(Slot.contact), 'ахмеда работа');
      expect(result.slot(Slot.message), 'буду поздно');
    });
    test('вопрос в SMS остаётся текстом SMS', () async {
      final result = await nlu.parse(
        'напиши маме сообщение какое сегодня число',
        DialogContext(),
      );
      expect(result.intent, Intent.sms);
      expect(result.slot(Slot.message), 'какое сегодня число');
    });
    test('обращение и громкая связь', () async {
      final result = await nlu.parse(
        'Макс, звони маме на громкой связи',
        DialogContext(),
      );
      expect(result.intent, Intent.call);
      expect(result.slot(Slot.contact), 'маме');
      expect(result.slot(Slot.speaker), 'true');
    });
    test('имя Макс в тексте не вырезается', () async {
      final result = await nlu.parse(
        'напиши маме сообщение Макс уже дома',
        DialogContext(),
      );
      expect(result.slot(Slot.message), 'Макс уже дома');
    });
    for (final entry in {
      'Макс, какое сегодня число?': Intent.date,
      'Макс, как дела, скажи время': Intent.time,
      'Макс скажи время пожалуйста': Intent.time,
      'Макс как дела': Intent.smallTalk,
    }.entries) {
      test(entry.key, () async {
        expect(
          (await nlu.parse(entry.key, DialogContext())).intent,
          entry.value,
        );
      });
    }
  });

  group('Семейные контакты и память', () {
    test('мама находится как Ejemjan, папа как Kakamjan', () async {
      final index = ContactIndex(
        InMemoryContactsSource([
          person('1', 'Ejemjan ❤️'),
          person('2', 'Kakamjan'),
          person('3', 'Марат'),
        ]),
      );
      await index.buildIndex();
      expect((await index.resolve('маме')).first.contact.id, '1');
      expect((await index.resolve('папе')).first.contact.id, '2');
      expect((await index.resolve('эжемжан')).first.contact.id, '1');
    });
    test('несколько родственников требуют выбора', () async {
      final index = ContactIndex(
        InMemoryContactsSource([person('1', 'Мама'), person('2', 'Ejemjan')]),
      );
      await index.buildIndex();
      expect(await lookupContact(index, 'маме'), isA<LookupAmbiguous>());
    });
    test(
      'назначение сохраняется при пересоздании индекса и сбрасывается',
      () async {
        final store = _MemoryAliases();
        final source = InMemoryContactsSource([
          person('1', 'Айна'),
          person('2', 'Ejemjan'),
        ]);
        final index = ContactIndex(source, aliasStore: store);
        await index.buildIndex();
        await index.rememberRelationship('мама', '1');
        final restarted = ContactIndex(source, aliasStore: store);
        await restarted.buildIndex();
        expect((await restarted.resolve('маме')).single.contact.id, '1');
        await restarted.rememberRelationship('мама', null);
        expect((await restarted.resolve('маме')).single.contact.id, '2');
      },
    );
    test('удалённого родственника не заменяет другим человеком', () async {
      final store = _MemoryAliases()..values = {'мама': 'deleted'};
      final index = ContactIndex(
        InMemoryContactsSource([person('2', 'Ejemjan')]),
        aliasStore: store,
      );
      await index.buildIndex();
      expect(await index.resolve('маме'), isEmpty);
    });
    test('не угадывает папу по случайному имени', () async {
      final index = ContactIndex(
        InMemoryContactsSource([person('3', 'Марат')]),
      );
      await index.buildIndex();
      expect(await index.resolve('папе'), isEmpty);
    });
    test('сохраняет туркменские буквы', () {
      expect(RussianMorphology.normalize('Gülşat Ýagmyr'), 'gülşat ýagmyr');
    });
  });

  group('Целые диалоги', () {
    test('звонок, затем SMS этому человеку без служебных слов', () async {
      final assistant = await TestAssistant.build(
        contacts: InMemoryContactsSource([person('1', 'Ejemjan')]),
      );
      await assistant.machine.handle('Макс позвони маме по громкой связи');
      expect(assistant.phone.lastCallOnSpeaker, isTrue);
      await assistant.machine.handle(
        'напиши этому человеку сообщение Привет, как дела?',
      );
      expect(assistant.phone.sentSms, isEmpty);
      await assistant.machine.handle('да');
      expect(assistant.phone.sentSms.single.text, 'Привет, как дела?');
      expect(assistant.phone.sentSms.single.number, '+1001');
    });
    test('выбор второго человека с одинаковым именем', () async {
      final assistant = await TestAssistant.build(
        contacts: InMemoryContactsSource([
          person('1', 'Ахмед'),
          person('2', 'Ахмед'),
        ]),
      );
      await assistant.machine.handle('позвони ахмеду');
      await assistant.machine.handle('второму');
      expect(assistant.phone.calls, ['+1002']);
    });
    test('новая команда отменяет прежнее подтверждение SMS', () async {
      final assistant = await TestAssistant.build();
      await assistant.machine.handle('напиши маме что привет');
      await assistant.machine.handle('скажи время');
      await assistant.machine.handle('да');
      expect(assistant.phone.sentSms, isEmpty);
    });
  });
}
