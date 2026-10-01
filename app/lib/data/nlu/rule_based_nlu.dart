import '../../domain/entities/dialog_context.dart';
import '../../domain/entities/intent.dart';
import '../../domain/entities/nlu_result.dart';
import '../../domain/ports/nlu.dart';
import '../contacts/morphology.dart';
import 'device_commands.dart';
import 'life_commands.dart';
import 'turkmen_commands.dart';
import 'utility_commands.dart';

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
    'позвони',
    'позвонить',
    'звони',
    'звонить',
    'позвоните',
    'набери',
    'набрать',
    'наберите',
    'вызови',
    'вызвать',
    'соедини',
    'соедини меня',
  ];

  static const List<String> _smsVerbs = [
    'напиши',
    'написать',
    'напишите',
    'отправь',
    'отправить',
    'отправьте',
    'сообщи',
    'сообщить',
    'передай',
    'передать',
    'скажи',
    'смс',
    'сообщение',
  ];

  static const List<String> _confirmWords = [
    'да',
    'ага',
    'угу',
    'давай',
    'давайте',
    'конечно',
    'верно',
    'точно',
    'подтверждаю',
    'подтвердить',
    'ок',
    'окей',
    'окей',
    'хорошо',
    'ладно',
    'отправь',
    'отправляй',
    'отправить',
    'шли',
    'посылай',
    'все верно',
  ];

  static const List<String> _cancelWords = [
    'отмена',
    'отмени',
    'отменить',
    'стоп',
    'стой',
    'нет',
    'не надо',
    'не нужно',
    'отставить',
    'забудь',
    'забей',
    'хватит',
    'прекрати',
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
    'на громкой связи',
    'громкой связи',
    'с громкой связью',
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
    'ему',
    'ей',
    'его',
    'ее',
    'им',
    'ей же',
    'туда',
    'обратно',
    'этому человеку',
    'этому контакту',
    'этому человеку вот',
    'этому',
    'ему же',
    'этому абоненту',
  };

  static const Set<String> _againMarkers = {
    'еще',
    'ещё',
    'снова',
    'опять',
    'повтори',
    'перезвони',
  };

  /// Команды-вопросы: фраза целиком, без слотов. Ключ — что должно
  /// встретиться в сказанном, значение — намерение.
  ///
  /// Сопоставление идёт по вхождению, а не по началу строки: «алым скажи
  /// который час» и «а который сейчас час» должны сработать одинаково.
  static const Map<String, Intent> _questionPhrases = {
    'который час': Intent.time,
    'сколько времени': Intent.time,
    'скажи время': Intent.time,
    'сколько сейчас времени': Intent.time,
    'текущее время': Intent.time,
    'время сейчас': Intent.time,
    'какое сегодня число': Intent.date,
    'какое число': Intent.date,
    'какой сегодня день': Intent.date,
    'какая сегодня дата': Intent.date,
    'скажи дату': Intent.date,
    'сегодняшняя дата': Intent.date,
    'сколько заряда': Intent.battery,
    'заряд батареи': Intent.battery,
    'сколько процентов': Intent.battery,
    'заряд телефона': Intent.battery,
    'сколько батареи': Intent.battery,
  };

  /// Слова, которые отделяют текст сообщения от имени.
  static const List<String> _messageSeparators = [
    ' что ',
    ' чтобы ',
    ' о том что ',
    ' типа ',
  ];

  /// Служебные слова, которые выкидываются перед разбором имени.
  static const Set<String> _stopWords = {
    'мне',
    'пожалуйста',
    'быстро',
    'срочно',
    'сейчас',
    'на',
    'по',
    'номер',
    'номеру',
    'контакт',
    'контакту',
    'акыл',
    'эй',
    'раз',
    'разик',
  };

  /// Слова, которые сами по себе ничего не значат, но встречаются в ответах:
  /// «да всё верно», «ага давай».
  static const Set<String> _confirmFillers = {
    'все',
    'это',
    'так',
    'точно',
    'именно',
    'ну',
  };

  // --- Разбор ----------------------------------------------------------------

  @override
  Future<NluResult> parse(String text, DialogContext ctx) async {
    var command = text
        .trim()
        .replaceFirst(
          RegExp(
            r'^(?:(?:эй|привет)\s+)?(?:макс|maks|max|акыл|алым)[\s,:!—-]+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(RegExp(r'^пожалуйста[\s,]+', caseSensitive: false), '');
    // «Ejeme jaň et» -> «позвони ejem»: дальше разбор общий.
    command = TurkmenCommands.toRussian(command) ?? command;
    final t = RussianMorphology.normalize(command);
    if (t.isEmpty) return NluResult.unknown;

    // «Помогите» — раньше всего. «Забудь про ключи» и «отмени напоминание»
    // начинаются со слов отмены, но отменой не являются.
    final urgent = LifeCommands.parseBeforeCancel(command);
    if (urgent != null) return urgent;

    // «Нет, не ему, а брату» начинается с «нет», но это не отмена, а поправка.
    final correction = _tryCorrection(t, ctx);
    if (correction != null) return correction;

    // Отмена работает в любом состоянии (ТЗ, FR-9).
    final cancel = _tryCancel(t);
    if (cancel != null) return cancel;

    // «Повтори» — даже посреди вопроса «какому Ахмеду?».
    if (_repeatPhrases.contains(t)) {
      return const NluResult(intent: Intent.repeat, confidence: 0.97);
    }

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

    return _tryCall(t, ctx) ??
        UtilityCommands.parse(command) ??
        DeviceCommands.parse(command) ??
        LifeCommands.parse(command) ??
        _trySms(command, ctx) ??
        _tryQuestion(t) ??
        _trySmallTalk(t) ??
        NluResult.unknown;
  }

  static const Set<String> _repeatPhrases = {
    'повтори',
    'повтори еще раз',
    'повтори пожалуйста',
    'еще раз повтори',
    'скажи еще раз',
    'что ты сказал',
    'что ты сказала',
    'что ты говоришь',
    'не расслышал',
    'не расслышала',
    'не понял повтори',
    'что',
  };

  /// Поправка адресата: «нет, не ему, а Ахмеду брату», «я сказал папе»,
  /// «нет, маме». Имеет смысл, только если есть что поправлять.
  NluResult? _tryCorrection(String t, DialogContext ctx) {
    if (ctx.lastCommand == null &&
        ctx.pendingAction == null &&
        ctx.choices.isEmpty) {
      return null;
    }
    final match =
        RegExp(r'^(?:нет\s+)?не\s+\S+(?:\s\S+)?\s+а\s+(.+)$').firstMatch(t) ??
        RegExp(
          r'^(?:нет\s+)?я\s+(?:же\s+)?(?:сказал|сказала|имел в виду|имела в виду|просил|просила)\s+(.+)$',
        ).firstMatch(t) ??
        RegExp(r'^нет\s+(.+)$').firstMatch(t);
    if (match == null) return null;

    final name = _cleanContact(match[1]!.replaceFirst(RegExp(r'^а\s+'), ''));
    // «нет, не надо», «нет, спасибо» — это отказ, а не новое имя.
    if (name.isEmpty ||
        name.startsWith('не ') ||
        name.split(' ').length > 3 ||
        _tryCancel(name) != null ||
        _confirmWords.contains(name) ||
        const {
          'спасибо',
          'не надо',
          'не нужно',
          'все',
          'никому',
        }.contains(name)) {
      return null;
    }
    return NluResult(
      intent: Intent.correct,
      slots: {Slot.contact: name},
      confidence: 0.9,
    );
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
    final allAgreement =
        words.isNotEmpty &&
        words.every(
          (w) => _confirmWords.contains(w) || _confirmFillers.contains(w),
        );
    if (!allAgreement) return null;
    return const NluResult(intent: Intent.confirm, confidence: 0.98);
  }

  /// Вопрос о телефоне или времени: слотов нет, важна только сама фраза.
  NluResult? _tryQuestion(String t) {
    t = t
        .replaceFirst(
          RegExp(r'^(?:как дела|привет|добрый день)\s+(?:и\s+)?'),
          '',
        )
        .replaceFirst(RegExp(r'\s+пожалуйста$'), '');
    // Длинные варианты раньше коротких: «какое сегодня число» важнее,
    // чем «какое число», хотя подходят оба.
    final phrases = _questionPhrases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final phrase in phrases) {
      if (t != phrase && t != 'скажи $phrase' && t != 'а $phrase') continue;
      return NluResult(intent: _questionPhrases[phrase]!, confidence: 0.97);
    }
    return null;
  }

  NluResult? _trySmallTalk(String t) {
    // «Привет, как дела?» — приветствие и вопрос вместе, так говорят чаще,
    // чем по отдельности.
    final rest = t
        .replaceFirst(
          RegExp(
            r'^(?:привет|приветик|здравствуй|здравствуйте|добрый день|добрый вечер|доброе утро|салам|салют)(?:\s+|$)',
          ),
          '',
        )
        .replaceFirst(RegExp(r'\s+(?:макс|друг)$'), '')
        .trim();
    const questions = {
      'как дела',
      'как ты',
      'как у тебя дела',
      'как поживаешь',
      'как жизнь',
      'как сам',
    };
    final greeted = rest != t;
    final smallTalk =
        (greeted && (rest.isEmpty || questions.contains(rest))) ||
        questions.contains(t) ||
        const {'спасибо', 'благодарю', 'спасибо большое'}.contains(t);
    if (!smallTalk) return null;
    return NluResult(
      intent: Intent.smallTalk,
      slots: {Slot.topic: t},
      confidence: .99,
    );
  }

  NluResult? _trySelect(String t) {
    if (_tryQuestion(t) != null || _trySmallTalk(t) != null) return null;
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
          Slot.contactId: last.id,
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
    if (_tryQuestion(RussianMorphology.normalize(t)) != null) return null;
    // Keep the dictated body intact: punctuation, case and ё are user content.
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = t.toLowerCase();
    final stripped = _stripVerb(lower, _smsVerbs);
    final rest = stripped == null
        ? null
        : t.substring(t.length - stripped.length);
    if (rest == null) return null;

    // «отправь смс маме что ...» — слово «смс» тут служебное.
    var body = rest;
    body = body.replaceFirst(
      RegExp(r'^(?:сообщение|смс|смску)(?:\s+для)?\s+', caseSensitive: false),
      '',
    );

    String namePart;
    String message;

    final sepIndex = _findSeparator(body.toLowerCase());
    if (sepIndex != null) {
      namePart = body.substring(0, sepIndex.$1).trim();
      message = body.substring(sepIndex.$1 + sepIndex.$2).trim();
    } else {
      // Без «что»: первое слово — имя, остальное — текст.
      final references = _pronouns.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      final reference = references
          .where((p) => body.toLowerCase().startsWith('$p '))
          .firstOrNull;
      final space = reference?.length ?? body.indexOf(' ');
      if (space < 0) return null; // одно слово: имя есть, текста нет
      namePart = body.substring(0, space).trim();
      message = body.substring(space + 1).trim();
    }

    if (message.isEmpty) return null;

    final contact = _cleanContact(RussianMorphology.normalize(namePart));
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
        slots: {
          Slot.contact: last.displayName,
          Slot.contactId: last.id,
          Slot.message: message,
        },
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
    // The earliest boundary wins. Prefer the longest marker at that position;
    // «сообщение ... что ...» must not discard the beginning of the message.
    final separators = [
      ..._messageSeparators,
      ' вот это сообщение ',
      ' это сообщение ',
      ' вот такое сообщение ',
      ' такое сообщение ',
      ' сообщение ',
      ' смс ',
      ' с текстом ',
      ' текст сообщения ',
      ' сообщение: ',
      ' смс: ',
      ': ',
    ]..sort((a, b) => b.length.compareTo(a.length));
    (int, int)? found;
    for (final sep in separators) {
      final i = body.indexOf(sep);
      if (i > 0 && (found == null || i < found.$1)) found = (i, sep.length);
    }
    return found;
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
      final hasPreposition =
          i > 0 && (words[i - 1] == 'на' || words[i - 1] == 'по');
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
      .where(
        (w) =>
            w.isNotEmpty &&
            !_stopWords.contains(w) &&
            !_againMarkers.contains(w),
      )
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
