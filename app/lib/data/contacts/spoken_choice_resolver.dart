import '../../domain/entities/contact.dart';
import '../../domain/ports/choice_resolver.dart';
import '../nlu/rule_based_nlu.dart';
import 'morphology.dart';
import 'similarity.dart';
import 'transliteration.dart';

/// «Какому Ахмеду: Ахмед Работа или Ахмед Брат?» -> «брату» (ТЗ, сценарий С6).
///
/// Сначала порядковое числительное, потом слово из названия варианта. Сравнение
/// идёт по тем же правилам, что и поиск контакта, иначе «брату» не сойдётся
/// с «Брат».
class SpokenChoiceResolver implements ChoiceResolver {
  const SpokenChoiceResolver({
    this.morphology = const RussianMorphology(),
    this.wordMatchFloor = 0.85,
  });

  final RussianMorphology morphology;

  /// Порог Jaro-Winkler для совпадения слова из ответа со словом варианта.
  final double wordMatchFloor;

  @override
  ContactMatch? resolve(String spokenChoice, List<ContactMatch> choices) {
    if (choices.isEmpty) return null;

    final spoken = RussianMorphology.normalize(spokenChoice);
    if (spoken.isEmpty) return null;

    // «первому», «второй»
    final index = RuleBasedNlu.ordinalIndexOf(spoken);
    if (index != null) {
      return index < choices.length ? choices[index] : null;
    }

    // «брату» -> вариант, в названии которого есть «брат».
    ContactMatch? best;
    var bestScore = 0.0;

    for (final choice in choices) {
      final score = _scoreAgainst(spoken, choice.contact.displayName);
      if (score > bestScore) {
        bestScore = score;
        best = choice;
      }
    }

    return bestScore >= wordMatchFloor ? best : null;
  }

  /// Лучшее совпадение любого слова ответа с любым словом названия варианта.
  double _scoreAgainst(String spoken, String displayName) {
    final target = RussianMorphology.normalize(displayName);
    var best = 0.0;

    for (final said in spoken.split(' ')) {
      if (said.isEmpty) continue;
      final saidStem = morphology.stripCaseEnding(said);

      for (final word in target.split(' ')) {
        if (word.isEmpty) continue;

        if (said == word) return 1.0;

        final stemScore = Similarity.jaroWinkler(saidStem, word);
        final directScore = Similarity.jaroWinkler(said, word);
        final phoneticScore = Similarity.jaroWinkler(
          Transliteration.phoneticKey(said),
          Transliteration.phoneticKey(word),
        );

        for (final s in [stemScore, directScore, phoneticScore]) {
          if (s > best) best = s;
        }
      }
    }
    return best;
  }
}
