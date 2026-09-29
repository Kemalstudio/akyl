import '../../domain/entities/contact.dart';
import '../../domain/ports/contact_resolver.dart';
import '../../domain/ports/contacts_source.dart';
import '../../domain/ports/contact_alias_store.dart';
import 'family_names.dart';
import 'diminutives.dart';
import 'morphology.dart';
import 'similarity.dart';
import 'transliteration.dart';

/// Поиск контакта по произнесённому имени (ТЗ, FR-5), бюджет — 30 мс.
///
/// Индекс строится заранее (при запуске и при изменении адресной книги), поэтому
/// на горячем пути сначала идут три поиска по хеш-таблице — точный, падежный и
/// фонетический. Перебор с Jaro-Winkler включается, только если они пусты.
class ContactIndex implements ContactResolver {
  ContactIndex(
    this._source, {
    RussianMorphology morphology = const RussianMorphology(),
    ContactAliasStore? aliasStore,
  }) : _morphology = morphology,
       _aliasStore = aliasStore;

  final ContactAliasStore? _aliasStore;
  Map<String, String> _relationships = {};
  Map<String, String> get relationships => Map.unmodifiable(_relationships);

  /// Назначенные близкие в порядке ролей: мама, папа, брат… Для SOS и
  /// присмотра — им звонят и пишут первыми.
  List<Contact> get relatives => [
    for (final role in FamilyNames.groups.keys)
      if (_relationships[role] case final id?)
        ..._contacts.where((c) => c.id == id).take(1),
  ];

  Future<void> rememberRelationship(String role, String? contactId) async {
    if (!FamilyNames.groups.containsKey(role)) throw ArgumentError.value(role);
    if (contactId != null && !_contacts.any((c) => c.id == contactId)) {
      throw ArgumentError.value(contactId);
    }
    final updated = {..._relationships};
    if (contactId == null) {
      updated.remove(role);
    } else {
      updated[role] = contactId;
    }
    await _aliasStore?.save(updated);
    _relationships = updated;
  }

  final ContactsSource _source;
  final RussianMorphology _morphology;

  /// Псевдоним в нормальной форме -> кандидаты.
  final Map<String, List<_Alias>> _byAlias = {};

  /// Фонетический ключ -> кандидаты (Ahmet и Ахмед попадают в один).
  final Map<String, List<_Alias>> _byPhonetic = {};

  /// Длина псевдонима -> сами псевдонимы. Нужно, чтобы перебор с Jaro-Winkler
  /// не проходил по всей книге: сравниваются только слова близкой длины.
  final Map<int, List<String>> _aliasKeysByLength = {};
  final Map<int, List<String>> _phoneticKeysByLength = {};

  List<Contact> _contacts = const [];

  /// Ниже этого Jaro-Winkler не считаем совпадением вовсе.
  static const double _fuzzyFloor = 0.82;

  /// Короткие слова слишком легко «совпадают» — для них порог выше.
  static const int _shortNameLength = 4;
  static const double _shortFuzzyFloor = 0.9;

  /// На сколько символов услышанное имя может отличаться по длине от искомого.
  /// STT ошибается заменами и одиночными пропусками, а не меняет длину слова
  /// втрое, — поэтому перебор ограничен этой полосой. Без неё поиск по книге
  /// из 500 контактов занимал 250 мс вместо 30 мс из бюджета ТЗ.
  static const int _lengthTolerance = 2;

  List<Contact> get contacts => _contacts;

  @override
  Future<void> buildIndex() async {
    _byAlias.clear();
    _byPhonetic.clear();
    _aliasKeysByLength.clear();
    _phoneticKeysByLength.clear();
    _contacts = await _source.loadAll();
    _relationships = await _aliasStore?.load() ?? {};

    for (final contact in _contacts) {
      final full = RussianMorphology.normalize(contact.displayName);
      if (full.isEmpty) continue;

      // Целиком: «ахмед работа» — так зовут, если в книге записано так.
      _addWithForms(full, contact, MatchKind.exact);
      for (final alias in FamilyNames.aliasesFor(full)) {
        _addWithForms(alias, contact, MatchKind.morphology);
      }

      // По словам: «Ахмед Рахманов» отзывается и на «ахмед», и на «рахманов».
      final tokens = full.split(' ').where((t) => t.isNotEmpty);
      for (final token in tokens) {
        _addWithForms(token, contact, MatchKind.exact);
        for (final alias in FamilyNames.aliasesFor(token)) {
          _addWithForms(alias, contact, MatchKind.morphology);
        }

        // «Мама» -> мамуля, мамочка, мам.
        for (final v in Diminutives.variantsOf(token)) {
          _addWithForms(v, contact, MatchKind.diminutive);
        }
        // «Саша» в книге -> отзывается на «александр».
        for (final fullName in Diminutives.expandsTo(token)) {
          _addWithForms(fullName, contact, MatchKind.diminutive);
        }
      }
    }

    _groupByLength(_byAlias, _aliasKeysByLength);
    _groupByLength(_byPhonetic, _phoneticKeysByLength);
  }

  static void _groupByLength(
    Map<String, List<_Alias>> source,
    Map<int, List<String>> target,
  ) {
    for (final key in source.keys) {
      target.putIfAbsent(key.length, () => []).add(key);
    }
  }

  /// Кладёт слово, все его падежные формы и фонетический ключ каждой формы.
  ///
  /// Ключи считаются и для падежных форм тоже: имя, записанное латиницей,
  /// в речи всё равно склоняется по-русски — «Gurban» слышится как «гурбану».
  void _addWithForms(String word, Contact contact, MatchKind kind) {
    _put(_byAlias, word, _Alias(contact, kind));
    _addPhonetic(word, contact);

    for (final form in _morphology.inflections(word)) {
      if (form == word) continue;
      _put(_byAlias, form, _Alias(contact, MatchKind.morphology));
      _addPhonetic(form, contact);
    }
  }

  void _addPhonetic(String word, Contact contact) => _put(
    _byPhonetic,
    Transliteration.phoneticKey(word),
    _Alias(contact, MatchKind.transliteration),
  );

  static void _put(Map<String, List<_Alias>> map, String key, _Alias alias) {
    if (key.isEmpty) return;
    final list = map.putIfAbsent(key, () => []);
    // Один и тот же контакт под одним ключом не дублируем: берём лучший способ.
    for (var i = 0; i < list.length; i++) {
      if (list[i].contact.id != alias.contact.id) continue;
      if (alias.kind.baseScore > list[i].kind.baseScore) list[i] = alias;
      return;
    }
    list.add(alias);
  }

  @override
  Future<List<ContactMatch>> resolve(String spokenName) async {
    final spoken = RussianMorphology.normalize(spokenName);
    if (spoken.isEmpty) return const [];

    final remembered = _relationships[FamilyNames.roleOf(spoken)];
    if (remembered != null) {
      final contact = _contacts.where((c) => c.id == remembered).firstOrNull;
      // A removed contact must be reassigned, never silently replaced.
      if (contact == null) return const [];
      return [
        ContactMatch(contact: contact, score: 1, matchedVia: MatchKind.exact),
      ];
    }

    // id контакта -> лучшее совпадение по нему.
    final best = <String, ContactMatch>{};

    void offer(Contact c, double score, MatchKind kind) {
      final current = best[c.id];
      if (current != null && current.score >= score) return;
      best[c.id] = ContactMatch(contact: c, score: score, matchedVia: kind);
    }

    // 1. Точное совпадение или известная падежная/уменьшительная форма.
    for (final alias in _byAlias[spoken] ?? const <_Alias>[]) {
      offer(alias.contact, alias.kind.baseScore, alias.kind);
    }

    // 2. Отсечь окончание и попробовать снова — для имён, которых нет в правилах.
    if (best.isEmpty) {
      final stem = _morphology.stripCaseEnding(spoken);
      if (stem != spoken) {
        for (final alias in _byAlias[stem] ?? const <_Alias>[]) {
          offer(
            alias.contact,
            MatchKind.morphology.baseScore,
            MatchKind.morphology,
          );
        }
      }
    }

    // 3. Фонетический ключ: Ahmet / Ахмед / Ахмет.
    if (best.isEmpty) {
      final key = Transliteration.phoneticKey(spoken);
      for (final alias in _byPhonetic[key] ?? const <_Alias>[]) {
        offer(
          alias.contact,
          MatchKind.transliteration.baseScore,
          MatchKind.transliteration,
        );
      }
    }

    // 4. Последний рубеж: перебор с Jaro-Winkler. Ошибки STT в середине имени
    //    сюда и попадают («ахмеб» вместо «ахмед»).
    if (best.isEmpty) {
      final floor = spoken.length <= _shortNameLength
          ? _shortFuzzyFloor
          : _fuzzyFloor;

      void scan(
        Map<String, List<_Alias>> map,
        Map<int, List<String>> keysByLength,
        String probe,
      ) {
        final from = probe.length - _lengthTolerance;
        final to = probe.length + _lengthTolerance;
        for (var len = from; len <= to; len++) {
          for (final alias in keysByLength[len] ?? const <String>[]) {
            final score = Similarity.jaroWinkler(probe, alias);
            if (score < floor) continue;
            for (final c in map[alias]!) {
              // Нечёткое совпадение не может быть увереннее точного.
              offer(
                c.contact,
                score * MatchKind.fuzzy.baseScore,
                MatchKind.fuzzy,
              );
            }
          }
        }
      }

      scan(_byAlias, _aliasKeysByLength, spoken);
      // И по звучанию — на случай, когда STT ошибся в букве нерусского имени.
      if (best.isEmpty) {
        scan(
          _byPhonetic,
          _phoneticKeysByLength,
          Transliteration.phoneticKey(spoken),
        );
      }
    }

    final result = best.values.toList()..sort();
    return result;
  }
}

/// Запись индекса: какой контакт и каким способом отозвался на псевдоним.
class _Alias {
  const _Alias(this.contact, this.kind);

  final Contact contact;
  final MatchKind kind;
}

extension on MatchKind {
  /// Насколько доверяем совпадению этого рода.
  /// Порог автоматического звонка — 0.85 (ТЗ, FR-6), поэтому fuzzy до него
  /// сам по себе не дотягивает и почти всегда вызывает уточнение.
  double get baseScore => switch (this) {
    MatchKind.exact => 1.0,
    MatchKind.morphology => 0.97,
    MatchKind.diminutive => 0.93,
    MatchKind.transliteration => 0.9,
    MatchKind.fuzzy => 0.95,
  };
}
