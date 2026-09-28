import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../domain/ports/speech_to_text.dart';

/// Распознавание речи на устройстве через системный движок Android (ТЗ, FR-2).
///
/// Режим `onDevice: true` означает буквально следующее: если офлайн-движка нет,
/// попытка **провалится**, а не уйдёт в сеть. Это и есть гарантия приватности,
/// которую даёт ТЗ, — сильнее, чем отсутствие разрешения INTERNET у самого
/// приложения, потому что распознавание идёт в чужом процессе.
///
/// Это не конечная реализация. По ТЗ распознавать должна T-one через
/// sherpa-onnx: она точнее на именах собственных, а имя — это ровно то, что
/// произносят в команде «позвони Ахмеду». Здесь тот же интерфейс, поэтому
/// замена не затронет ни ядро, ни экран. Подробности — docs/speech.md.
class DeviceSpeechStt implements SpeechToText {
  DeviceSpeechStt({
    this.localePrefix = 'ru',
    this.pauseFor = const Duration(milliseconds: 900),
    this.listenFor = const Duration(seconds: 20),
  });

  /// Какой язык искать среди установленных на устройстве.
  final String localePrefix;

  /// Сколько тишины считать концом фразы.
  ///
  /// ТЗ отводит на это 300 мс, но здесь пауза длиннее: системный движок сам
  /// решает, когда фраза закончилась, а этот таймер — страховка поверх него.
  /// Поставить 300 мс значит обрывать человека на вдохе. Настоящие 300 мс
  /// даст Silero VAD, когда распознавание переедет на sherpa-onnx.
  final Duration pauseFor;

  /// Предел одной фразы: команда ассистенту не бывает длинной.
  final Duration listenFor;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final StreamController<String> _partial = StreamController<String>.broadcast();

  /// Ожидание текущей фразы. Живёт до следующего start(), а не до
  /// завершения: движок может отдать финальный результат раньше, чем
  /// вызывающий успеет спросить finalResult(), и тогда ответ потерялся бы.
  Completer<String>? _pending;

  /// Микрофон открыт.
  bool _active = false;

  bool _available = false;
  String? _localeId;
  String? _lastError;

  /// Движок готов и офлайн-язык найден.
  bool get isAvailable => _available;

  /// Почему распознавание недоступно — для сообщения на экране.
  String? get lastError => _lastError;

  /// Найденный язык, например `ru_RU`. null — если русского на устройстве нет.
  String? get localeId => _localeId;

  @override
  Future<void> init() async {
    _available = await _speech.initialize(
      onError: (e) {
        _lastError = e.errorMsg;
        // Ошибка приходит вместо финального результата — иначе start()
        // будет ждать вечно.
        _finish('');
      },
      onStatus: (status) {
        // Движок замолчал сам, не отдав результата, — закрываем ожидание.
        if (status == 'done' || status == 'notListening') _finish(null);
      },
    );

    if (!_available) {
      _lastError ??= 'Системное распознавание речи недоступно';
      return;
    }

    final locales = await _speech.locales();
    for (final locale in locales) {
      if (!locale.localeId.toLowerCase().startsWith(localePrefix)) continue;
      _localeId = locale.localeId;
      break;
    }
    if (_localeId == null) {
      _available = false;
      _lastError = 'На устройстве нет русского языка для распознавания';
    }
  }

  @override
  Stream<String> partialResults() => _partial.stream;

  @override
  Future<void> start() async {
    if (!_available) {
      throw StateError(_lastError ?? 'Распознавание недоступно');
    }
    if (_active) return; // уже слушаем

    _lastError = null;
    _active = true;
    _pending = Completer<String>();
    _lastText = '';

    await _speech.listen(
      onResult: _onResult,
      listenOptions: stt.SpeechListenOptions(
        // Только на устройстве. Если офлайн-движка нет — пусть падает.
        onDevice: true,
        partialResults: true,
        cancelOnError: true,
        localeId: _localeId,
        pauseFor: pauseFor,
        listenFor: listenFor,
      ),
    );
  }

  /// Последний услышанный текст: им закрывается ожидание, если движок
  /// завершился, не пометив результат финальным.
  String _lastText = '';

  void _onResult(SpeechRecognitionResult result) {
    _lastText = result.recognizedWords;
    if (!_partial.isClosed) _partial.add(_lastText);
    if (result.finalResult) _finish(_lastText);
  }

  /// [text] == null означает «взять то, что успели услышать».
  void _finish(String? text) {
    _active = false;
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    pending.complete(text ?? _lastText);
  }

  @override
  Future<String> finalResult() {
    final pending = _pending;
    if (pending == null) return Future.value('');
    return pending.future;
  }

  @override
  Future<void> stop() async {
    if (!_active) return;
    await _speech.cancel();
    _finish('');
  }

  @override
  Future<void> dispose() async {
    await _speech.cancel();
    _finish('');
    await _partial.close();
  }
}
