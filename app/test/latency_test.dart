import 'package:akyl/data/contacts/contact_index.dart';
import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/data/nlu/rule_based_nlu.dart';
import 'package:akyl/domain/entities/contact.dart';
import 'package:akyl/domain/entities/dialog_context.dart';
import 'package:akyl/domain/entities/intent.dart';
import 'package:flutter_test/flutter_test.dart';

/// Бюджет задержек из ТЗ (раздел 3): NLU — 20 мс, поиск контакта — 30 мс.
///
/// Тест считает p95 на настольной машине, а не на телефоне, поэтому порог здесь
/// заведомо мягкий: задача — поймать алгоритмическую регрессию (перебор там, где
/// должна быть хеш-таблица), а не подтвердить цифры из ТЗ. Настоящие замеры
/// снимаются на устройстве, см. docs/latency.md.
void main() {
  const iterations = 2000;

  /// Книга размером с реальную: 500 контактов.
  InMemoryContactsSource bigBook() => InMemoryContactsSource([
        for (var i = 0; i < 500; i++)
          Contact(
            id: '$i',
            displayName: '${_names[i % _names.length]} $i',
            phones: [
              PhoneNumber(number: '+9936100$i', type: PhoneType.mobile),
            ],
          ),
        const Contact(
          id: 'mama',
          displayName: 'Мама',
          phones: [PhoneNumber(number: '+99361000001', type: PhoneType.mobile)],
        ),
      ]);

  double p95(List<int> micros) {
    final sorted = [...micros]..sort();
    return sorted[(sorted.length * 0.95).floor()] / 1000;
  }

  test('NLU: p95 разбора фразы', () async {
    final nlu = RuleBasedNlu();
    final ctx = DialogContext();
    final samples = <int>[];

    // Прогрев: первый вызов платит за ленивую инициализацию регулярок.
    for (var i = 0; i < 100; i++) {
      await nlu.parse('позвони маме', ctx);
    }

    for (var i = 0; i < iterations; i++) {
      final sw = Stopwatch()..start();
      await nlu.parse('напиши мерет что я сегодня опаздываю на работу', ctx);
      samples.add(sw.elapsedMicroseconds);
    }

    final value = p95(samples);
    printOnFailure('NLU p95 = ${value.toStringAsFixed(3)} мс');
    expect(value, lessThan(5.0));
  });

  test('Поиск контакта в книге из 500 записей: p95', () async {
    final index = ContactIndex(bigBook());
    await index.buildIndex();

    final samples = <int>[];
    for (var i = 0; i < iterations; i++) {
      final sw = Stopwatch()..start();
      await index.resolve('маме');
      samples.add(sw.elapsedMicroseconds);
    }

    final value = p95(samples);
    printOnFailure('Поиск контакта p95 = ${value.toStringAsFixed(3)} мс');
    expect(value, lessThan(10.0));
  });

  test('Промах по индексу не срывает бюджет', () async {
    final index = ContactIndex(bigBook());
    await index.buildIndex();

    final samples = <int>[];
    for (var i = 0; i < 200; i++) {
      final sw = Stopwatch()..start();
      // Такого имени нет: включается полный перебор с Jaro-Winkler —
      // самый дорогой путь в модуле.
      await index.resolve('несуществующее имя контакта');
      samples.add(sw.elapsedMicroseconds);
    }

    final value = p95(samples);
    printOnFailure('Перебор Jaro-Winkler p95 = ${value.toStringAsFixed(3)} мс');
    expect(value, lessThan(60.0));
  });

  test('Построение индекса при запуске', () async {
    final index = ContactIndex(bigBook());

    final sw = Stopwatch()..start();
    await index.buildIndex();
    final ms = sw.elapsedMilliseconds;

    printOnFailure('Построение индекса на 500 контактов = $ms мс');
    // Строится один раз при запуске, вне бюджета команды, но не должно
    // задерживать первый экран.
    expect(ms, lessThan(500));
  });
}

const _names = [
  'Ахмед', 'Мерет', 'Гурбан', 'Ольга', 'Мария', 'Сергей', 'Айна', 'Бахтияр',
  'Джумагуль', 'Нурмухаммет', 'Михаил', 'Екатерина', 'Огулджан', 'Сапар',
];
