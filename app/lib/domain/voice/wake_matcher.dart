import 'voice_settings.dart';

/// Найденное обращение: что прозвучало и какая команда стоит после него.
class WakeMatch {
  const WakeMatch({
    required this.heard,
    required this.command,
    this.fuzzy = false,
  });

  /// Слово, принятое за обращение («макс», «мась»…).
  final String heard;

  /// Текст после обращения; пустой — прозвучало одно имя.
  final String command;

  /// Имя распознано неточно и принято по звучанию и контексту.
  final bool fuzzy;
}

/// Ищет обращение в распознанном тексте.
///
/// Короткое имя T-one пишет по-разному, и это не догадки, а замер: русская
/// речь Piper в 36 вариантах темпа дала «макс», «мак», «маг», «магс», «матс»,
/// «мах», «мась», «нась», «насть», «натс», «нас», «над». Общий у всех
/// рисунок — носовой, «а», смычный и/или «с»: его и ищет [_maxSound].
///
/// Среди таких форм есть обычные слова («нас», «над», «мак»), поэтому
/// неточная форма засчитывается, только если:
/// * за ней начинается команда («нась позвони маме») — [_commandStems], или
/// * вся фраза — одно слово («нас.» после паузы).
///
/// Так «нас позвали в гости», «над городом» и «мак растёт» — не обращение,
/// как и «позвони Максу» и «Максим пришёл»: это другие слова. Промежуточный
/// «макс» внутри «Максим» отсекает PipelineCore: он ждёт следующего слова.
class WakeMatcher {
  WakeMatcher({
    this.phrase = WakePhrases.max,
    this.sensitivity = WakeSensitivity.medium,
  }) : _strictPosition = switch (sensitivity) {
         WakeSensitivity.low => 0,
         WakeSensitivity.medium => 2,
         WakeSensitivity.high => 4,
       },
       _fuzzyPosition = switch (sensitivity) {
         WakeSensitivity.low => -1,
         WakeSensitivity.medium => 0,
         WakeSensitivity.high => 1,
       },
       _needsPrefix = phrase == WakePhrases.heyMax;

  final String phrase;
  final WakeSensitivity sensitivity;

  /// Сколько слов может стоять перед точным именем (не считая «эй», «привет»).
  final int _strictPosition;

  /// То же для неточной формы; −1 — неточные формы не принимаются.
  final int _fuzzyPosition;

  /// «Эй, Макс»: без приветствия имя не считается.
  final bool _needsPrefix;

  bool get _alym => phrase == WakePhrases.alym;

  /// Обращения перед именем. T-one пишет «эй» и как «и», «ий», «кей».
  static const _prefixes = {
    'эй',
    'хей',
    'hey',
    'ой',
    'и',
    'ий',
    'кей',
    'окей',
    'привет',
    'слушай',
  };

  static const _strictMax = {'макс', 'max', 'макc'};
  static const _strictAlym = {'алым', 'alym'};

  /// Носовой + «а» + смычный и/или «с», как в замеренных ошибках T-one.
  static final _maxSound = RegExp(r'^[мн][аэя][кгхтд]?[сзц]?(?:ть|т|ь)?$');
  static const _alymSounds = {
    'алом',
    'алим',
    'олым',
    'авом',
    'авам',
    'алум',
    'алм',
    'салом',
    'аом',
    'аум',
  };

  /// Начала команд, которые понимает помощник. Сравнение по началу слова:
  /// «позвони», «позвонить», «позвоните».
  static const _commandStems = [
    'позвон', 'звон', 'набер', 'напиш', 'отправ', 'смс', 'сообщ', //
    'постав',
    'став',
    'завед',
    'установ',
    'будил',
    'разбуд',
    'таймер',
    'засек',
    'включ',
    'выключ',
    'фонар', 'громч', 'тиш', 'как', 'котор', 'скольк', 'скаж', 'врем',
    'дат', 'числ', 'напом', 'откр', 'запуст', 'прочит', 'прочт', 'кто',
    'запомн', 'вспомн', 'забуд', 'что', 'где', 'помог', 'стоп', 'хват',
    'отмен', 'повтор', 'привет', 'спасиб', 'пауз', 'следующ', 'предыдущ',
    'продолж', 'расскаж', 'найд', 'погод', 'батар', 'заряд', 'сегодн',
    'завтр', 'мне', 'посчит', 'умнож', 'слушай', 'да', 'нет',
  ];

  static final _word = RegExp(r"[\p{L}\p{N}']+", unicode: true);

  bool _isStrict(String w) =>
      _alym ? _strictAlym.contains(w) : _strictMax.contains(w);

  bool _isFuzzy(String w) {
    if (_isStrict(w)) return false;
    if (_alym) return _alymSounds.contains(w);
    return w.length >= 3 && _maxSound.hasMatch(w);
  }

  /// Одиночное слово, которое тоже может быть именем: только чувствительный
  /// режим принимает совсем короткие «на» и «ма».
  bool _isIsolatedFuzzy(String w) =>
      _isFuzzy(w) ||
      (sensitivity == WakeSensitivity.high &&
          !_alym &&
          (w == 'на' || w == 'ма'));

  static bool _startsCommand(String w) => _commandStems.any(
    (stem) => w.length >= stem.length && w.startsWith(stem),
  );

  /// null — обращения нет (или рано судить). Иначе — команда после имени.
  ///
  /// [complete] — фраза закончилась (VAD услышал паузу): только тогда
  /// одиночное слово может быть обращением.
  WakeMatch? match(String text, {bool complete = true}) {
    final lower = text.toLowerCase();
    final words = _word.allMatches(lower).toList();
    if (words.isEmpty) return null;

    String word(int i) => words[i].group(0)!;
    WakeMatch found(int i, {required bool fuzzy}) => WakeMatch(
      heard: word(i),
      command: _clean(text.substring(words[i].end)),
      fuzzy: fuzzy,
    );

    var position = 0;
    for (var i = 0; i < words.length; i++) {
      final w = word(i);
      if (_prefixes.contains(w) && !_isStrict(w)) continue;
      final prefixed = i > 0 && _prefixes.contains(word(i - 1));
      final allowed = !_needsPrefix || prefixed;

      if (_isStrict(w) && position <= _strictPosition) {
        return allowed ? found(i, fuzzy: false) : null;
      }
      if (_fuzzyPosition >= 0 && position <= _fuzzyPosition && allowed) {
        final single = complete && words.length == 1;
        if (single && _isIsolatedFuzzy(w)) return found(i, fuzzy: true);
        // Команда может начаться не с первого слова: «ставь» T-one часто
        // пишет как «тавь» или «так», но за ним идёт «будильник».
        final next = [
          for (var j = i + 1; j < words.length && j <= i + 2; j++) word(j),
        ];
        if (_isFuzzy(w) && next.any(_startsCommand)) {
          return found(i, fuzzy: true);
        }
      }
      position++;
      if (position > _strictPosition) return null;
    }
    return null;
  }

  /// Знаки между именем и командой. Хвост команды не трогаем: в тексте SMS
  /// «я опаздываю!» восклицательный знак — часть сообщения.
  static final _lead = RegExp(r'^[\s,.!?:;—–-]+');

  static String _clean(String s) => s.replaceFirst(_lead, '').trim();
}
