/// Транслитерация и фонетическая свёртка имён (ТЗ, FR-5: Ahmet <-> Ахмед).
///
/// Две задачи:
///  1. В адресной книге имя может быть записано латиницей («Ahmet»), а сказано
///     по-русски («Ахмеду») — и наоборот.
///  2. Туркменский и русский по-разному передают одни и те же звуки:
///     оглушение на конце (Ahmet / Ахмед), ө/ү/ä, ň.
class Transliteration {
  const Transliteration();

  /// Двухбуквенные сочетания разбираются раньше однобуквенных.
  static const Map<String, String> _digraphs = {
    'sh': 'ш',
    'ch': 'ч',
    'zh': 'ж',
    'kh': 'х',
    'ts': 'ц',
    'yu': 'ю',
    'ya': 'я',
    'ye': 'е',
    'yo': 'е',
    'ee': 'и',
    'oo': 'у',
    'gh': 'г',
    'dj': 'ж',
  };

  /// Туркменская и английская латиница -> кириллица.
  static const Map<String, String> _single = {
    'a': 'а', 'ä': 'а', 'b': 'б', 'c': 'к', 'ç': 'ч', 'd': 'д',
    'e': 'е', 'f': 'ф', 'g': 'г', 'h': 'х', 'i': 'и', 'j': 'ж',
    'ž': 'ж', 'k': 'к', 'l': 'л', 'm': 'м', 'n': 'н', 'ň': 'н',
    'o': 'о', 'ö': 'о', 'p': 'п', 'q': 'к', 'r': 'р', 's': 'с',
    'ş': 'ш', 't': 'т', 'u': 'у', 'ü': 'у', 'v': 'в', 'w': 'в',
    'x': 'х', 'y': 'ы', 'ý': 'й', 'z': 'з',
  };

  /// Латинские буквы, которые встречаются в туркменских именах вне ASCII.
  static final Set<int> _latinExtras =
      'äçžňöşüý'.codeUnits.toSet();

  /// Есть ли в строке латинские буквы. Проверка по кодовым точкам, без regexp:
  /// вызывается для каждой падежной формы каждого контакта.
  static bool hasLatin(String s) {
    for (final u in s.codeUnits) {
      final lower = (u >= 0x41 && u <= 0x5A) ? u + 0x20 : u;
      if (lower >= 0x61 && lower <= 0x7A) return true;
      if (_latinExtras.contains(lower)) return true;
    }
    return false;
  }

  /// «Ahmet» -> «ахмет», «Meret» -> «мерет».
  static String latinToCyrillic(String s) {
    final src = s.toLowerCase();
    final out = StringBuffer();
    var i = 0;
    while (i < src.length) {
      if (i + 1 < src.length) {
        final pair = src.substring(i, i + 2);
        final mapped = _digraphs[pair];
        if (mapped != null) {
          out.write(mapped);
          i += 2;
          continue;
        }
      }
      final ch = src[i];
      out.write(_single[ch] ?? ch);
      i++;
    }
    return out.toString();
  }

  /// Свёртка: буква -> чем её заменить при построении фонетического ключа.
  /// Пустая строка означает «выбросить».
  static const Map<String, String> _fold = {
    'ё': 'е',
    // Кириллические буквы туркменского алфавита.
    'ә': 'а', 'ө': 'о', 'ү': 'у', 'ң': 'н', 'җ': 'ш',
    'ъ': '', 'ь': '',
    // Оглушение: туркменское имя на конце слова произносится глухо, а в
    // русской записи остаётся звонким (Ahmet / Ахмед).
    'б': 'п', 'д': 'т', 'г': 'к', 'з': 'с', 'в': 'ф', 'ж': 'ш',
    // Гласные, которые STT путает между собой.
    'ы': 'и', 'э': 'е', 'я': 'а',
  };

  /// Та же таблица, но по кодовым точкам: ключи считаются десятки тысяч раз
  /// при построении индекса, а хеширование односимвольных строк заметно дороже
  /// хеширования int. -1 означает «выбросить символ».
  static final Map<int, int> _foldUnits = {
    for (final e in _fold.entries)
      e.key.codeUnitAt(0): e.value.isEmpty ? -1 : e.value.codeUnitAt(0),
  };

  /// Огрублённая фонетическая форма: имена, звучащие одинаково, дают один ключ.
  ///
  /// «ахмед» и «ahmet» -> «ахмет»; «гурбан» и «kurban» -> «курпан».
  /// Ключ намеренно грубый — он только сводит кандидатов вместе,
  /// окончательную оценку даёт Jaro-Winkler.
  static String phoneticKey(String s) {
    final lower = s.toLowerCase();
    final src = hasLatin(lower) ? latinToCyrillic(lower) : lower;

    final units = src.codeUnits;
    final out = List<int>.filled(units.length, 0);
    var length = 0;
    var previous = -1;

    for (final u in units) {
      final folded = _foldUnits[u] ?? u;
      if (folded == -1) continue;
      // Двойные согласные: «Анна» и «Ана» — одно и то же имя.
      if (folded == previous) continue;
      out[length++] = folded;
      previous = folded;
    }

    return String.fromCharCodes(out, 0, length);
  }
}
