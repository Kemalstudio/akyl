import '../entities/contact.dart';

/// Разбор ответа на уточняющий вопрос (ТЗ, сценарий С6):
/// «первому», «брату», «работа» -> конкретный вариант из предложенных.
abstract class ChoiceResolver {
  /// null — ответ не опознан ни как номер варианта, ни как имя из списка.
  ContactMatch? resolve(String spokenChoice, List<ContactMatch> choices);
}
