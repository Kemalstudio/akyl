import '../entities/contact.dart';

/// Сырая адресная книга устройства. Индекс для поиска строится поверх.
abstract class ContactsSource {
  Future<List<Contact>> loadAll();
}
