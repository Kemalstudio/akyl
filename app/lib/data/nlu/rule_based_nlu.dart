import '../../domain/entities/dialog_context.dart';
import '../../domain/entities/intent.dart';
import '../../domain/entities/nlu_result.dart';
import '../../domain/ports/nlu.dart';
import '../contacts/morphology.dart';

/// NLU на правилах — этап 1 (ТЗ, раздел 5).
///
/// Служит двум целям: даёт рабочее приложение до того, как обучена своя модель,
/// и задаёт нижнюю границу качества, с которой в отчёте сравнивается MlNlu
/// (ТЗ, раздел 6). Интерфейс общий, поэтому замена — одна строка в сборке
/// зависимостей.
///
/// Текст приходит от STT: нижний регистр, без пунктуации.
class RuleBasedNlu implements Nlu {
  RuleBasedNlu();

  @override
  Future<void> init() async {}

  // --- Словари ---------------------------------------------------------------

  static const List<String> _callVerbs = [
    'позвони', 'позвонить', 'звони', 'звонить', 'позвоните',
    'набери', 'набрать', 'наберите',
    'вызови', 'вызвать', 'соедини', 'соедини меня',
  ];

  static const List<String> _smsVerbs = [
    'напиши', 'написать', 'напишите',
    'отправь', 'отправить', 'отправьте',
    'сообщи', 'сообщить', 'передай', 'передать',
    'скажи', 'смс', 'сообщение',
  ];

  static const List<String> _confirmWords = [
    'да', 'ага', 'угу', 'давай', 'давайте', 'конечно', 'верно', 'точно',
    'подтверждаю', 'подтвердить', 'ок', 'окей', 'окей', 'хорошо', 'ладно',
    'отправь', 'отправляй', 'отправить', 'шли', 'посылай', 'все верно',
  ];

  static const List<String> _cancelWords = [
    'отмена', 'отмени', 'отменить', 'стоп', 'стой', 'нет', 'не надо',
    'не нужно', 'отставить', 'забудь', 'забей', 'хватит', 'прекрати',
  ];

  /// Тип номера: как его называют вслух -> что означает.
  static const Map<String, PhoneType> _phoneTypes = {
    'мобильный': PhoneType.mobile,
    'мобильном': PhoneType.mobile,
    'мобильному': PhoneType.mobile,
    'мобилу': PhoneType.mobile,
    'мобильник': PhoneType.mobile,
    'сотовый': PhoneType.mobile,
    'сотовому': PhoneType.mobile,
    'телефон': PhoneType.mobile,
    'рабочий': PhoneType.work,
    'рабочему': PhoneType.work,
    'рабочем': PhoneType.work,
    'работу': PhoneType.work,
    'работе': PhoneType.work,
    'работа': PhoneType.work,
    'офис': PhoneType.work,
    'офисный': PhoneType.work,
    'домашний': PhoneType.home,
    'домашнему': PhoneType.home,
    'домашнем': PhoneType.home,
    'дом': PhoneType.home,
    'домой': PhoneType.home,
    'дома': PhoneType.home,
  };

  /// Громкая связь: «позвони маме по громкой связи».
  /// Фразы длиннее одного слова, поэтому ищутся во всей строке, а не по словам.
  static const List<String> _speakerPhrases = [
    'по громкой связи',
    'на громкую связь',
    'через громкую связь',
    'по громкой',
    'на громкой',
    'громкую связь',
    'громкая связь',
    'по динамику',
    'через динамик',
  ];

  /// Местоимения, которые берут контакт из контекста (ТЗ, FR-8, сценарий С7).
  static const Set<String> _pronouns = {
    'ему', 'ей', 'его', 'ее', 'им', 'ей же', 'туда', 'обратно',
  };

  static const Set<String> _againMarkers = {
    'еще', 'ещё', 'снова', 'опять', 'повтори', 'перезвони',
  };

  /// Слова, которые отделяют текст сообщения от имени.
  static const List<String> _messageSeparators = [
    ' что ', ' чтобы ', ' о том что ', ' типа ',
  ];

  /// Служебные слова, которые выкидываются перед разбором имени.
  static const Set<String> _stopWords = {
    'мне', 'пожалуйста', 'быстро', 'срочно', 'сейчас', 'на', 'по', 'номер',
    'номеру', 'контакт', 'контакту', 'акыл', 'эй', 'раз', 'разик',
  };

  /// Слова, которые сами по себе ничего не значат, но встречаются в ответах:
  /// «да всё верно», «ага давай».
  static const Set<String> _confirmFillers = {
    'все', 'это', 'так', 'точно', 'именно', 'ну',
  };

  // --- Разбор ----------------------------------------------------------------

  @override
  Future<NluResult> parse(String text, DialogContext ctx) async {
    final t = RussianMorphology.normalize(text);
    if (t.isEmpty) return NluResult.unknown;

    // Отмена работает в любом состоянии (ТЗ, FR-9).
    final cancel = _tryCancel(t);
    if (cancel != null) return cancel;

    // Ответ на «какому Ахмеду?» важнее, чем попытка увидеть тут новую команду.
    if (ctx.choices.isNotEmpty) {
      final select = _trySelect(t);
      if (select != null) return select;
    }

    // «да» / «отправь» имеют смысл, только когда что-то ждёт подтверждения.
    if (ctx.pendingAction != null) {
      final confirm = _tryConfirm(t);
      if (confirm != null) return confirm;
    }

    return _tryCall(t, ctx) ?? _trySms(t, ctx) ?? NluResult.unknown;
  }

  NluResult? _tryCancel(String t) {
    for (final w in _cancelWords) {
      if (t == w || t.startsWith('$w ')) {
        return const NluResult(intent: Intent.cancel, confidence: 0.99);
      }
    }
    return null;
  }

  /// Подтверждением считается только фраза, в которой нет ничего, кроме
  /// согласия. Иначе «отправь маме что я в пути» при отложенной SMS было бы
  /// понято как «да» — и ушло бы не то сообщение (ТЗ, FR-7).
  NluResult? _tryConfirm(String t) {
    if (_confirmWords.contains(t)) {
      return const NluResult(intent: Intent.confirm, confidence: 0.98);
    }
    final words = t.split(' ').where((w) => w.isNotEmpty);
    final allAgreement = words.isNotEmpty &&
        words.every((w) => _confirmWords.contains(w) || _confirmFillers.contains(w));
    if (!allAgreement) return null;
    return const NluResult(intent: Intent.confirm, confidence: 0.98);
  }

  NluResult? _trySelect(String t) {
    // Порядковое числительное: «первому», «второй», «третьего».
    if (_ordinalIndex(t) != null || !_startsWithCommandVerb(t)) {
      return NluResult(
        intent: Intent.select,
        slots: {Slot.choice: t},
        confidence: _ordinalIndex(t) != null ? 0.97 : 0.8,
      );
    }
    return null;
  }

  NluResult? _tryCall(String t, DialogContext ctx) {
    final rest = _stripVerb(t, _callVerbs);
    if (rest == null) return null;

    final (speaker, withoutSpeaker) = _extractSpeaker(rest);
    final (phoneType, withoutType) = _extractPhoneType(withoutSpeaker);
    final contact = _cleanContact(withoutType);

    // «позвони ему ещё раз» — имя берём из контекста (ТЗ, FR-8).
    if (_isContextReference(contact, t)) {
      final last = ctx.lastContact;
      if (last == null) {
        return const NluResult(intent: Intent.call, confidence: 0.4);
      }
      return NluResult(
        intent: Intent.call,
        slots: {
          Slot.contact: last.displayName,
          if (phoneType != null) Slot.phoneType: phoneType.name,
          if (speaker) Slot.speaker: 'true',
        },
        confidence: 0.95,
      );
    }

    if (contact.isEmpty) {
      // Глагол есть, имени нет: «позвони». Переспросим, а не промолчим.
      return const NluResult(intent: Intent.call, confidence: 0.5);
    }

    return NluResult(
      intent: Intent.call,
      slots: {
        Slot.contact: contact,
        if (phoneType != null) Slot.phoneType: phoneType.name,
        if (speaker) Slot.speaker: 'true',
      },
      confidence: 0.95,
    );
  }

  NluResult? _trySms(String t, DialogContext ctx) {
    final rest = _stripVerb(t, _smsVerbs);
    if (rest == null) return null;

    // «отправь смс маме что ...» — слово «смс» тут служебное.
    var body = rest;
    for (final filler in ['смс', 'сообщение', 'сообщение для', 'смску']) {
      if (body == filler) return null; // просто «отправь смс» — имени нет
      if (body.startsWith('$filler ')) {
        body = body.substring(filler.length + 1);
      }
    }

    String namePart;
    String message;

    final sepIndex = _findSeparator(body);
    if (sepIndex != null) {
      namePart = body.substring(0, sepIndex.$1).trim();
      message = body.substring(sepIndex.$1 + sepIndex.$2).trim();
    } else {
      // Без «что»: первое слово — имя, остальное — текст.
      final space = body.indexOf(' ');
      if (space < 0) return null; // одно слово: имя есть, текста нет
      namePart = body.substring(0, space).trim();
      message = body.substring(space + 1).trim();
    }

    if (message.isEmpty) return null;

    final contact = _cleanContact(namePart);
    if (_isContextReference(contact, t)) {
      final last = ctx.lastContact;
      if (last == null) {
        return NluResult(
          intent: Intent.sms,
          slots: {Slot.message: message},
          confidence: 0.4,
        );
      }
      return NluResult(
        intent: Intent.sms,
        slots: {Slot.contact: last.displayName, Slot.message: message},
        confidence: 0.95,
      );
    }

    if (contact.isEmpty) return null;

    return NluResult(
      intent: Intent.sms,
      slots: {Slot.contact: contact, Slot.message: message},
      confidence: 0.95,
    );
  }

  // --- Вспомогательное -------------------------------------------------------

  /// Убирает глагол команды. null — если фраза начинается не с него.
  /// Глагол ищется только в начале: «скажи маме что я в пути» — команда,
  /// «мама скажи» — нет.
  String? _stripVerb(String t, List<String> verbs) {
    // Длинные варианты раньше коротких: «позвонить» до «позвони».
    final sorted = [...verbs]..sort((a, b) => b.length.compareTo(a.length));
    for (final v in sorted) {
      if (t == v) return '';
      if (t.startsWith('$v ')) return t.substring(v.length + 1).trim();
    }
    return null;
  }

  bool _startsWithCommandVerb(String t) =>
      _stripVerb(t, _callVerbs) != null || _stripVerb(t, _smsVerbs) != null;

  /// Находит «что»/«чтобы» и возвращает (позиция, длина разделителя).
  (int, int)? _findSeparator(String body) {
    for (final sep in _messageSeparators) {
      final i = body.indexOf(sep);
      if (i > 0) return (i, sep.length);
    }
    return null;
  }

  /// Вынимает просьбу о громкой связи и возвращает фразу без неё.
  (bool, String) _extractSpeaker(String s) {
    // Длинные варианты раньше коротких: «по громкой связи» до «по громкой».
    final sorted = [..._speakerPhrases]
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final phrase in sorted) {
      if (!s.contains(phrase)) continue;
      final rest = s.replaceFirst(phrase, ' ').replaceAll(RegExp(r'\s+'), ' ');
      return (true, rest.trim());
    }
    return (false, s);
  }

  /// Вынимает тип номера и возвращает фразу без него.
  (PhoneType?, String) _extractPhoneType(String s) {
    final words = s.split(' ');
    for (var i = 0; i < words.length; i++) {
      final type = _phoneTypes[words[i]];
      if (type == null) continue;

      // «телефон» без «на» перед ним — часть имени контакта, а не тип.
      final hasPreposition = i > 0 && (words[i - 1] == 'на' || words[i - 1] == 'по');
      if (words[i] == 'телефон' && !hasPreposition) continue;

      final rest = [...words]..removeAt(i);
      if (i > 0 && (rest[i - 1] == 'на' || rest[i - 1] == 'по')) {
        rest.removeAt(i - 1);
      }
      return (type, rest.join(' ').trim());
    }
    return (null, s);
  }

  /// Выкидывает служебные слова, оставляя только имя.
  String _cleanContact(String s) => s
      .split(' ')
      .where((w) => w.isNotEmpty && !_stopWords.contains(w) && !_againMarkers.contains(w))
      .join(' ')
      .trim();

  /// Имя не названо, но есть отсылка к предыдущему разговору.
  bool _isContextReference(String contact, String fullText) {
    if (_pronouns.contains(contact)) return true;
    if (contact.isNotEmpty) return false;
    return _againMarkers.any((m) => fullText.contains(m));
  }

  /// «первому» -> 0, «второй» -> 1. null — если это не числительное.
  static int? _ordinalIndex(String t) {
    const prefixes = ['перв', 'втор', 'трет', 'четверт', 'пят'];
    final firstWord = t.split(' ').first;
    for (var i = 0; i < prefixes.length; i++) {
      if (firstWord.startsWith(prefixes[i])) return i;
    }
    return null;
  }

  /// Открыто для DialogMachine: разбор ответа на «какому Ахмеду?».
  static int? ordinalIndexOf(String text) =>
      _ordinalIndex(RussianMorphology.normalize(text));
}
