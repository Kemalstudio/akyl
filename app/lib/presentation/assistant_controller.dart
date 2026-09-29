import 'dart:async';

import 'package:flutter/foundation.dart';
import '../data/contacts/contact_index.dart';
import '../data/phone/care_bridge.dart';
import '../data/phone/hands_free_bridge.dart';
import '../domain/entities/contact.dart';
import '../domain/entities/skill_result.dart';

import '../domain/dialog/conversation_titler.dart';
import '../domain/dialog/dialog_machine.dart';
import '../domain/dialog/dialog_state.dart';
import '../domain/dialog/wake_phrase.dart';
import '../domain/entities/conversation.dart';
import '../domain/ports/contact_resolver.dart';
import '../domain/ports/conversation_store.dart';
import '../domain/ports/phone.dart';
import '../domain/ports/speech_to_text.dart';
import '../domain/ports/text_to_speech.dart';

export '../domain/entities/conversation.dart' show ChatMessage, Conversation;

/// Связывает автомат диалога с экраном: микрофон, разговоры, разрешения,
/// озвучка.
class AssistantController extends ChangeNotifier {
  AssistantController({
    required DialogMachine machine,
    required ContactResolver resolver,
    required TextToSpeech tts,
    required SpeechToText stt,
    required Phone phone,
    required ConversationStore store,
    ConversationTitler titler = const ConversationTitler(),
    HandsFreeBridge? handsFree,
    bool wakeWordEnabled = false,
    ValueChanged<bool>? onWakeWordChanged,
    CareBridge? care,
    bool simpleMode = false,
    ValueChanged<bool>? onSimpleModeChanged,
  }) : _machine = machine,
       _resolver = resolver,
       _tts = tts,
       _stt = stt,
       _phone = phone,
       _store = store,
       _titler = titler,
       _handsFree = handsFree,
       _wakeWord = wakeWordEnabled,
       _onWakeWordChanged = onWakeWordChanged,
       _care = care,
       _simpleMode = simpleMode,
       _onSimpleModeChanged = onSimpleModeChanged,
       _current = Conversation.fresh();

  final DialogMachine _machine;
  final ContactResolver _resolver;
  final TextToSpeech _tts;
  final SpeechToText _stt;
  final Phone _phone;
  final ConversationStore _store;
  final ConversationTitler _titler;
  final HandsFreeBridge? _handsFree;
  HandsFreeStatus handsFreeStatus = const HandsFreeStatus();
  bool _disposed = false;
  Future<void>? _initFuture;

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

  Future<void> refreshHandsFree() async {
    if (_handsFree == null) return;
    try {
      handsFreeStatus = await _handsFree.status();
    } catch (_) {
      handsFreeStatus = const HandsFreeStatus(
        error: 'Настройка доступна на Android',
      );
    }
    if (!_disposed) notifyListeners();
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

  Future<void> selectSystemAssistant() async => _handsFree?.selectAssistant();
  Future<void> enableHandsFree(bool enabled) async {
    if (enabled && _wakeWord && _foreground) await _pauseWake(true);
    await _handsFree?.setEnabled(enabled);
    await refreshHandsFree();
  }

  Future<void> _pauseWake(bool paused) async {
    try {
      await _handsFree?.setPaused(paused);
    } catch (_) {
      /* Foreground commands remain available. */
    }
  }

  /// Фоновый режим «Макс» (служба Android) не должен спорить за микрофон
  /// с приложением, пока оно открыто и слушает обращение само.
  Future<void> _resumeNativeWake() async {
    if (_busy || _listening || (_wakeWord && _foreground)) return;
    await _pauseWake(false);
  }

  // --- Обращение «Макс», пока приложение открыто -----------------------------

  bool _wakeWord;
  final ValueChanged<bool>? _onWakeWordChanged;

  /// Откликаться на «Макс» без нажатия кнопки, пока приложение на экране.
  bool get wakeWordEnabled => _wakeWord;

  bool _foreground = true;
  bool _wakeRunning = false;
  bool _wakeListening = false;
  bool _wakeInterrupted = false;
  Completer<void>? _wakeReleased;

  /// Микрофон открыт в ожидании «Макс».
  bool get wakeListening => _wakeListening;

  bool get _wakeAllowed =>
      _wakeWord && _foreground && _voiceAvailable && _ready && !_disposed;

  Future<void> setWakeWordEnabled(bool value) async {
    if (_wakeWord == value) return;
    _wakeWord = value;
    _onWakeWordChanged?.call(value);
    if (value) {
      await _pauseWake(true);
      _startWakeLoop();
    } else {
      await _releaseWakeMic();
      await _resumeNativeWake();
    }
    notifyListeners();
  }

  /// На фоне локальный STT закрывается. Фоновую службу пользователь включает
  /// отдельным переключателем в настройках Android.
  Future<void> setForeground(bool value) async {
    if (_foreground == value) return;
    _foreground = value;
    if (value) {
      if (_wakeWord) await _pauseWake(true);
      await refreshHandsFree();
      _startWakeLoop();
    } else {
      await _releaseWakeMic();
      if (_listening) await _stt.stop();
      await _resumeNativeWake();
    }
  }

  void _startWakeLoop() {
    if (_wakeRunning || !_wakeAllowed) return;
    unawaited(_wakeLoop());
  }

  /// Слушает фразу за фразой и ждёт в них имя. Между фразами микрофон
  /// отдаётся кнопке записи, команде и озвучке ответа.
  Future<void> _wakeLoop() async {
    _wakeRunning = true;
    var failures = 0;
    try {
      while (_wakeAllowed) {
        if (_busy || _listening) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          continue;
        }

        _wakeListening = true;
        _wakeInterrupted = false;
        _wakeReleased = Completer<void>();
        notifyListeners();

        var heard = '';
        try {
          await _stt.startWake();
          if (_wakeInterrupted || !_wakeAllowed) await _stt.stop();
          heard = await _stt.finalResult();
          failures = 0;
        } catch (e) {
          failures++;
          if (failures >= 4) {
            _warning = 'Обращение «Макс» остановлено: $e';
            _wakeWord = false;
            _onWakeWordChanged?.call(false);
          }
        } finally {
          _wakeListening = false;
          _wakeReleased?.complete();
          _wakeReleased = null;
          notifyListeners();
        }

        if (failures > 0) {
          await Future<void>.delayed(Duration(seconds: 2 * failures));
          continue;
        }
        if (_wakeInterrupted || !_wakeAllowed) continue;

        final command = wakeCommand(heard);
        if (command == null) {
          // Движок может закончить сеанс мгновенно — не крутимся вхолостую.
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        if (command.isEmpty) {
          await listen();
        } else {
          await submit(command, voiceFollowUp: true);
        }
      }
    } finally {
      _wakeRunning = false;
      _wakeListening = false;
    }
  }

  /// Забирает микрофон у ожидания «Макс»: нажата кнопка или набран текст.
  Future<void> _releaseWakeMic() async {
    final released = _wakeReleased;
    if (!_wakeListening || released == null) return;
    _wakeInterrupted = true;
    await _stt.stop();
    await released.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    // Движку Android нужна пауза, чтобы отпустить микрофон.
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  Future<void> _consumeWakeCommand() async {
    if (!_ready || _disposed || _busy || _listening) return;
    final command = await _handsFree?.takeCommand();
    if (command == null) return;
    if (command.isEmpty) {
      await listen();
    } else {
      await submit(command, voiceFollowUp: true);
    }
  }

  /// Сохранённые разговоры, свежие первыми. Текущий сюда попадает только
  /// после первой реплики: пустые в панели не нужны.
  List<Conversation> _conversations = [];
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  Conversation _current;
  Conversation get current => _current;

  List<ChatMessage> get history => List.unmodifiable(_current.messages);

  DialogState get state => _machine.state;

  bool get ttsEnabled => _tts.enabled;

  bool _permissionsGranted = false;
  bool get permissionsGranted => _permissionsGranted;

  String? _warning;
  String? get warning => _warning;

  bool _busy = false;
  bool get busy => _busy;

  bool _ready = false;
  bool get ready => _ready;

  bool _listening = false;
  bool get listening => _listening;

  /// Текст, который распознаётся в эту секунду (ТЗ, FR-2).
  String _partialText = '';
  String get partialText => _partialText;

  bool _voiceAvailable = false;
  bool get voiceAvailable => _voiceAvailable;

  StreamSubscription<String>? _partialSubscription;
  StreamSubscription<double>? _levelSubscription;

  /// Сглаженная громкость голоса 0..1, пока идёт запись команды.
  /// Отдельно от notifyListeners: меняется десятки раз в секунду, и
  /// перестраивать ради неё весь экран незачем.
  final ValueNotifier<double> soundLevel = ValueNotifier(0);

  Future<void> init() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    await _tts.init();
    if (_disposed) return;
    _conversations = await _store.load();
    if (_disposed) return;
    _permissionsGranted = await _phone.hasPermissions();
    if (_disposed) return;
    if (_permissionsGranted) {
      await _buildIndex();
      if (_disposed) return;
      await _initVoice();
      if (_disposed) return;
    }
    _ready = true;
    _handsFree?.onCommandAvailable(_consumeWakeCommand);
    notifyListeners();
    if (_wakeWord) await _pauseWake(true);
    _startWakeLoop();
    await refreshHandsFree();
    await _consumeWakeCommand();
  }

  Future<bool> requestPermissions() async {
    _permissionsGranted = await _phone.requestPermissions();
    if (_permissionsGranted) {
      await _buildIndex();
      await _initVoice();
    }
    notifyListeners();
    _startWakeLoop();
    return _permissionsGranted;
  }

  Future<void> _buildIndex() async {
    try {
      await _resolver.buildIndex();
    } catch (_) {
      _warning = 'Контакты недоступны — разрешите доступ к адресной книге';
    }
  }

  /// Микрофон — не обязательное условие работы: команду всегда можно набрать.
  Future<void> _initVoice() async {
    try {
      await _stt.init();
      if (_disposed) return;
      _voiceAvailable = true;
    } catch (e) {
      _voiceAvailable = false;
      _warning ??= 'Голос недоступен: $e. Команду можно набрать текстом';
    }
  }

  // --- Разговоры -------------------------------------------------------------

  /// Начать новый разговор. Пустой текущий не плодится: если в нём ничего
  /// нет, он и остаётся текущим.
  void startNewConversation() {
    if (_busy || _listening) return;
    if (_current.isEmpty) return;
    _current = Conversation.fresh();
    // Контекст на 60 секунд относится к прежнему разговору: «позвони ему
    // ещё раз» в новом не должно ничего помнить.
    _machine.reset();
    notifyListeners();
  }

  void openConversation(String id) {
    if (_busy || _listening) return;
    final found = _conversations.where((c) => c.id == id).firstOrNull;
    if (found == null || found.id == _current.id) return;
    _current = found;
    _machine.reset();
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    if (_busy || _listening) return;
    _conversations.removeWhere((c) => c.id == id);
    if (_current.id == id) {
      _current = Conversation.fresh();
      _machine.reset();
    }
    await _store.save(_conversations);
    notifyListeners();
  }

  Future<void> clearAllConversations() async {
    if (_busy || _listening) return;
    _conversations = [];
    _current = Conversation.fresh();
    _machine.reset();
    await _store.clear();
    notifyListeners();
  }

  // --- Голос -----------------------------------------------------------------

  /// Нажата кнопка записи (ТЗ, FR-1): слушаем до конца фразы и выполняем её.
  Future<void> listen() async {
    if (_busy || _listening) return;

    if (!_voiceAvailable) {
      await _resumeNativeWake();
      _warning = 'Распознавание речи на этом устройстве недоступно';
      notifyListeners();
      return;
    }

    // Ассистент не должен слышать собственный голос.
    _listening = true;
    _partialText = '';
    _machine.startListening();
    notifyListeners();

    await _releaseWakeMic();

    _levelSubscription = _stt.soundLevels().listen((level) {
      if (_disposed) return;
      // Быстро вверх, плавно вниз — как стрелка индикатора.
      final current = soundLevel.value;
      soundLevel.value = level > current
          ? current + (level - current) * 0.6
          : current + (level - current) * 0.25;
    });
    _partialSubscription = _stt.partialResults().listen((text) {
      if (_disposed) return;
      _partialText = text;
      notifyListeners();
    });

    String phrase = '';
    try {
      await _pauseWake(true);
      await _tts.stop();
      await _stt.start();
      phrase = await _stt.finalResult();
    } catch (e) {
      _warning = e is SpeechError
          ? e.message
          : 'Не удалось включить микрофон: $e';
    } finally {
      await _partialSubscription?.cancel();
      _partialSubscription = null;
      await _levelSubscription?.cancel();
      _levelSubscription = null;
      if (!_disposed) soundLevel.value = 0;
      _listening = false;
      _partialText = '';
    }

    if (phrase.trim().isEmpty) {
      // Тишина — не ошибка и не команда. Молча возвращаемся в покой.
      _machine.abortListening();
      await _resumeNativeWake();
      notifyListeners();
      return;
    }

    await submit(phrase, alreadyListening: true, voiceFollowUp: true);
  }

  Future<void> stopListening() async {
    if (!_listening) return;
    await _stt.stop();
  }

  // --- Команда ---------------------------------------------------------------

  /// Основной вход: распознанная или введённая фраза.
  Future<void> submit(
    String text, {
    bool alreadyListening = false,
    bool voiceFollowUp = false,
  }) async {
    final phrase = text.trim();
    if (phrase.isEmpty || _busy || _listening) return;

    if (!alreadyListening) _machine.startListening();

    final firstInConversation = _current.isEmpty;

    _busy = true;
    _append(ChatMessage(text: phrase, fromUser: true, at: DateTime.now()));

    try {
      await _releaseWakeMic();
      await _pauseWake(true);
      await _tts.stop();
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
      notifyListeners();

      // Озвучка после обновления экрана: текст пользователь видит сразу,
      // не дожидаясь конца фразы синтезатора.
      if (!turn.alreadySpoken) {
        try {
          await _tts.speak(turn.response);
        } catch (_) {
          _warning =
              'Ответ показан в чате. Для озвучки установите русский офлайн-голос Android.';
        }
      }
    } catch (_) {
      _machine.reset();
      _warning =
          'Не удалось завершить команду. Проверьте разрешения и повторите.';
      _append(
        ChatMessage(
          text: _warning!,
          fromUser: false,
          at: DateTime.now(),
          status: SkillStatus.failed,
        ),
      );
    } finally {
      _busy = false;
      await _resumeNativeWake();
      if (!_disposed) notifyListeners();
    }
    if (voiceFollowUp && state.isAwaiting && !_disposed) await listen();
  }

  /// Кнопка «отмена» (ТЗ, FR-9) — то же, что фраза «отмена».
  Future<void> cancel() async {
    _machine.reset();
    await _tts.stop();
    await stopListening();
    await submit('отмена');
  }

  /// «Озвучить» под ответом: сказать его ещё раз, даже если голосовые
  /// ответы выключены.
  Future<void> speakAgain(String text) async {
    if (_busy || _listening) return;
    final enabled = _tts.enabled;
    _tts.enabled = true;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Нет голоса — ответ и так на экране.
    } finally {
      _tts.enabled = enabled;
    }
  }

  void setTtsEnabled(bool value) {
    _tts.enabled = value; // ТЗ, FR-11
    notifyListeners();
  }

  void dismissWarning() {
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
    _wakeInterrupted = true;
    _handsFree?.dispose();
    _partialSubscription?.cancel();
    _levelSubscription?.cancel();
    soundLevel.dispose();
    unawaited(_disposeVoice());
    super.dispose();
  }

  Future<void> _disposeVoice() async {
    try {
      await _initFuture;
    } catch (_) {
      // Инициализация могла завершиться ошибкой при закрытии экрана.
    }
    await _stt.stop();
    await _stt.dispose();
  }
}
