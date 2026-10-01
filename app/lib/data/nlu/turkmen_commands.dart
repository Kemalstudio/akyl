/// Туркменские команды: переводятся в русские, а дальше разбор общий.
///
/// Так вся логика — контакты, близкие, подтверждения — работает и для
/// «Ejeme jaň et», без второго разборщика. Туркменский порядок слов
/// «кому — что сделать» учтён: «Ejeme jaň et» = «позвони маме».
abstract final class TurkmenCommands {
  /// Русская команда или null, если фраза не туркменская.
  static String? toRussian(String raw) {
    final t = _clean(raw);
    if (t.isEmpty) return null;

    for (final (pattern, russian) in _fixed) {
      if (pattern.hasMatch(t)) return russian;
    }

    // «Ejeme jaň et», «Ahmede jaň et gromkiý aragatnaşykda».
    final call = RegExp(
      r'^(.+?)\s+(?:jaň|jan|zeň|zen)\s+(?:et|ed|edip ber|ediň|edin|et-de)(?:\s+(.*))?$',
    ).firstMatch(t);
    if (call != null) {
      final speaker =
          (call[2] ?? '').contains('gromk') ||
          (call[2] ?? '').contains('dinamik');
      return 'позвони ${_withoutDative(call[1]!)}'
          '${speaker ? ' по громкой связи' : ''}';
    }

    // «Merede hat ýaz: gijä galýaryn», «Ejeme sms ugrat men ýoldaýyn».
    final sms = RegExp(
      r'^(.+?)\s+(?:sms|hat|habar)\s+(?:ýaz|yaz|ugrat|iber)[\s:,]+(.+)$',
    ).firstMatch(raw.trim().toLowerCase());
    if (sms != null) {
      final text = raw.trim().substring(raw.trim().length - sms[2]!.length);
      final name = raw.trim().substring(0, sms[1]!.length);
      return 'напиши ${_withoutDative(name)} что $text';
    }

    // «Budilnik 7:30 goý», «jaňly sagady 7-de goý».
    final alarm = RegExp(
      r'^(?:budilnik\S*|jaňly sagad\S*)\s+(\d{1,2}(?::\d{2})?)\S*\s+(?:goý|goy|gur|goýuber)$',
    ).firstMatch(t);
    if (alarm != null) return 'поставь будильник на ${alarm[1]}';

    return null;
  }

  static final _fixed = <(RegExp, String)>[
    (RegExp(r'^(?:sagat|wagt)\s+(?:näçe|nače|nache|nece)'), 'который час'),
    (
      RegExp(r'^(?:şu gün|su gun|bu gün|bu gun|senesi)\s+(?:näçe|nače|nece)'),
      'какое сегодня число',
    ),
    (
      RegExp(
        r'^(?:zarýad|zaryad|zarad|batareýa|batareya)\s+(?:näçe|nače|nece)',
      ),
      'сколько заряда',
    ),
    (RegExp(r'^(?:salam|salam aleýkum|salam aleykum)$'), 'привет'),
    (
      RegExp(r'^(?:salam\s+)?(?:nähili|nahili|ýagdaýlar nähili|işler nähili)'),
      'привет как дела',
    ),
    (RegExp(r'^(?:sag bol|sagbol|sag boluň|sag bolun|minnetdar)'), 'спасибо'),
    (
      RegExp(r'^(?:fonar\S*|çyra\S*|cyra\S*)\s+(?:ýak|yak|ýakyň)'),
      'включи фонарик',
    ),
    (
      RegExp(r'^(?:fonar\S*|çyra\S*|cyra\S*)\s+(?:öçür|ocur|öçüriň)'),
      'выключи фонарик',
    ),
    (RegExp(r'^(?:kömek|komek|halas ediň|halas edin)'), 'помогите'),
    (RegExp(r'^(?:hawa|howa|bolýar|boldy)$'), 'да'),
    (RegExp(r'^(?:ýok|yok|goýbolsun|goybolsun|bes et|gerek däl)$'), 'отмена'),
    (RegExp(r'^(?:kim jaň etdi|kim jan etdi)'), 'кто звонил'),
    (RegExp(r'^(?:gaýtala|gaytala|ýene aýt)'), 'повтори'),
  ];

  static String _clean(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[,.!?«»"]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Отбрасывает окончание дательного падежа: «ejeme» → «ejem»,
  /// «kakama» → «kakam», «Ahmede» → «Ahmed». Дальше имя ищется как
  /// обычно — «ejem» уже есть среди имён мамы.
  static String _withoutDative(String name) {
    final words = name.trim().split(' ');
    final last = words.removeLast();
    for (final suffix in const [
      'ýa',
      'ýe',
      'ya',
      'ye',
      'na',
      'ne',
      'a',
      'e',
      'ä',
    ]) {
      if (last.length > suffix.length + 2 && last.endsWith(suffix)) {
        words.add(last.substring(0, last.length - suffix.length));
        return words.join(' ');
      }
    }
    words.add(last);
    return words.join(' ');
  }
}
