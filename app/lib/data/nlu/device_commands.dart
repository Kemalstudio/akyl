import '../../domain/entities/intent.dart';
import '../../domain/entities/nlu_result.dart';

/// Разбор команд управления телефоном: будильник, таймер, фонарик,
/// громкость, SMS, звонки, приложения.
///
/// Работает с текстом до общей нормализации: та выкидывает двоеточие,
/// и «7:30» превратилось бы в «730».
abstract final class DeviceCommands {
  static NluResult? parse(String raw) {
    final t = _clean(raw);
    if (t.isEmpty) return null;
    return _alarm(t) ??
        _timer(t) ??
        _flashlight(t) ??
        _volume(t) ??
        _readSms(t) ??
        _recentCalls(t) ??
        _openApp(t);
  }

  static String _clean(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}:.\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'(?<!\d)\.|\.(?!\d)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static NluResult _result(Intent intent, String value) =>
      NluResult(intent: intent, slots: {Slot.value: value}, confidence: 0.95);

  // --- Будильник ---------------------------------------------------------

  static NluResult? _alarm(String t) {
    if (!t.contains('будильник') && !t.contains('разбуди')) return null;
    final tokens = _tokens(t);

    // «Через 20 минут», «через час»: время считает навык по своим часам.
    final relative = _relativeMinutes(tokens);
    if (relative != null) return _result(Intent.alarm, '+$relative');

    int? hour;
    int? minute;
    final spoken = _spokenClock(tokens);
    if (spoken != null) (hour, minute) = spoken;
    for (var i = 0; spoken == null && i < tokens.length; i++) {
      final time = RegExp(r'^(\d{1,2})[:.](\d{2})$').firstMatch(tokens[i]);
      if (time != null) {
        hour = int.parse(time[1]!);
        minute = int.parse(time[2]!);
        break;
      }
      final (n, used) = _numberAt(tokens, i);
      if (n == null) continue;
      hour = n;
      var next = i + used;
      if (next < tokens.length && tokens[next].startsWith('час')) next++;
      final (m, _) = _numberAt(tokens, next);
      minute = m ?? 0;
      break;
    }
    if (hour == null) {
      return const NluResult(intent: Intent.alarm, confidence: 0.6);
    }
    // «в 7 вечера» — это 19:00; «в 12 ночи» — полночь.
    if ((t.contains('вечера') || t.contains('дня')) && hour < 12) hour += 12;
    if (t.contains('ночи') && hour == 12) hour = 0;
    if (hour > 23 || minute! > 59) return null;
    return _result(
      Intent.alarm,
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
    );
  }

  // --- Таймер ------------------------------------------------------------

  static NluResult? _timer(String t) {
    if (!t.contains('таймер') && !t.contains('засеки')) return null;
    final tokens = _tokens(t);
    var seconds = 0;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token == 'полчаса') {
        seconds += 1800;
        continue;
      }
      if (token == 'полтора' || token == 'полторы') {
        final unit = i + 1 < tokens.length ? tokens[i + 1] : '';
        seconds += (_unitSeconds(unit) ?? 60) * 3 ~/ 2;
        i++;
        continue;
      }
      final (n, used) = _numberAt(tokens, i);
      if (n != null) {
        final unit = i + used < tokens.length ? tokens[i + used] : '';
        final size = _unitSeconds(unit);
        if (size != null) {
          seconds += n * size;
          i += used;
        }
        continue;
      }
      // «на час», «на минуту» — без числа, значит одна.
      final size = _unitSeconds(token);
      if (size != null && i > 0 && tokens[i - 1] == 'на') seconds += size;
    }
    if (seconds == 0) {
      return const NluResult(intent: Intent.timer, confidence: 0.6);
    }
    return _result(Intent.timer, '$seconds');
  }

  static int? _unitSeconds(String unit) {
    if (unit.startsWith('час')) return 3600;
    if (unit.startsWith('мин')) return 60;
    if (unit.startsWith('сек')) return 1;
    return null;
  }

  // --- Фонарик -----------------------------------------------------------

  static NluResult? _flashlight(String t) {
    if (!t.contains('фонар') && !t.contains('вспышк')) return null;
    final off = _has(t, r'выключи\p{L}*|отключи\p{L}*|погаси\p{L}*|убери');
    return _result(Intent.flashlight, off ? 'off' : 'on');
  }

  // --- Громкость ---------------------------------------------------------

  static NluResult? _volume(String t) {
    // «по громкой связи» — это про звонок, а не про громкость.
    if (t.contains('громкой связ') || t.contains('громкую связ')) return null;
    final change = switch (t) {
      _
          when t.contains('без звука') ||
              t.contains('беззвуч') ||
              _has(t, r'(?:выключи|отключи|убери)\p{L}* звук\p{L}*') =>
        'mute',
      _ when _has(t, r'включи\p{L}* звук\p{L}*') => 'unmute',
      _ when t.contains('максимум') || t.contains('максимальн') =>
        t.contains('громк') || t.contains('звук') ? 'max' : null,
      _
          when t.contains('громче') ||
              t.contains('прибавь') ||
              _has(t, r'(?:увеличь|добавь)\p{L}* (?:громкость|звук)') =>
        'up',
      _
          when t.contains('тише') ||
              t.contains('убавь') ||
              _has(t, r'уменьши\p{L}* (?:громкость|звук)') =>
        'down',
      _ => null,
    };
    return change == null ? null : _result(Intent.volume, change);
  }

  // --- SMS и звонки ------------------------------------------------------

  static NluResult? _readSms(String t) {
    final aboutSms = _has(t, r'смс|sms|эсэмэс|сообщени\p{L}*|смску|смски');
    final read = _has(t, r'прочитай|прочти|зачитай|последн\p{L}*|покажи');
    final asked =
        t.contains('кто мне написал') ||
        t.contains('кто написал') ||
        t.contains('что мне написали');
    if ((aboutSms && read) || asked) {
      return const NluResult(intent: Intent.readSms, confidence: 0.95);
    }
    return null;
  }

  static NluResult? _recentCalls(String t) {
    if (t.contains('кто звонил') ||
        t.contains('кто мне звонил') ||
        t.contains('пропущенн') ||
        t.contains('последний звонок') ||
        t.contains('последние звонки')) {
      return const NluResult(intent: Intent.recentCalls, confidence: 0.95);
    }
    return null;
  }

  // --- Приложения --------------------------------------------------------

  /// «Включи» сюда не входит: «включи музыку» — не просьба открыть
  /// приложение (ТЗ, сценарий С8), а фонарик и звук разобраны выше.
  static const _openVerbs = [
    'открой',
    'открыть',
    'откройте',
    'запусти',
    'запустить',
  ];

  /// Как название произносят -> как оно пишется на телефоне.
  static const _apps = <String, String>{
    'ватсап': 'whatsapp',
    'вацап': 'whatsapp',
    'вотсап': 'whatsapp',
    'ватсапп': 'whatsapp',
    'вотсапп': 'whatsapp',
    'воцап': 'whatsapp',
    'телеграм': 'telegram',
    'телеграмм': 'telegram',
    'телегу': 'telegram',
    'ютуб': 'youtube',
    'ютюб': 'youtube',
    'инстаграм': 'instagram',
    'инсту': 'instagram',
    'инстаграмм': 'instagram',
    'имо': 'imo',
    'тикток': 'tiktok',
    'хром': 'chrome',
    'браузер': 'chrome',
    'плей маркет': 'play',
    'плеймаркет': 'play',
    'гугл плей': 'play',
    'камеру': 'camera',
    'камера': 'camera',
    'галерею': 'gallery',
    'галерея': 'gallery',
    'настройки': 'settings',
    'калькулятор': 'calculator',
    'карты': 'maps',
    'часы': 'clock',
    'календарь': 'calendar',
    'контакты': 'contacts',
    'сообщения': 'messages',
  };

  static NluResult? _openApp(String t) {
    final verb = _openVerbs.where((v) => t.startsWith('$v ')).firstOrNull;
    if (verb == null) return null;
    var name = t.substring(verb.length).trim();
    name = name
        .replaceFirst(RegExp(r'^(мне\s+)?(приложение|программу)\s+'), '')
        .replaceFirst(RegExp(r'\s+пожалуйста$'), '')
        .trim();
    if (name.isEmpty) return null;
    // И русское, и английское: на Samsung «Камера» подписана по-русски,
    // а WhatsApp — латиницей.
    final canonical = _apps[name];
    return _result(
      Intent.openApp,
      canonical == null ? name : '$canonical|$name',
    );
  }

  // --- Числа -------------------------------------------------------------

  static List<String> _tokens(String t) => t.split(' ');

  /// «Через 20 минут», «через полчаса», «через полтора часа», «через час».
  static int? _relativeMinutes(List<String> tokens) {
    final at = tokens.indexOf('через');
    if (at < 0 || at + 1 >= tokens.length) return null;
    final rest = tokens.sublist(at + 1);
    if (rest.first == 'полчаса') return 30;
    if (rest.first == 'полтора' &&
        rest.length > 1 &&
        rest[1].startsWith('час')) {
      return 90;
    }
    if (rest.first.startsWith('час')) return 60;
    final (n, used) = _numberAt(rest, 0);
    if (n == null || used >= rest.length) return null;
    final unit = rest[used];
    if (unit.startsWith('минут')) return n;
    if (unit.startsWith('час')) return n * 60;
    return null;
  }

  /// Час по-разговорному: «полвосьмого», «половину восьмого» — 7:30,
  /// «четверть восьмого» — 7:15, «без четверти восемь» — 7:45,
  /// «без десяти восемь» — 7:50.
  static (int, int)? _spokenClock(List<String> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      final w = tokens[i];
      if (w.startsWith('пол') &&
          w.length > 3 &&
          _ordinals[w.substring(3)] != null) {
        return (_ordinals[w.substring(3)]! - 1, 30);
      }
      if ((w == 'пол' || w == 'половину' || w == 'половина') &&
          i + 1 < tokens.length &&
          _ordinals[tokens[i + 1]] != null) {
        return (_ordinals[tokens[i + 1]]! - 1, 30);
      }
      if (w == 'четверть' &&
          i + 1 < tokens.length &&
          _ordinals[tokens[i + 1]] != null) {
        return (_ordinals[tokens[i + 1]]! - 1, 15);
      }
      if (w == 'без' && i + 2 < tokens.length) {
        var j = i + 1;
        int? before;
        if (tokens[j] == 'четверти') {
          before = 15;
          j++;
        } else {
          before = _minutesBefore[tokens[j]];
          if (before == null) continue;
          j++;
          // «без двадцати пяти восемь»
          if (before == 20 && tokens[j] == 'пяти') {
            before = 25;
            j++;
          }
        }
        if (j >= tokens.length) continue;
        final (h, _) = _numberAt(tokens, j);
        if (h == null || h < 1 || h > 24) continue;
        return ((h - 1) % 24, 60 - before);
      }
    }
    return null;
  }

  /// «Восьмого» в «половину восьмого» — час, к которому идёт время.
  static const _ordinals = <String, int>{
    'первого': 1,
    'второго': 2,
    'третьего': 3,
    'четвертого': 4,
    'пятого': 5,
    'шестого': 6,
    'седьмого': 7,
    'восьмого': 8,
    'девятого': 9,
    'десятого': 10,
    'одиннадцатого': 11,
    'двенадцатого': 12,
  };

  static const _minutesBefore = <String, int>{
    'пяти': 5,
    'десяти': 10,
    'пятнадцати': 15,
    'двадцати': 20,
  };

  /// Целое слово из [pattern]. `\b` в Dart не видит кириллицу.
  static bool _has(String t, String pattern) =>
      RegExp('(?:^| )(?:$pattern)(?= |\$)', unicode: true).hasMatch(t);

  static const _units = <String, int>{
    'ноль': 0,
    'один': 1,
    'одну': 1,
    'одна': 1,
    'одной': 1,
    'два': 2,
    'две': 2,
    'три': 3,
    'четыре': 4,
    'пять': 5,
    'шесть': 6,
    'семь': 7,
    'восемь': 8,
    'девять': 9,
    'десять': 10,
    'одиннадцать': 11,
    'двенадцать': 12,
    'тринадцать': 13,
    'четырнадцать': 14,
    'пятнадцать': 15,
    'шестнадцать': 16,
    'семнадцать': 17,
    'восемнадцать': 18,
    'девятнадцать': 19,
  };

  static const _tens = <String, int>{
    'двадцать': 20,
    'тридцать': 30,
    'сорок': 40,
    'пятьдесят': 50,
  };

  /// Число в позиции [i]: цифрами или словами («двадцать пять»).
  /// Возвращает значение и сколько слов оно заняло.
  static (int?, int) _numberAt(List<String> tokens, int i) {
    if (i >= tokens.length) return (null, 0);
    final digits = int.tryParse(tokens[i]);
    if (digits != null) return (digits, 1);
    final tens = _tens[tokens[i]];
    if (tens != null) {
      final unit = i + 1 < tokens.length ? _units[tokens[i + 1]] : null;
      if (unit != null && unit < 10) return (tens + unit, 2);
      return (tens, 1);
    }
    final unit = _units[tokens[i]];
    return unit == null ? (null, 0) : (unit, 1);
  }
}
