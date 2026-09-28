import 'intent.dart';

/// Номер телефона контакта.
class PhoneNumber {
  const PhoneNumber({required this.number, required this.type, this.label});

  final String number;
  final PhoneType type;

  /// Пользовательская метка из адресной книги, если тип — other.
  final String? label;

  @override
  String toString() => '$number (${type.name})';
}

/// Контакт из адресной книги устройства.
class Contact {
  const Contact({
    required this.id,
    required this.displayName,
    required this.phones,
  });

  final String id;
  final String displayName;
  final List<PhoneNumber> phones;

  /// Номер нужного типа; если такого нет — null.
  PhoneNumber? phoneOfType(PhoneType type) {
    for (final p in phones) {
      if (p.type == type) return p;
    }
    return null;
  }

  /// Номер по умолчанию: мобильный, иначе первый доступный.
  PhoneNumber? get primaryPhone {
    if (phones.isEmpty) return null;
    return phoneOfType(PhoneType.mobile) ?? phones.first;
  }

  @override
  String toString() => 'Contact($displayName, ${phones.length} номеров)';
}

/// Контакт с оценкой того, насколько он совпал с произнесённым именем.
class ContactMatch implements Comparable<ContactMatch> {
  const ContactMatch({
    required this.contact,
    required this.score,
    required this.matchedVia,
  });

  final Contact contact;

  /// 0.0..1.0
  final double score;

  /// Как совпало — для отладки и объяснения в логах.
  final MatchKind matchedVia;

  @override
  int compareTo(ContactMatch other) => other.score.compareTo(score);

  @override
  String toString() =>
      '${contact.displayName} <- ${matchedVia.name} (${score.toStringAsFixed(2)})';
}

/// Каким способом произнесённое имя сошлось с контактом (ТЗ, FR-5).
enum MatchKind {
  /// точное совпадение строки
  exact,

  /// после нормализации падежа: «маме» -> «мама»
  morphology,

  /// уменьшительная или родственная форма: «мамуля» -> «Мама»
  diminutive,

  /// транслитерация: «Ahmet» -> «Ахмед»
  transliteration,

  /// нечёткое сравнение Jaro-Winkler
  fuzzy,
}
