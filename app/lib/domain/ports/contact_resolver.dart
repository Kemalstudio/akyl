import '../entities/contact.dart';

/// Поиск контакта по произнесённому имени (ТЗ, FR-5).
/// Не нейросеть: падежи + уменьшительные + транслитерация + Jaro-Winkler.
abstract class ContactResolver {
  /// Построить индекс. Вызывается при запуске и при изменении адресной книги.
  Future<void> buildIndex();

  /// Совпадения, отсортированные по убыванию score.
  Future<List<ContactMatch>> resolve(String spokenName);
}
