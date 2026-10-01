import '../../domain/entities/intent.dart';
import '../../domain/entities/nlu_result.dart';

/// Короткие офлайн-команды: калькулятор, музыка, заряд — и честный ответ на
/// то, что без интернета не сделать (погода, новости, поиск).
///
/// Распознаватель пишет числа словами («двадцать пять умножить на четыре»),
/// поэтому числа разбираются и цифрами, и словами до миллиона.
abstract final class UtilityCommands {
  static NluResult? parse(String raw) {
    final t = _clean(raw);
    if (t.isEmpty) return null;
    return _internet(t) ?? _media(t) ?? _battery(t) ?? _calculate(t);
  }

  static String _clean(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'(\d),(\d)'), r'$1.$2')
      .replaceAll(RegExp(r'[^\p{L}\p{N}.+\-*/×÷%\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'(?<!\d)\.|\.(?!\d)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static NluResult _result(Intent intent, [String? value]) =>
      NluResult(intent: intent, slots: {Slot.value: ?value}, confidence: 0.95);

  // --- Интернет ------------------------------------------------------------

  static NluResult? _internet(String t) {
    const topics = {
      'погод': 'weather',
      'новост': 'news',
      'курс доллар': 'rates',
      'курс валют': 'rates',
      'найди в интернете': 'search',
      'поищи в интернете': 'search',
      'загугли': 'search',
      'пробк': 'traffic',
    };
    for (final entry in topics.entries) {
      if (t.contains(entry.key)) {
        return _result(Intent.needsInternet, entry.value);
      }
    }
    return null;
  }

  // --- Музыка --------------------------------------------------------------

  static NluResult? _media(String t) {
    final music = RegExp(r'музык|песн|трек|плеер|воспроизв').hasMatch(t);
    if (RegExp(r'^(?:следующ\S*|дальше|переключи|пропусти)').hasMatch(t) &&
        (music || t.startsWith('следующ') || t.startsWith('пропусти'))) {
      return _result(Intent.media, 'next');
    }
    if (RegExp(r'^(?:предыдущ\S*|верни)').hasMatch(t) && music) {
      return _result(Intent.media, 'previous');
    }
    if (t == 'пауза' ||
        t.contains('на паузу') ||
        (music &&
            RegExp(r'останови|выключи|стоп|приостанови|хватит').hasMatch(t))) {
      return _result(Intent.media, 'pause');
    }
    if (music &&
        RegExp(r'включи|продолжи|играй|запусти|воспроизв').hasMatch(t)) {
      return _result(Intent.media, 'play');
    }
    return null;
  }

  // --- Заряд ---------------------------------------------------------------

  static NluResult? _battery(String t) {
    if (t.contains('присмотр')) return null; // настройка, а не вопрос
    final asks = RegExp(
      r'сколько|какой|какая|скажи|проверь|уровень',
    ).hasMatch(t);
    if (asks && RegExp(r'батаре|заряд|аккумулятор').hasMatch(t)) {
      return _result(Intent.battery);
    }
    return null;
  }

  // --- Калькулятор ---------------------------------------------------------

  static final _ops = <String, String>{
    'плюс': '+',
    'прибавить': '+',
    'сложить с': '+',
    '+': '+',
    'минус': '-',
    'отнять': '-',
    'вычесть': '-',
    '-': '-',
    'умножить на': '*',
    'умножить': '*',
    'умноженное на': '*',
    'помножить на': '*',
    'на': '*', // только после «умножить» уже съедено; одиночное «на» ниже
    'x': '*',
    'х': '*',
    '*': '*',
    '×': '*',
    'разделить на': '/',
    'делить на': '/',
    'поделить на': '/',
    'деленное на': '/',
    '/': '/',
    '÷': '/',
    'процентов от': '%',
    'процента от': '%',
    'процент от': '%',
    '%': '%',
  };

  static NluResult? _calculate(String t) {
    final asked = RegExp(
      r'^(?:сколько будет|посчитай|вычисли|реши|сколько)\s+',
    ).firstMatch(t);
    var body = asked == null ? t : t.substring(asked.end);
    body = body.replaceAll(RegExp(r'\s*=\s*$'), '');

    final tokens = body.split(' ');
    final (a, usedA) = parseNumber(tokens, 0);
    if (a == null) return null;
    var i = usedA;
    if (i >= tokens.length) return null;

    // Самый длинный подходящий оператор: «умножить на» раньше «умножить».
    String? op;
    for (final len in [3, 2, 1]) {
      if (i + len > tokens.length) continue;
      final phrase = tokens.sublist(i, i + len).join(' ');
      final found = _ops[phrase];
      if (found != null && !(phrase == 'на' && asked == null)) {
        op = found;
        i += len;
        break;
      }
    }
    // «25 процентов от 200» — «процентов» идёт отдельным словом.
    if (op == null) return null;

    final (b, usedB) = parseNumber(tokens, i);
    if (b == null || i + usedB != tokens.length) return null;
    return _result(Intent.calculate, '$a|$op|$b');
  }

  static const _units = {
    'ноль': 0, 'нуль': 0, 'один': 1, 'одна': 1, 'одну': 1, 'два': 2, 'две': 2,
    'три': 3, 'четыре': 4, 'пять': 5, 'шесть': 6, 'семь': 7, 'восемь': 8,
    'девять': 9, 'десять': 10, 'одиннадцать': 11, 'двенадцать': 12,
    'тринадцать': 13, 'четырнадцать': 14, 'пятнадцать': 15,
    'шестнадцать': 16, 'семнадцать': 17, 'восемнадцать': 18,
    'девятнадцать': 19,
    // Родительный падеж: «процентов от двух», «от пяти».
    'одного': 1, 'двух': 2, 'трех': 3, 'четырех': 4, 'пяти': 5, 'шести': 6,
    'семи': 7, 'восьми': 8, 'девяти': 9, 'десяти': 10,
  };

  static const _tens = {
    'двадцать': 20,
    'тридцать': 30,
    'сорок': 40,
    'пятьдесят': 50,
    'шестьдесят': 60,
    'семьдесят': 70,
    'восемьдесят': 80,
    'девяносто': 90,
    'двадцати': 20,
    'тридцати': 30,
    'сорока': 40,
    'пятидесяти': 50,
  };

  static const _hundreds = {
    'сто': 100,
    'двести': 200,
    'триста': 300,
    'четыреста': 400,
    'пятьсот': 500,
    'шестьсот': 600,
    'семьсот': 700,
    'восемьсот': 800,
    'девятьсот': 900,
    'ста': 100,
    'двухсот': 200,
    'трехсот': 300,
    'четырехсот': 400,
    'пятисот': 500,
  };

  /// Число цифрами или словами с позиции [i]: значение и сколько слов заняло.
  static (num?, int) parseNumber(List<String> tokens, int i) {
    if (i >= tokens.length) return (null, 0);
    final digits = num.tryParse(tokens[i]);
    if (digits != null) return (digits, 1);

    var total = 0;
    var current = 0;
    var used = 0;
    var any = false;
    while (i + used < tokens.length) {
      final w = tokens[i + used];
      final h = _hundreds[w], d = _tens[w], u = _units[w];
      if (h != null) {
        current += h;
      } else if (d != null) {
        current += d;
      } else if (u != null) {
        current += u;
      } else if (w.startsWith('тысяч')) {
        total += (current == 0 ? 1 : current) * 1000;
        current = 0;
      } else {
        break;
      }
      any = true;
      used++;
    }
    return any ? (total + current, used) : (null, 0);
  }
}
