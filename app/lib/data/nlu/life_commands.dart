import '../../domain/entities/intent.dart';
import '../../domain/entities/nlu_result.dart';

/// Память, напоминания, «когда я звонил», SOS.
///
/// Разбирает текст до общей нормализации: время «21:30» и текст заметки
/// должны дойти как сказаны.
abstract final class LifeCommands {
  /// Команды, которые иначе съела бы отмена: «забудь про ключи»,
  /// «отмени напоминание». Проверяются до неё.
  static NluResult? parseBeforeCancel(String raw) {
    final t = _clean(raw);
    return _sos(t) ?? _forget(raw, t) ?? _cancelReminder(t);
  }

  static NluResult? parse(String raw, {DateTime? now}) {
    final t = _clean(raw);
    if (t.isEmpty) return null;
    return _remember(raw, t) ??
        _listReminders(t) ??
        _remind(raw, t, now ?? DateTime.now()) ??
        _recall(t) ??
        _lastCall(t);
  }

  static String _clean(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}:\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // --- SOS -------------------------------------------------------------------

  static const _sosPhrases = [
    'помогите',
    'помоги мне',
    'мне плохо',
    'спасите',
    'спаси меня',
    'вызови помощь',
    'экстренный вызов',
    'sos',
    'сос',
  ];

  static NluResult? _sos(String t) {
    final hit = _sosPhrases.any(
      (p) => t == p || t.startsWith('$p ') || t.endsWith(' $p'),
    );
    return hit ? const NluResult(intent: Intent.sos, confidence: 0.99) : null;
  }

  // --- Память ----------------------------------------------------------------

  static final _rememberVerb = RegExp(
    r'^(?:запомни|запиши|сохрани|заметка)(?:\s+(?:что|пожалуйста))?[\s:,-]*',
    caseSensitive: false,
  );

  static NluResult? _remember(String raw, String t) {
    if (!RegExp(
      r'^(?:запомни|запиши|сохрани|заметка)(?:[\s:]|$)',
    ).hasMatch(t)) {
      return null;
    }
    // «Запиши маме что…» — это SMS, а не заметка.
    if (t.startsWith('запиши ') && t.contains(' что ') && !t.contains(':')) {
      final second = t.split(' ')[1];
      if (second.endsWith('е') || second.endsWith('у')) return null;
    }
    final text = raw.trim().replaceFirst(_rememberVerb, '').trim();
    return NluResult(
      intent: Intent.remember,
      slots: {if (text.isNotEmpty) Slot.value: text},
      confidence: text.isEmpty ? 0.6 : 0.95,
    );
  }

  static NluResult? _recall(String t) {
    const everything = {
      'что ты помнишь',
      'что ты запомнил',
      'что я просил запомнить',
      'что я просила запомнить',
      'мои заметки',
      'покажи заметки',
    };
    if (everything.contains(t)) {
      return const NluResult(intent: Intent.recall, confidence: 0.95);
    }
    final match = RegExp(
      r'^(?:где|куда я положил|куда я положила|что я говорил про|что я говорила про|что ты помнишь про|что ты помнишь о|напомни что я говорил про|напомни про|вспомни|что я просил запомнить про|что я просила запомнить про)\s+(.+)$',
    ).firstMatch(t);
    if (match == null) return null;
    return NluResult(
      intent: Intent.recall,
      slots: {Slot.value: match[1]!},
      confidence: 0.9,
    );
  }

  static NluResult? _forget(String raw, String t) {
    final match = RegExp(
      r'^(?:забудь|сотри|удали)\s+(?:запись\s+|заметку\s+)?(?:про|о|об)\s+(.+)$',
    ).firstMatch(t);
    if (match == null) return null;
    // «удали напоминание про…» — это о напоминаниях.
    if (t.contains('напоминани')) return null;
    return NluResult(
      intent: Intent.forget,
      slots: {Slot.value: match[1]!},
      confidence: 0.95,
    );
  }

  // --- Звонки ----------------------------------------------------------------

  static NluResult? _lastCall(String t) {
    final match = RegExp(
      r'^когда\s+(?:я\s+)?(?:в\s+)?(?:последний\s+раз\s+)?(?:звонил|звонила|разговаривал|разговаривала|говорил|говорила)\s+(?:с\s+)?(.+?)(?:\s+в\s+последний\s+раз)?$',
    ).firstMatch(t);
    if (match == null) return null;
    return NluResult(
      intent: Intent.lastCall,
      slots: {Slot.contact: match[1]!},
      confidence: 0.95,
    );
  }

  // --- Напоминания -----------------------------------------------------------

  static NluResult? _listReminders(String t) {
    const phrases = {
      'какие напоминания',
      'какие у меня напоминания',
      'мои напоминания',
      'список напоминаний',
      'покажи напоминания',
    };
    if (!phrases.contains(t)) return null;
    return const NluResult(intent: Intent.listReminders, confidence: 0.95);
  }

  static NluResult? _cancelReminder(String t) {
    if (t == 'удали все напоминания' || t == 'отмени все напоминания') {
      return const NluResult(
        intent: Intent.cancelReminder,
        slots: {Slot.value: '*'},
        confidence: 0.95,
      );
    }
    final match = RegExp(
      r'^(?:удали|отмени|убери|сотри|выключи)\s+напоминани\p{L}*\s*(?:про|о|об)?\s*(.*)$',
      unicode: true,
    ).firstMatch(t);
    if (match == null) return null;
    return NluResult(
      intent: Intent.cancelReminder,
      slots: {Slot.value: match[1]!.trim()},
      confidence: 0.95,
    );
  }

  /// «Напомни через 10 минут позвонить маме», «напоминай каждый день в 9
  /// утра выпить таблетку», «напомни завтра в 8 про врача».
  ///
  /// Слот value: `daily|09:00`, `once|2026-09-29T20:30:00.000` или
  /// `in|600` (секунды); слот message — что напомнить.
  static NluResult? _remind(String raw, String t, DateTime now) {
    final verb = RegExp(
      r'^(?:напомни|напоминай|поставь напоминание|сделай напоминание)(?:\s+мне)?(?:\s|$)',
    ).firstMatch(t);
    if (verb == null) return null;
    // «Напомни, что я говорил про ключи» — это вопрос к памяти.
    if (RegExp(r'^напомни\s+(?:что\s+я|про\s+что)').hasMatch(t)) return null;

    var rest = t.substring(verb.end).trim();
    var daily = t.startsWith('напоминай');
    rest = rest.replaceAllMapped(
      RegExp(
        r'(?:^|\s)(?:каждый день|ежедневно|каждое утро|каждый вечер)(?=\s|$)',
      ),
      (m) {
        daily = true;
        if (m[0]!.contains('утро')) rest += ' утра';
        return ' ';
      },
    );

    String? when;
    // «через 10 минут», «через час», «через полчаса».
    final after = RegExp(
      r'(?:^|\s)через\s+(?:(\d+|\p{L}+)\s+)?(минут\p{L}*|час\p{L}*|полчаса|секунд\p{L}*)(?=\s|$)',
      unicode: true,
    ).firstMatch(rest);
    if (after != null) {
      final n = after[1] == null ? 1 : (_number(after[1]!) ?? 1);
      final unit = after[2]!;
      final seconds = unit == 'полчаса'
          ? 1800
          : unit.startsWith('час')
          ? n * 3600
          : unit.startsWith('сек')
          ? n
          : n * 60;
      when = 'in|$seconds';
      daily = false;
      rest = rest.replaceRange(after.start, after.end, ' ');
    } else {
      // «в 9», «в 21:30», «в 9 утра», «в семь вечера», «завтра в 8».
      final at = RegExp(
        r'(?:^|\s)(завтра\s+)?(?:в|на)\s+(\d{1,2})(?::(\d{2}))?(?:\s+(утра|вечера|дня|ночи))?(?=\s|$)',
      ).firstMatch(rest);
      final atWords = at == null
          ? RegExp(
              r'(?:^|\s)(завтра\s+)?(?:в|на)\s+(\p{L}+)(?:\s+(утра|вечера|дня|ночи))(?=\s|$)',
              unicode: true,
            ).firstMatch(rest)
          : null;
      final match = at ?? atWords;
      if (match != null) {
        final tomorrow = match[1] != null;
        int? hour;
        var minute = 0;
        String? part;
        if (at != null) {
          hour = int.parse(at[2]!);
          minute = at[3] == null ? 0 : int.parse(at[3]!);
          part = at[4];
        } else {
          hour = _number(atWords![2]!);
          part = atWords[3];
        }
        if (hour == null) return null;
        part ??= RegExp(
          r'(?:^|\s)(утра|вечера|дня|ночи)(?=\s|$)',
        ).firstMatch(rest)?[1];
        if ((part == 'вечера' || part == 'дня') && hour < 12) hour += 12;
        if (part == 'ночи' && hour == 12) hour = 0;
        if (hour > 23 || minute > 59) return null;
        rest = rest
            .replaceRange(match.start, match.end, ' ')
            .replaceAll(RegExp(r'(?:^|\s)(утра|вечера|дня|ночи)(?=\s|$)'), ' ');
        final hh = hour.toString().padLeft(2, '0');
        final mm = minute.toString().padLeft(2, '0');
        if (daily) {
          when = 'daily|$hh:$mm';
        } else {
          var target = DateTime(now.year, now.month, now.day, hour, minute);
          if (tomorrow || !target.isAfter(now)) {
            target = target.add(const Duration(days: 1));
          }
          when = 'once|${target.toIso8601String()}';
        }
      } else if (daily) {
        // «Напоминай каждое утро» без часа — в 9:00.
        when = 'daily|09:00';
      }
    }

    // Что напомнить: остаток без служебных слов, в исходном написании.
    var text = rest
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceFirst(RegExp(r'^(?:что|чтобы|о том что|про|о|об|мне)\s+'), '')
        .trim();
    text = _restoreCase(raw, text);

    return NluResult(
      intent: Intent.remind,
      slots: {Slot.value: ?when, if (text.isNotEmpty) Slot.message: text},
      confidence: when != null && text.isNotEmpty ? 0.95 : 0.6,
    );
  }

  /// Текст напоминания берём из исходной фразы, если он там есть как есть:
  /// сохраняются заглавные буквы в именах.
  static String _restoreCase(String raw, String lower) {
    if (lower.isEmpty) return lower;
    final index = raw.toLowerCase().replaceAll('ё', 'е').indexOf(lower);
    return index < 0 ? lower : raw.substring(index, index + lower.length);
  }

  static const _numbers = {
    'один': 1,
    'одну': 1,
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
    'пятнадцать': 15,
    'двадцать': 20,
    'тридцать': 30,
    'сорок': 40,
    'пятьдесят': 50,
  };

  static int? _number(String word) => int.tryParse(word) ?? _numbers[word];
}
