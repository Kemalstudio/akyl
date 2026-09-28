import '../../domain/entities/contact.dart';
import '../../domain/entities/intent.dart';
import '../../domain/ports/contacts_source.dart';

/// Контакты в памяти: тесты и запуск без адресной книги.
class InMemoryContactsSource implements ContactsSource {
  const InMemoryContactsSource(this.contacts);

  final List<Contact> contacts;

  @override
  Future<List<Contact>> loadAll() async => contacts;

  /// Книга под сценарии С1–С4 и С7: все имена однозначны.
  /// «Gurban» записан латиницей намеренно — так проверяется транслитерация.
  factory InMemoryContactsSource.demo() => InMemoryContactsSource(const [
        Contact(
          id: '1',
          displayName: 'Мама',
          phones: [PhoneNumber(number: '+99361000001', type: PhoneType.mobile)],
        ),
        Contact(
          id: '2',
          displayName: 'Ахмед',
          phones: [
            PhoneNumber(number: '+99361000002', type: PhoneType.mobile),
            PhoneNumber(number: '+99312000002', type: PhoneType.work),
          ],
        ),
        Contact(
          id: '3',
          displayName: 'Мерет',
          phones: [PhoneNumber(number: '+99361000003', type: PhoneType.mobile)],
        ),
        Contact(
          id: '4',
          displayName: 'Ольга',
          phones: [
            PhoneNumber(number: '+99361000004', type: PhoneType.mobile),
            PhoneNumber(number: '+99312000004', type: PhoneType.home),
          ],
        ),
        Contact(
          id: '5',
          displayName: 'Gurban',
          phones: [PhoneNumber(number: '+99361000005', type: PhoneType.mobile)],
        ),
      ]);

  /// Книга под сценарии С5–С6: два Ахмеда, команда «позвони Ахмеду»
  /// обязана вызвать уточнение, а не звонок.
  factory InMemoryContactsSource.twoAhmeds() => InMemoryContactsSource(const [
        Contact(
          id: '1',
          displayName: 'Мама',
          phones: [PhoneNumber(number: '+99361000001', type: PhoneType.mobile)],
        ),
        Contact(
          id: '2',
          displayName: 'Ахмед Работа',
          phones: [
            PhoneNumber(number: '+99361000002', type: PhoneType.mobile),
            PhoneNumber(number: '+99312000002', type: PhoneType.work),
          ],
        ),
        Contact(
          id: '3',
          displayName: 'Ахмед Брат',
          phones: [PhoneNumber(number: '+99361000003', type: PhoneType.mobile)],
        ),
      ]);
}
