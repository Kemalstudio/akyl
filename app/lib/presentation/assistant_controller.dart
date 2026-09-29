import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/contacts/contact_index.dart';
import '../data/phone/care_bridge.dart';
import '../domain/dialog/conversation_titler.dart';
import '../domain/dialog/dialog_machine.dart';
import '../domain/dialog/dialog_state.dart';
import '../domain/entities/contact.dart';
import '../domain/entities/conversation.dart';
import '../domain/entities/intent.dart';
import '../domain/entities/skill_result.dart';
import '../domain/ports/contact_resolver.dart';
import '../domain/ports/conversation_store.dart';
import '../domain/ports/phone.dart';
import 'voice_manager.dart';

export '../domain/entities/conversation.dart' show ChatMessage, Conversation;
export 'voice_manager.dart';

/// Связывает автомат диалога с экраном: разговоры, разрешения, команды.
///
/// Голос — микрофон, обращение, озвучка — целиком у [VoiceManager]: здесь
/// только передача распознанной фразы в диалог и ответа обратно.
class AssistantController extends ChangeNotifier {
  AssistantController({
    required DialogMachine machine,
    required ContactResolver resolver,
    required VoiceManager voice,
    required Phone phone,
    required ConversationStore store,
    ConversationTitler titler = const ConversationTitler(),
    CareBridge? care,
    bool simpleMode = false,
    ValueChanged<bool>? onSimpleModeChanged,
  }) : _machine = machine,
       _resolver = resolver,
       _voice = voice,
       _phone = phone,
       _store = store,
       _titler = titler,
       _care = care,
       _simpleMode = simpleMode,
       _onSimpleModeChanged = onSimpleModeChanged,
       _current = Conversation.fresh() {
    _voice
      ..onCommand = _handleVoiceCommand
      ..dialogAwaiting = (() => _machine.state.isAwaiting)
      ..addListener(_onVoiceChanged);
    _machine.guard = _guard;
  }

  final DialogMachine _machine;
  final ContactResolver _resolver;
  final VoiceManager _voice;
  final Phone _phone;
  final ConversationStore _store;
  final ConversationTitler _titler;
  bool _disposed = false;
  Future<void>? _initFuture;

  VoiceManager get voice => _voice;

  /// Автомат диалога знает, что микрофон слушает команду: строка состояния
  /// и подсказки на экране берутся из него.
  void _onVoiceChanged() {
    final state = _machine.state;
    if (_voice.listening && state == DialogState.idle) {
      _machine.startListening();
    } else if (!_voice.listening && state == DialogState.listening && !_busy) {
      _machine.abortListening();
    }
    notifyListeners();
  }

  List<Contact> get contacts => _resolver is ContactIndex
      ? List.unmodifiable((_resolver).contacts)
      : const [];
  Map<String, String> get relationships =>
      _resolver is ContactIndex ? (_resolver).relationships : const {};

  Future<void> rememberRelationship(String role, String? contactId) async {
    if (_resolver case final ContactIndex index) {
      await index.rememberRelationship(role, contactId);
      notifyListeners();
    }
  }

  Future<void> refreshContacts() async {
    await _buildIndex();
    notifyListeners();
  }

  // --- Забота и простой режим ------------------------------------------------

  final CareBridge? _care;

  bool _simpleMode;
  final ValueChanged<bool>? _onSimpleModeChanged;

  /// Простой режим для родителей: крупный текст и большие кнопки звонка.
  bool get simpleMode => _simpleMode;

  void setSimpleMode(bool value) {
    if (_simpleMode == value) return;
    _simpleMode = value;
    _onSimpleModeChanged?.call(value);
    notifyListeners();
  }

  /// Назначенные близкие — им звонит SOS и пишет присмотр.
  List<Contact> get relatives =>
      _resolver is ContactIndex ? (_resolver).relatives : const [];

  bool _batteryWatch = false;

  /// Присмотр: при заряде ниже 15% близким уходит SMS.
  bool get batteryWatch => _batteryWatch;

  Future<void> refreshCare() async {
    try {
      _batteryWatch = await _care?.batteryWatchEnabled() ?? false;
    } catch (_) {
      _batteryWatch = false;
    }
    if (!_disposed) notifyListeners();
  }

  /// Включить присмотр. Номера — близких из настроек; без них включать
  /// некому писать.
  Future<void> setBatteryWatch(bool on) async {
    final numbers = [
      for (final c in relatives)
        if (c.primaryPhone case final phone?) phone.number,
    ];
    if (on && numbers.isEmpty) {
      throw StateError('Сначала назначьте близких');
    }
    await _care?.setBatteryWatch(on ? numbers : const []);
    _batteryWatch = on;
    notifyListeners();
  }

  /// Разрешение на место для SOS — заранее, не в момент беды.
  Future<bool> requestLocation() async =>
      await _care?.requestLocationPermission() ?? false;

  // --- Голос: то, что показывает экран ---------------------------------------

  bool get listening => _voice.listening;
  bool get wakeListening => _voice.wakeListening;
  bool get voiceAvailable => _voice.voiceAvailable;
  String get partialText => _voice.partialText;
  ValueNotifier<double> get soundLevel => _voice.level;
  bool get wakeWordEnabled => _voice.settings.wakeEnabled;
  bool get ttsEnabled => _voice.settings.autoSpeak;

  Future<void> setWakeWordEnabled(bool value) => _voice.updateSettings(
    _voice.settings.copyWith(wakeEnabled: value),
  );

  Future<void> setTtsEnabled(bool value) =>
      _voice.updateSettings(_voice.settings.copyWith(autoSpeak: value));

  Future<void> listen() => _voice.listen();
  Future<void> stopListening() => _voice.stopListening();

  /// Личные данные не читаются вслух с заблокированного экрана: рядом
  /// с телефоном на подоконнике может стоять кто угодно.
  static const _personal = {
    Intent.readSms,
    Intent.recentCalls,
    Intent.lastCall,
    Intent.recall,
    Intent.sms,
  };

  String? _guard(Intent intent) {
    if (!_voice.locked || _voice.settings.personalOnLockScreen) return null;
    if (!_personal.contains(intent)) return null;
    return 'Разблокируйте телефон: это личные данные.';
  }

  // --- Разговоры -------------------------------------------------------------

  /// Сохранённые разговоры, свежие первыми. Текущий сюда попадает только
  /// после первой реплики: пустые в панели не нужны.
  List<Conversation> _conversations = [];
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  Conversation _current;
  Conversation get current => _current;

  List<ChatMessage> get history => List.unmodifiable(_current.messages);

  DialogState get state => _machine.state;

  bool _permissionsGranted = false;
  bool get permissionsGranted => _permissionsGranted;

  String? _warning;
  String? get warning => _warning ?? _voiceWarning;

  /// Ошибка голоса показывается, пока человек её не закрыл.
  String? get _voiceWarning {
    final error = _voice.error;
    if (error == null || error == _dismissedVoiceError) return null;
    return error;
  }

  String? _dismissedVoiceError;

  bool _busy = false;
  bool get busy => _busy || _voice.phase == VoicePhase.processing;

  bool _ready = false;
  bool get ready => _ready;

  Future<void> init() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    _conversations = await _store.load();
    if (_disposed) return;
    _permissionsGranted = await _phone.hasPermissions();
    if (_disposed) return;
    if (_permissionsGranted) {
      await _buildIndex();
      if (_disposed) return;
    }
    _ready = true;
    notifyListeners();
    // Модель распознавания грузится несколько секунд — экран уже работает.
    await _voice.init(permission: _permissionsGranted);
  }

  Future<bool> requestPermissions() async {
    _permissionsGranted = await _phone.requestPermissions();
    if (_permissionsGranted) {
      await _buildIndex();
      notifyListeners();
      await _voice.permissionGranted();
    }
    notifyListeners();
    return _permissionsGranted;
  }

  Future<void> _buildIndex() async {
    try {
      await _resolver.buildIndex();
    } catch (_) {
      _warning = 'Контакты недоступны — разрешите доступ к адресной книге';
    }
  }

  /// Начать новый разговор. Пустой текущий не плодится: если в нём ничего
  /// нет, он и остаётся текущим.
  void startNewConversation() {
    if (busy || listening) return;
    if (_current.isEmpty) return;
    _current = Conversation.fresh();
    // Контекст на 60 секунд относится к прежнему разговору: «позвони ему
    // ещё раз» в новом не должно ничего помнить.
    _machine.reset();
    notifyListeners();
  }

  void openConversation(String id) {
    if (busy || listening) return;
    final found = _conversations.where((c) => c.id == id).firstOrNull;
    if (found == null || found.id == _current.id) return;
    _current = found;
    _machine.reset();
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    if (busy || listening) return;
    _conversations.removeWhere((c) => c.id == id);
    if (_current.id == id) {
      _current = Conversation.fresh();
      _machine.reset();
    }
    await _store.save(_conversations);
    notifyListeners();
  }

  Future<void> clearAllConversations() async {
    if (busy || listening) return;
    _conversations = [];
    _current = Conversation.fresh();
    _machine.reset();
    await _store.clear();
    notifyListeners();
  }

  // --- Команда ---------------------------------------------------------------

  /// Фразы выполняются строго по очереди: набранная и сказанная команды
  /// не должны перемешаться в одном диалоге.
  Future<void> _queue = Future.value();

  /// Набранная команда: выполнить и ответить голосом, если он включён.
  Future<void> submit(String text) async {
    final phrase = text.trim();
    if (phrase.isEmpty || _busy || listening) return;
    final turn = await _process(phrase);
    if (turn != null && !turn.alreadySpoken && !_disposed) {
      await _voice.speak(turn.response);
    }
  }

  Future<VoiceReply> _handleVoiceCommand(String text) async {
    final turn = await _process(text);
    if (turn == null) return const VoiceReply('');
    return VoiceReply(
      turn.response,
      expectsReply: _machine.state.isAwaiting,
      alreadySpoken: turn.alreadySpoken,
    );
  }

  Future<DialogTurn?> _process(String phrase) {
    final result = Completer<DialogTurn?>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await _processNow(phrase));
      } catch (e) {
        result.complete(null);
      }
    });
    return result.future;
  }

  Future<DialogTurn?> _processNow(String phrase) async {
    if (_disposed) return null;
    final firstInConversation = _current.isEmpty;
    _busy = true;
    _append(ChatMessage(text: phrase, fromUser: true, at: DateTime.now()));

    try {
      // Голосовая команда уже перевела автомат в «слушаю», набранная — нет.
      if (_machine.state == DialogState.idle) _machine.startListening();
      final turn = await _machine.handle(phrase);
      _append(
        ChatMessage(
          text: turn.response,
          fromUser: false,
          at: DateTime.now(),
          status: turn.status,
        ),
      );

      // Заголовок придумывается по разобранной команде, а не по её тексту:
      // «позвони пожалуйста маме по громкой связи» -> «Звонок: Мама».
      final nlu = turn.nlu;
      if (firstInConversation && nlu != null) {
        _current.title = _titler.titleFor(nlu, phrase);
      }
      await _persist(newConversation: firstInConversation);
      return turn;
    } catch (_) {
      _machine.reset();
      const failure =
          'Не удалось завершить команду. Проверьте разрешения и повторите.';
      _warning = failure;
      _append(
        ChatMessage(
          text: failure,
          fromUser: false,
          at: DateTime.now(),
          status: SkillStatus.failed,
        ),
      );
      return null;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Кнопка «отмена» (ТЗ, FR-9) — то же, что фраза «отмена».
  Future<void> cancel() async {
    _machine.reset();
    await _voice.stopSpeaking();
    await stopListening();
    await submit('отмена');
  }

  /// «Озвучить» под ответом: сказать его ещё раз, даже если голосовые
  /// ответы выключены.
  Future<void> speakAgain(String text) async {
    if (busy || listening) return;
    await _voice.speakForced(text);
  }

  void dismissWarning() {
    if (_warning == null) _dismissedVoiceError = _voice.error;
    _warning = null;
    notifyListeners();
  }

  void _append(ChatMessage m) {
    _current.messages.add(m);
    _current.updatedAt = m.at;
    notifyListeners();
  }

  Future<void> _persist({required bool newConversation}) async {
    if (newConversation) _conversations.insert(0, _current);
    // Свежий разговор — наверх списка, даже если открыт был старый.
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _store.save(_conversations);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _voice.removeListener(_onVoiceChanged);
    unawaited(_voice.dispose());
    super.dispose();
  }
}
