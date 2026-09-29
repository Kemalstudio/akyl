import '../entities/dialog_context.dart';
import '../entities/intent.dart';
import '../entities/nlu_result.dart';
import '../entities/skill_result.dart';
import '../ports/choice_resolver.dart';
import '../ports/nlu.dart';
import '../ports/skill.dart';
import 'dialog_state.dart';

/// Один ход диалога: что услышали, что ответили, в каком состоянии остались.
class DialogTurn {
  const DialogTurn({
    required this.recognizedText,
    required this.response,
    required this.state,
    required this.status,
    this.nlu,
    this.alreadySpoken = false,
  });

  final String recognizedText;
  final bool alreadySpoken;

  /// Текст для TTS и для чата на экране (ТЗ, FR-10, FR-11).
  final String response;

  final DialogState state;
  final SkillStatus status;

  /// Разбор фразы — для отладочного экрана и метрик.
  final NluResult? nlu;

  @override
  String toString() => '"$recognizedText" -> "$response" [$state]';
}

/// Диспетчер диалога (ТЗ, раздел 5).
///
/// Всё, что связывает распознанный текст с навыком, живёт здесь: состояния,
/// контекст на 60 секунд, подтверждения и уточнения. Ни Flutter, ни Android
/// отсюда не видны — поэтому все сценарии из ТЗ проверяются юнит-тестами.
class DialogMachine {
  DialogMachine({
    required Nlu nlu,
    required ChoiceResolver choiceResolver,
    required List<Skill> skills,
    DialogContext? context,
  }) : _nlu = nlu,
       _choiceResolver = choiceResolver,
       _skills = {for (final s in skills) s.intent: s},
       context = context ?? DialogContext();

  final Nlu _nlu;
  final ChoiceResolver _choiceResolver;
  final Map<Intent, Skill> _skills;

  /// Проверка перед выполнением: вернуть текст отказа или null. Так
  /// помощник не читает SMS и журнал звонков при заблокированном экране.
  String? Function(Intent intent)? guard;

  final DialogContext context;

  DialogState _state = DialogState.idle;
  DialogState get state => _state;

  /// Команда, ради которой задан уточняющий вопрос «кому звонить?».
  NluResult? _choiceOrigin;

  static const String _didNotUnderstand =
      'Не понял. Скажите, например: позвони маме';

  /// Пользователь нажал кнопку или сказал фразу активации (ТЗ, FR-1).
  void startListening() => _transition(DialogState.listening);

  /// Микрофон закрылся, а фразы не было: вернуться в покой, не поднимая
  /// разговор. Без этого автомат завис бы в listening до следующей команды.
  /// Смена разговора: забыть контекст и вернуться в покой.
  /// «Позвони ему ещё раз» не должно тянуться из прошлого разговора.
  void reset() {
    context.reset();
    _choiceOrigin = null;
    _state = DialogState.idle;
  }

  void abortListening() {
    if (_state != DialogState.listening) return;
    _transition(DialogState.idle);
  }

  /// Основной вход: распознанная фраза целиком.
  Future<DialogTurn> handle(String recognizedText) async {
    _transition(DialogState.processing);

    final result = await _nlu.parse(recognizedText, context);
    // Новая самостоятельная команда отменяет незаконченный вопрос.
    // «Повтори» и поправка, наоборот, к нему относятся.
    if (!const {
      Intent.cancel,
      Intent.select,
      Intent.confirm,
      Intent.unknown,
      Intent.repeat,
      Intent.correct,
    }.contains(result.intent)) {
      context.clearPending();
      _choiceOrigin = null;
    }

    final turn = switch (result.intent) {
      Intent.cancel => _cancel(recognizedText, result),
      Intent.select => await _select(recognizedText, result),
      Intent.confirm => await _confirm(recognizedText, result),
      Intent.unknown => _unknown(recognizedText, result),
      Intent.repeat => _repeat(recognizedText, result),
      Intent.correct => await _correct(recognizedText, result),
      Intent.call ||
      Intent.sms ||
      Intent.time ||
      Intent.date ||
      Intent.battery ||
      Intent.smallTalk ||
      Intent.alarm ||
      Intent.timer ||
      Intent.flashlight ||
      Intent.volume ||
      Intent.readSms ||
      Intent.recentCalls ||
      Intent.openApp ||
      Intent.remember ||
      Intent.recall ||
      Intent.forget ||
      Intent.lastCall ||
      Intent.remind ||
      Intent.listReminders ||
      Intent.cancelReminder ||
      Intent.sos => await _dispatch(recognizedText, result),
    };

    if (result.intent != Intent.repeat) _lastResponse = turn.response;
    return turn;
  }

  /// Последний ответ — для «повтори».
  String? _lastResponse;

  /// «Повтори»: сказать последний ответ ещё раз, не трогая вопрос,
  /// на который человек ещё не ответил.
  DialogTurn _repeat(String text, NluResult result) {
    final (next, status) = context.pendingAction != null
        ? (DialogState.awaitingConfirmation, SkillStatus.needsConfirmation)
        : context.choices.isNotEmpty && _choiceOrigin != null
        ? (DialogState.awaitingChoice, SkillStatus.needsChoice)
        : (DialogState.idle, SkillStatus.done);
    _transition(next);
    return DialogTurn(
      recognizedText: text,
      response: _lastResponse ?? 'Я ещё ничего не говорил',
      state: _state,
      status: status,
      nlu: result,
    );
  }

  /// «Нет, не ему, а Ахмеду брату»: та же команда, другой адресат.
  /// SMS после поправки снова ждёт подтверждения — уйти не тому она не может.
  Future<DialogTurn> _correct(String text, NluResult result) async {
    final base = context.pendingAction ?? _choiceOrigin ?? context.lastCommand;
    final name = result.slot(Slot.contact);
    if (base == null || name == null) return _unknown(text, result);

    final slots = {...base.slots}..remove(Slot.contactId);
    slots[Slot.contact] = name;
    context.clearPending();
    _choiceOrigin = null;
    return _dispatch(
      text,
      base.copyWith(slots: slots, confidence: 0.95),
      nluForLog: result,
    );
  }

  /// «отмена», «стоп» — в любом состоянии (ТЗ, FR-9).
  DialogTurn _cancel(String text, NluResult result) {
    context.reset();
    _choiceOrigin = null;
    _transition(DialogState.idle);
    return DialogTurn(
      recognizedText: text,
      response: 'Отменено',
      state: _state,
      status: SkillStatus.done,
      nlu: result,
    );
  }

  DialogTurn _unknown(String text, NluResult result) {
    _transition(DialogState.idle);
    return DialogTurn(
      recognizedText: text,
      response: _didNotUnderstand,
      state: _state,
      status: SkillStatus.failed,
      nlu: result,
    );
  }

  /// «первому» / «брату» после уточняющего вопроса (ТЗ, сценарий С6).
  Future<DialogTurn> _select(String text, NluResult result) async {
    final origin = _choiceOrigin;
    final choices = context.choices;

    if (origin == null || choices.isEmpty) {
      return _unknown(text, result);
    }

    final chosen = _choiceResolver.resolve(
      result.slot(Slot.choice) ?? text,
      choices,
    );
    if (chosen == null) {
      // Вопрос остаётся в силе — переспрашиваем, а не сбрасываем диалог.
      _transition(DialogState.awaitingChoice);
      return DialogTurn(
        recognizedText: text,
        response: 'Не понял, какой именно. Повторите имя',
        state: _state,
        status: SkillStatus.needsChoice,
        nlu: result,
      );
    }

    // Имя варианта уникально в индексе, поэтому повторный поиск однозначен.
    final resolved = origin.copyWith(
      slots: {
        ...origin.slots,
        Slot.contact: chosen.contact.displayName,
        Slot.contactId: chosen.contact.id,
      },
    );
    context.clearPending();
    _choiceOrigin = null;

    return _dispatch(text, resolved, nluForLog: result);
  }

  /// «да» / «отправь» — выполняем отложенное действие (ТЗ, сценарий С4).
  Future<DialogTurn> _confirm(String text, NluResult result) async {
    final pending = context.pendingAction;
    if (pending == null) return _unknown(text, result);

    // pending передаётся тем же объектом: навык узнаёт его по identical
    // и понимает, что подтверждение уже получено.
    final turn = await _dispatch(text, pending, nluForLog: result);
    context.clearPending();
    return turn;
  }

  /// Выполнение команды навыком и перевод автомата в нужное состояние.
  Future<DialogTurn> _dispatch(
    String text,
    NluResult result, {
    NluResult? nluForLog,
  }) async {
    final skill = _skills[result.intent];
    if (skill == null) return _unknown(text, result);

    final refusal = guard?.call(result.intent);
    if (refusal != null) {
      _transition(DialogState.idle);
      return DialogTurn(
        recognizedText: text,
        response: refusal,
        state: _state,
        status: SkillStatus.failed,
        nlu: nluForLog ?? result,
      );
    }

    // Команды без адресата — «который час» — отвечают сразу: уточнять
    // там нечего.
    final needsContact =
        result.intent == Intent.call || result.intent == Intent.sms;

    // Уверенности не хватает даже на попытку — лучше переспросить (ТЗ, FR-6).
    if (needsContact &&
        !result.isConfident &&
        result.slots[Slot.contact] == null) {
      _transition(DialogState.idle);
      return DialogTurn(
        recognizedText: text,
        response: result.intent == Intent.call
            ? 'Кому позвонить?'
            : 'Кому написать?',
        state: _state,
        status: SkillStatus.failed,
        nlu: nluForLog ?? result,
      );
    }

    _transition(DialogState.executing);
    final outcome = await skill.execute(result, context);

    // Звонок и SMS можно поправить: «нет, не ему, а брату».
    if (needsContact &&
        (outcome.status == SkillStatus.done ||
            outcome.status == SkillStatus.needsConfirmation)) {
      context.rememberCommand(result);
    }

    switch (outcome.status) {
      case SkillStatus.done:
        final contact = outcome.contact;
        if (contact != null) context.rememberContact(contact);
        _transition(DialogState.idle);

      case SkillStatus.needsConfirmation:
        // Откладываем ровно тот объект, который потом узнает навык.
        final contact = outcome.contact;
        final pending = contact == null
            ? result
            : result.copyWith(
                slots: {
                  ...result.slots,
                  Slot.contact: contact.displayName,
                  Slot.contactId: contact.id,
                },
              );
        context.awaitConfirmation(pending);
        if (contact != null) context.rememberContact(contact);
        _transition(DialogState.awaitingConfirmation);

      case SkillStatus.needsChoice:
        context.offerChoices(outcome.choices);
        _choiceOrigin = result;
        _transition(DialogState.awaitingChoice);

      case SkillStatus.failed:
        _transition(DialogState.idle);
    }

    return DialogTurn(
      recognizedText: text,
      response: outcome.spokenResponse,
      alreadySpoken: outcome.alreadySpoken,
      state: _state,
      status: outcome.status,
      nlu: nluForLog ?? result,
    );
  }

  void _transition(DialogState next) {
    if (_state == next) return;
    if (!_state.canGoTo(next)) {
      // Переход, которого нет в автомате, — это ошибка в коде. В отладочной
      // сборке падаем сразу, в релизе просто выравниваем состояние.
      assert(false, 'Недопустимый переход: $_state -> $next');
    }
    _state = next;
  }
}
