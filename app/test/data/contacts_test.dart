import 'package:akyl/data/contacts/contact_index.dart';
import 'package:akyl/data/contacts/diminutives.dart';
import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/data/contacts/morphology.dart';
import 'package:akyl/data/contacts/similarity.dart';
import 'package:akyl/data/contacts/spoken_choice_resolver.dart';
import 'package:akyl/data/contacts/transliteration.dart';
import 'package:akyl/domain/entities/contact.dart';
import 'package:akyl/domain/entities/intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Падежи (ТЗ, FR-5)', () {
    const m = RussianMorphology();

    test('женское имя на -а', () {
      expect(m.inflections('мама'), containsAll(['мама', 'мамы', 'маме', 'маму']));
    });

    test('мужское имя на согласную', () {
      expect(
        m.inflections('ахмед'),
        containsAll(['ахмед', 'ахмеда', 'ахмеду', 'ахмедом', 'ахмеде']),
      );
    });

    test('после шипящей в родительном пишется и, а не ы', () {
      expect(m.inflections('маша'), contains('маши'));
      expect(m.inflections('маша'), isNot(contains('машы')));
    });

    test('имя на -й склоняется мягко', () {
      expect(m.inflections('андрей'), containsAll(['андрея', 'андрею', 'андреем']));
    });

    test('несклоняемое имя остаётся как есть', () {
      expect(m.inflections('мери'), equals({'мери'}));
    });

    test('дательный падеж для ответа вслух', () {
      expect(m.dative('Мама'), 'Маме');
      expect(m.dative('Ахмед'), 'Ахмеду');
      expect(m.dative('Андрей'), 'Андрею');
      expect(m.dative('Ольга'), 'Ольге');
      expect(m.dative('Мери'), 'Мери');
    });

    test('дательный падеж по каждому слову составного имени', () {
      expect(m.dative('Ахмед Брат'), 'Ахмеду Брату');
    });

    test('нормализация убирает регистр, ё и пунктуацию', () {
      expect(RussianMorphology.normalize('Алёша, привет!'), 'алеша привет');
    });
  });

  group('Транслитерация (ТЗ, FR-5)', () {
    test('латиница в кириллицу', () {
      expect(Transliteration.latinToCyrillic('Ahmet'), 'ахмет');
      expect(Transliteration.latinToCyrillic('Meret'), 'мерет');
      expect(Transliteration.latinToCyrillic('Shohrat'), 'шохрат');
    });

    test('Ahmet и Ахмед дают один фонетический ключ', () {
      expect(
        Transliteration.phoneticKey('Ahmet'),
        Transliteration.phoneticKey('Ахмед'),
      );
    });

    test('двойные согласные не меняют ключ', () {
      expect(
        Transliteration.phoneticKey('Анна'),
        Transliteration.phoneticKey('Ана'),
      );
    });

    test('разные имена дают разные ключи', () {
      expect(
        Transliteration.phoneticKey('Ахмед'),
        isNot(Transliteration.phoneticKey('Мерет')),
      );
    });
  });

  group('Jaro-Winkler', () {
    test('одинаковые строки', () {
      expect(Similarity.jaroWinkler('ахмед', 'ахмед'), 1.0);
    });

    test('одна ошибка в конце имени почти не снижает оценку', () {
      expect(Similarity.jaroWinkler('ахмед', 'ахмеб'), greaterThan(0.9));
    });

    test('разные имена оцениваются низко', () {
      expect(Similarity.jaroWinkler('ахмед', 'ольга'), lessThan(0.5));
    });
  });

  group('Уменьшительные формы', () {
    test('полное имя разворачивается в краткие', () {
      expect(Diminutives.variantsOf('александр'), contains('саша'));
    });

    test('краткая форма находит полные имена', () {
      expect(Diminutives.expandsTo('саша'), containsAll(['александр', 'александра']));
    });
  });

  group('Поиск контакта (ТЗ, FR-5)', () {
    late ContactIndex index;

    setUp(() async {
      index = ContactIndex(InMemoryContactsSource.demo());
      await index.buildIndex();
    });

    Future<ContactMatch?> top(String spoken) async {
      final r = await index.resolve(spoken);
      return r.isEmpty ? null : r.first;
    }

    test('точное имя', () async {
      expect((await top('ахмед'))?.contact.displayName, 'Ахмед');
    });

    test('падежная форма: маме -> Мама', () async {
      final m = await top('маме');
      expect(m?.contact.displayName, 'Мама');
      expect(m!.score, greaterThanOrEqualTo(0.85));
    });

    test('ласковая форма: мамуле -> Мама', () async {
      expect((await top('мамуле'))?.contact.displayName, 'Мама');
    });

    test('латиница в книге, кириллица в речи: гурбану -> Gurban', () async {
      expect((await top('гурбану'))?.contact.displayName, 'Gurban');
    });

    test('ошибка распознавания добирается нечётким сравнением', () async {
      // «олге» — потерянный мягкий знак, типичная ошибка STT.
      expect((await top('олге'))?.contact.displayName, 'Ольга');
    });

    test('незнакомое имя не находится', () async {
      expect(await index.resolve('бердымухамедов'), isEmpty);
    });

    test('два Ахмеда возвращаются оба', () async {
      final ambiguous = ContactIndex(InMemoryContactsSource.twoAhmeds());
      await ambiguous.buildIndex();

      final matches = await ambiguous.resolve('ахмеду');

      expect(matches, hasLength(2));
      expect(matches[0].score, matches[1].score); // разрыва нет — нужен выбор
    });

    test('совпадения отсортированы по убыванию оценки', () async {
      final matches = await index.resolve('ахмед');
      for (var i = 1; i < matches.length; i++) {
        expect(matches[i - 1].score, greaterThanOrEqualTo(matches[i].score));
      }
    });
  });

  group('Выбор из списка (ТЗ, сценарий С6)', () {
    const resolver = SpokenChoiceResolver();

    final choices = [
      const ContactMatch(
        contact: Contact(
          id: '2',
          displayName: 'Ахмед Работа',
          phones: [PhoneNumber(number: '1', type: PhoneType.mobile)],
        ),
        score: 0.97,
        matchedVia: MatchKind.morphology,
      ),
      const ContactMatch(
        contact: Contact(
          id: '3',
          displayName: 'Ахмед Брат',
          phones: [PhoneNumber(number: '2', type: PhoneType.mobile)],
        ),
        score: 0.97,
        matchedVia: MatchKind.morphology,
      ),
    ];

    test('по номеру варианта', () {
      expect(resolver.resolve('первому', choices)?.contact.id, '2');
      expect(resolver.resolve('второму', choices)?.contact.id, '3');
    });

    test('по слову из названия, в падеже', () {
      expect(resolver.resolve('брату', choices)?.contact.id, '3');
      expect(resolver.resolve('работа', choices)?.contact.id, '2');
    });

    test('номер за пределами списка не выбирается', () {
      expect(resolver.resolve('пятому', choices), isNull);
    });

    test('посторонний ответ не выбирает ничего', () {
      expect(resolver.resolve('ольге', choices), isNull);
    });
  });
}
