import '../domain/entities/contact.dart';
import '../domain/entities/nlu_result.dart';
import '../domain/ports/contact_resolver.dart';

/// Итог поиска контакта — общий для звонка и SMS.
sealed class Lookup {
  const Lookup();
}

/// Один контакт, уверенность выше порога — можно действовать (ТЗ, FR-6).
class LookupFound extends Lookup {
  const LookupFound(this.match);

  final ContactMatch match;
}

/// Несколько подходящих или уверенность ниже порога — нужно уточнить.
class LookupAmbiguous extends Lookup {
  const LookupAmbiguous(this.matches);

  final List<ContactMatch> matches;
}

/// В адресной книге такого нет.
class LookupNotFound extends Lookup {
  const LookupNotFound(this.spokenName);

  final String spokenName;
}

/// Сколько вариантов максимум предлагать вслух: больше трёх человек
/// на слух не удержит.
const int kMaxSpokenChoices = 3;

/// Насколько лидер должен опережать второго, чтобы считаться однозначным.
/// Два «Ахмеда» дают одинаковый score, разрыв нулевой — будет уточнение.
const double kAmbiguityMargin = 0.06;

/// Единое правило выбора контакта для всех навыков (ТЗ, FR-5, FR-6).
Future<Lookup> lookupContact(
  ContactResolver resolver,
  String spokenName,
) async {
  final matches = await resolver.resolve(spokenName);
  if (matches.isEmpty) return LookupNotFound(spokenName);

  final top = matches.first;
  final confident = top.score >= NluResult.autoExecuteThreshold;
  final clearLeader = matches.length == 1 ||
      (top.score - matches[1].score) > kAmbiguityMargin;

  if (confident && clearLeader) return LookupFound(top);

  return LookupAmbiguous(matches.take(kMaxSpokenChoices).toList());
}
