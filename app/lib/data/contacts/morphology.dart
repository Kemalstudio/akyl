/// Склонение русских имён по правилам (ТЗ, FR-5).
///
/// Индекс строится из именительного падежа, поэтому дешевле сгенерировать все
/// формы имени заранее, чем угадывать основу из услышанного слова. Обратное
/// отсечение окончания оставлено как запасной путь для нерусских имён.
///
/// На этапе подготовки датасета (ml/) те же правила проверяются против
/// pymorphy3 — расхождения идут в тесты.
class RussianMorphology {
  const RussianMorphology();

  static const Set<String> _vowels = {
    'а',
    'е',
    'ё',
    'и',
    'о',
    'у',
    'ы',
    'э',
    'ю',
    'я',
  };

  /// Шипящие и к/г/х: после них в родительном пишется «и», а не «ы».
  static const Set<String> _hushAndVelar = {'ж', 'ш', 'ч', 'щ', 'к', 'г', 'х'};

  /// Все падежные формы имени, включая исходную.
  /// «Мама» -> мама, мамы, маме, маму, мамой
  /// «Ахмед» -> ахмед, ахмеда, ахмеду, ахмедом, ахмеде
  Set<String> inflections(String nominative) {
    final w = normalize(nominative);
    if (w.length < 2) return {w};

    final last = w[w.length - 1];
    final stem = w.substring(0, w.length - 1);
    final beforeLast = w.length >= 2 ? w[w.length - 2] : '';

    final forms = <String>{w};

    switch (last) {
      // Мама, Анна, Никита, Саша — 1-е склонение на «а».
      case 'а':
        final gen = _hushAndVelar.contains(beforeLast)
            ? '${stem}и'
            : '${stem}ы';
        forms.addAll({gen, '${stem}е', '${stem}у', '${stem}ой', '${stem}ою'});

      // Оля, Настя, Мерьем? — 1-е склонение на «я».
      case 'я':
        forms.addAll({'${stem}и', '${stem}е', '${stem}ю', '${stem}ей'});

      // Андрей, Сергей.
      case 'й':
        forms.addAll({'${stem}я', '${stem}ю', '${stem}ем', '${stem}е'});

      // Игорь, Любовь — мягкий знак.
      case 'ь':
        forms.addAll({
          '${stem}я',
          '${stem}ю',
          '${stem}ем',
          '${stem}е',
          '${stem}и',
        });

      // Несклоняемые: Дмитро, Мери, Айгуль? — гласная на конце, кроме а/я.
      case 'о':
      case 'у':
      case 'ы':
      case 'и':
      case 'э':
      case 'ю':
      case 'е':
      case 'ё':
        break;

      // Ахмед, Мерет, Иван — согласная: 2-е склонение.
      default:
        if (!_vowels.contains(last)) {
          final instr = _hushAndVelar.contains(last) ? '${w}ем' : '${w}ом';
          forms.addAll({'${w}а', '${w}у', instr, '${w}е'});
        }
    }

    return forms;
  }

  /// Дательный падеж для голосового ответа: «Звоню маме», «Звоню Ахмеду»
  /// (ТЗ, сценарии С1 и С2). Регистр первой буквы сохраняется.
  String dative(String nominative) {
    final src = nominative.trim();
    if (src.length < 2) return src;
    if (RegExp(r'[a-zäöüýňşçž]', caseSensitive: false).hasMatch(src)) {
      return src;
    }

    // Многословное имя склоняем по каждому слову: «Ахмед Брат» -> «Ахмеду Брату».
    if (src.contains(' ')) {
      return src.split(' ').map(dative).join(' ');
    }

    final lower = src.toLowerCase();
    final last = lower[lower.length - 1];
    final stem = src.substring(0, src.length - 1);

    final result = switch (last) {
      'а' || 'я' => '${stem}е',
      'й' || 'ь' => '${stem}ю',
      // Гласная на конце — имя несклоняемое: «Мери», «Дмитро».
      'о' || 'у' || 'ы' || 'и' || 'э' || 'ю' || 'е' || 'ё' => src,
      _ => _vowels.contains(last) ? src : '${src}у',
    };
    return result;
  }

  /// Запасной путь: отсечь вероятное падежное окончание у услышанного слова.
  /// Используется, когда слово не нашлось ни в одной сгенерированной форме.
  /// «ахмеду» -> ахмед, «маме» -> мам (неточно, дальше добирает Jaro-Winkler).
  String stripCaseEnding(String spoken) {
    final w = normalize(spoken);
    if (w.length < 4) return w;

    const endings = [
      'ою',
      'ой',
      'ем',
      'ом',
      'ей',
      'ю',
      'я',
      'у',
      'е',
      'ы',
      'и',
      'а',
    ];
    for (final e in endings) {
      if (w.endsWith(e) && w.length - e.length >= 3) {
        return w.substring(0, w.length - e.length);
      }
    }
    return w;
  }

  /// Нижний регистр, ё -> е, лишние пробелы убраны.
  /// Распознаватель речи всё равно отдаёт текст без заглавных и пунктуации
  /// (ТЗ, раздел 6, пункт про шум), поэтому сравниваем в одном виде.
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s-]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
