import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/dialog/dialog_machine.dart';
import '../domain/dialog/dialog_state.dart';
import '../domain/entities/skill_result.dart';
import '../domain/ports/contact_resolver.dart';
import '../domain/ports/phone.dart';
import '../domain/ports/speech_to_text.dart';
import '../domain/ports/text_to_speech.dart';

/// Одна реплика в истории команд (ТЗ, FR-10). Хранится только в памяти
/// процесса — на диск история не пишется.
class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.fromUser,
    required this.at,
    this.status,
  });

  final String text;
  final bool fromUser;
  final DateTime at;

  /// Чем закончился ход ассистента — по нему экран выбирает акцент.
  final SkillStatus? status;
}

/// Связывает автомат диалога с экраном: микрофон, история, разрешения, озвучка.
class AssistantController extends ChangeNotifier {
  AssistantController({
    required DialogMachine machine,
    required ContactResolver resolver,
    required TextToSpeech tts,
    required SpeechToText stt,
    required Phone phone,
  })  : _machine = machine,
        _resolver = resolver,
        _tts = tts,
        _stt = stt,
        _phone = phone;

  final DialogMachine _machine;
  final ContactResolver _resolver;
  final TextToSpeech _tts;
  final SpeechToText _stt;
  final Phone _phone;

  final List<ChatMessage> _history = [];
  List<ChatMessage> get history => List.unmodifiable(_history);

  DialogState get state => _machine.state;

  bool get ttsEnabled => _tts.enabled;

  /// Разрешения выданы: без них ассистент бесполезен, поэтому экран
  /// приветствия не пропускает дальше, пока их нет.
  bool _permissionsGranted = false;
  bool get permissionsGranted => _permissionsGranted;

  /// Контакты недоступны или распознавание не запустилось — полоса сверху.
  String? _warning;
  String? get warning => _warning;

  bool _busy = false;
  bool get busy => _busy;

  bool _ready = false;
  bool get ready => _ready;

  /// Микрофон открыт прямо сейчас.
  bool _listening = false;
  bool get listening => _listening;

  /// Текст, который распознаётся в эту секунду (ТЗ, FR-2: вывод во время речи).
  String _partialText = '';
  String get partialText => _partialText;

  /// Распознавание речи доступно на этом устройстве.
  bool _voiceAvailable = false;
  bool get voiceAvailable => _voiceAvailable;

  StreamSubscription<String>? _partialSubscription;

  /// Проверка при старте: если разрешения уже выданы, экран приветствия
  /// пропускается — второй раз то же самое спрашивать незачем.
  Future<void> init() async {
    await _tts.init();
    _permissionsGranted = await _phone.hasPermissions();
    if (_permissionsGranted) {
      await _buildIndex();
      await _initVoice();
    }
    _ready = true;
    notifyListeners();
  }

  /// Запрос разрешений с экрана приветствия. Возвращает, выданы ли они.
  Future<bool> requestPermissions() async {
    _permissionsGranted = await _phone.requestPermissions();
    if (_permissionsGranted) {
      await _buildIndex();
      await _initVoice();
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

  /// Микрофон — не обязательное условие работы: команду всегда можно набрать.
  /// Поэтому отказ здесь не ломает приложение, а лишь прячет кнопку записи.
  Future<void> _initVoice() async {
    try {
      await _stt.init();
      _voiceAvailable = true;
    } catch (e) {
      _voiceAvailable = false;
      _warning ??= 'Голос недоступен: $e. Команду можно набрать текстом';
    }
  }

  /// Нажата кнопка записи (ТЗ, FR-1): слушаем до конца фразы и выполняем её.
  Future<void> listen() async {
    if (_busy || _listening) return;

    if (!_voiceAvailable) {
      _warning = 'Распознавание речи на этом устройстве недоступно';
      notifyListeners();
      return;
    }

    // Ассистент не должен слышать собственный голос.
    await _tts.stop();

    _listening = true;
    _partialText = '';
    _machine.startListening();
    notifyListeners();

    _partialSubscription = _stt.partialResults().listen((text) {
      _partialText = text;
      notifyListeners();
    });

    String phrase = '';
    try {
      await _stt.start();
      phrase = await _stt.finalResult();
    } catch (e) {
      _warning = 'Не удалось включить микрофон: $e';
    } finally {
      await _partialSubscription?.cancel();
      _partialSubscription = null;
      _listening = false;
      _partialText = '';
    }

    if (phrase.trim().isEmpty) {
      // Тишина — не ошибка и не команда. Молча возвращаемся в покой.
      _machine.abortListening();
      notifyListeners();
      return;
    }

    await submit(phrase, alreadyListening: true);
  }

  /// Прервать запись, ничего не выполняя.
  Future<void> stopListening() async {
    if (!_listening) return;
    await _stt.stop();
  }

  /// Основной вход: распознанная или введённая фраза.
  Future<void> submit(String text, {bool alreadyListening = false}) async {
    final phrase = text.trim();
    if (phrase.isEmpty || _busy) return;

    if (!alreadyListening) _machine.startListening();

    _busy = true;
    _append(ChatMessage(text: phrase, fromUser: true, at: DateTime.now()));

    final turn = await _machine.handle(phrase);

    _append(ChatMessage(
      text: turn.response,
      fromUser: false,
      at: DateTime.now(),
      status: turn.status,
    ));
    _busy = false;
    notifyListeners();

    // Озвучка после обновления экрана: текст пользователь видит сразу,
    // не дожидаясь конца фразы синтезатора.
    await _tts.speak(turn.response);
  }

  /// Кнопка «отмена» (ТЗ, FR-9) — то же, что фраза «отмена».
  Future<void> cancel() async {
    await _tts.stop();
    await stopListening();
    await submit('отмена');
  }

  void setTtsEnabled(bool value) {
    _tts.enabled = value; // ТЗ, FR-11
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  void dismissWarning() {
    _warning = null;
    notifyListeners();
  }

  void _append(ChatMessage m) {
    _history.add(m);
    notifyListeners();
  }

  @override
  void dispose() {
    _partialSubscription?.cancel();
    _stt.dispose();
    super.dispose();
  }
}
