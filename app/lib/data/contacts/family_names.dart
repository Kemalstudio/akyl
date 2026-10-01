import 'morphology.dart';

/// Curated kinship names. Never infer a relative from an unrelated first name.
abstract final class FamilyNames {
  static const groups = <String, List<String>>{
    'мама': [
      'мама',
      'мамочка',
      'мамуля',
      'мать',
      'eje',
      'ejem',
      'ejemjan',
      'ejejan',
      'эдже',
      'эджем',
      'эджемджан',
      'эже',
      'эжем',
      'эжемжан',
      'ejem jan',
    ],
    'папа': [
      'папа',
      'папочка',
      'папуля',
      'отец',
      'kaka',
      'kakam',
      'kakamjan',
      'kakajan',
      'кака',
      'какам',
      'какамджан',
      'какажан',
      'kakam jan',
    ],
    'брат': [
      'брат',
      'братик',
      'братишка',
      'братан',
      'aga',
      'agam',
      'ini',
      'inim',
      'ага',
      'агам',
      'иним',
    ],
    'сестра': [
      'сестра',
      'сестрёнка',
      'сестренка',
      'сестричка',
      'uýa',
      'uya',
      'uyam',
      'jigi',
      'jigim',
      'уя',
      'уям',
      'джигим',
    ],
    'бабушка': [
      'бабушка',
      'бабуля',
      'бабуся',
      'баба',
      'ejemmama',
      'eneke',
      'энеке',
    ],
    'дедушка': [
      'дедушка',
      'дедуля',
      'дед',
      'деда',
      'ata',
      'atam',
      'baba',
      'babam',
      'атам',
      'бабам',
    ],
    'жена': [
      'жена',
      'жёнушка',
      'женушка',
      'супруга',
      'любимая',
      'aýalym',
      'ayalym',
      'hatynym',
      'аялым',
    ],
    'муж': ['муж', 'муженёк', 'супруг', 'любимый', 'ärim', 'arim', 'ярым'],
    'сын': ['сын', 'сынок', 'сыночек', 'сынуля', 'ogul', 'oglum', 'оглум'],
    'дочь': [
      'дочь',
      'дочка',
      'доча',
      'доченька',
      'дочурка',
      'gyz',
      'gyzym',
      'гызым',
    ],
    'тётя': [
      'тётя',
      'тетя',
      'тётушка',
      'daýza',
      'dayza',
      'daýzam',
      'дайза',
      'дайзам',
    ],
    'дядя': ['дядя', 'дядюшка', 'daýy', 'dayy', 'daýym', 'дайы', 'дайым'],
  };

  /// Как роль подписана в настройках: по-русски и по-туркменски.
  static const titles = <String, String>{
    'мама': 'Мама · Ejem',
    'папа': 'Папа · Kakam',
    'брат': 'Брат · Agam',
    'сестра': 'Сестра · Uýam',
    'бабушка': 'Бабушка · Eneke',
    'дедушка': 'Дедушка · Atam',
    'жена': 'Жена · Aýalym',
    'муж': 'Муж · Ärim',
    'сын': 'Сын · Oglum',
    'дочь': 'Дочь · Gyzym',
    'тётя': 'Тётя · Daýzam',
    'дядя': 'Дядя · Daýym',
  };

  /// Любая падежная форма любого синонима -> роль. Строится один раз:
  /// склонять все синонимы на каждое слово книги слишком дорого.
  static final Map<String, String> _formToRole = () {
    const morphology = RussianMorphology();
    final map = <String, String>{};
    for (final entry in groups.entries) {
      for (final alias in entry.value) {
        for (final form in morphology.inflections(alias)) {
          map.putIfAbsent(form, () => entry.key);
        }
      }
    }
    return map;
  }();

  static String? roleOf(String name) =>
      _formToRole[RussianMorphology.normalize(name)];

  static Iterable<String> aliasesFor(String name) =>
      groups[roleOf(name)] ?? const <String>[];
}
