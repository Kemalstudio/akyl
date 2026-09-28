import 'package:flutter/foundation.dart';

import '../domain/dialog/dialog_machine.dart';
import '../domain/dialog/dialog_state.dart';
import '../domain/entities/skill_result.dart';
import '../domain/ports/contact_resolver.dart';
import '../domain/ports/phone.dart';
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

/// Связывает автомат диалога с экраном: история, состояние, разрешения, озвучка.
class AssistantController extends ChangeNotifier {
  AssistantController({
    required DialogMachine machine,
    required ContactResolver resolver,
    required TextToSpeech tts,
    required Phone phone,
  })  : _machine = machine,
        _resolver = resolver,
        _tts = tts,
        _phone = phone;

  final DialogMachine _machine;
  final ContactResolver _resolver;
  final TextToSpeech _tts;
  final Phone _phone;

  final List<ChatMessage> _history = [];
  List<ChatMessage> get history => List.unmodifiable(_history);

  DialogState get state => _machine.state;

  bool get ttsEnabled => _tts.enabled;

  /// Разрешения выданы: без них ассистент бесполезен, поэтому экран
  /// приветствия не пропускает дальше, пока их нет.
  bool _permissionsGranted = false;
  bool get permissionsGranted => _permissionsGranted;

  /// Контакты недоступны или разрешения отозваны — показывается полосой сверху.
  String? _warning;
  String? get warning => _warning;

  bool _busy = false;
  bool get busy => _busy;

  bool _ready = false;
  bool get ready => _ready;

  /// Проверка при старте: если разрешения уже выданы, экран приветствия
  /// пропускается — второй раз то же самое спрашивать незачем.
  Future<void> init() async {
    await _tts.init();
    _permissionsGranted = await _phone.hasPermissions();
    if (_permissionsGranted) await _buildIndex();
    _ready = true;
    notifyListeners();
  }

  /// Запрос разрешений с экрана приветствия. Возвращает, выданы ли они.
  Future<bool> requestPermissions() async {
    _permissionsGranted = await _phone.requestPermissions();
    if (_permissionsGranted) await _buildIndex();
    notifyListeners();
    return _permissionsGranted;
  }

  Future<void> _buildIndex() async {
    try {
      await _resolver.buildIndex();
      _warning = null;
    } catch (_) {
      _warning = 'Контакты недоступны — разрешите доступ к адресной книге';
    }
  }

  /// Ассистент слушает (ТЗ, FR-1). На этапе 1 фраза приходит с клавиатуры.
  void startListening() {
    if (_machine.state == DialogState.idle) _machine.startListening();
    notifyListeners();
  }

  /// Основной вход: распознанная или введённая фраза.
  Future<void> submit(String text) async {
    final phrase = text.trim();
    if (phrase.isEmpty || _busy) return;

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

  void _append(ChatMessage m) {
    _history.add(m);
    notifyListeners();
  }
}
