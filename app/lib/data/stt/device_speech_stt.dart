import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../domain/ports/speech_to_text.dart';

/// Распознавание речи через системный движок Android (ТЗ, FR-2).
///
/// Сначала просится распознавание на устройстве. Если офлайн-пакета русского
/// языка нет, движок отвечает ошибкой языка, и тогда та же фраза тут же
/// переслушивается обычным системным распознавателем: иначе на телефоне без
/// скачанного пакета голос не работал бы вовсе. Само приложение в сеть
/// по-прежнему не ходит — распознавание идёт в чужом процессе.
///
/// Это не конечная реализация. По ТЗ распознавать должна T-one через
/// sherpa-onnx: она точнее на именах собственных. Интерфейс тот же, поэтому
/// замена не затронет ни ядро, ни экран. Подробности — docs/speech.md.
class DeviceSpeechStt implements SpeechToText {
  DeviceSpeechStt({
    this.localePrefix = 'ru',
    this.fallbackLocale = 'ru_RU',
    this.pauseFor = const Duration(milliseconds: 1500),
    this.listenFor = const Duration(seconds: 20),
  });

  /// Какой язык искать среди установленных на устройстве.
  final String localePrefix;

  /// Язык, если движок не сказал, какие у него есть. Список языков на
  /// Android 13+ содержит только скачанные офлайн-пакеты и бывает пуст,
  /// хотя обычное распознавание русский понимает.
  final String fallbackLocale;

  /// Сколько тишины считать концом фразы. Меньше — и движок обрывает
  /// человека на вдохе между «Макс» и командой.
  final Duration pauseFor;

  /// Предел одной фразы: команда ассистенту не бывает длинной.
  final Duration listenFor;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final StreamController<String> _partial =
      StreamController<String>.broadcast();
  final StreamController<double> _levels = StreamController<double>.broadcast();

  /// Ожидание текущей фразы. Живёт до следующего start(), а не до
  /// завершения: движок может отдать финальный результат раньше, чем
  /// вызывающий успеет спросить finalResult(), и тогда ответ потерялся бы.
  Completer<String>? _pending;

  /// Микрофон открыт.
  bool _active = false;

  /// Просить ли офлайн-распознавание. Сбрасывается, если движок ответил,
  /// что офлайн-языка нет.
  bool _onDevice = true;

  bool _available = false;
  String _localeId = 'ru_RU';
  String? _lastError;

  /// Движок готов.
  bool get isAvailable => _available;

  /// Почему распознавание недоступно — для сообщения на экране.
  String? get lastError => _lastError;

  /// Язык распознавания, например `ru_RU`.
  String get localeId => _localeId;

  @override
  Future<void> init() async {
    _available = await _speech.initialize(
      onError: _onError,
      onStatus: (status) {
        // Движок замолчал сам. Финальный результат приходит до 'done',
        // поэтому здесь закрываем только то, что осталось без ответа.
        if (status == 'done') _finish(null);
      },
    );

    if (!_available) {
      _lastError = 'Нет доступа к микрофону или системному распознаванию речи';
      throw SpeechError(_lastError!);
    }

    _localeId = fallbackLocale;
    try {
      // На Android 13+ плагин иногда вообще не отвечает на этот вопрос.
      final locales = await _speech.locales().timeout(
        const Duration(seconds: 3),
      );
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith(localePrefix)) {
          _localeId = locale.localeId;
          break;
        }
      }
    } catch (_) {
      // Не знаем, что установлено, — говорим по-русски по умолчанию.
    }
  }

  @override
  Stream<String> partialResults() => _partial.stream;

  @override
  Stream<double> soundLevels() => _levels.stream;

  /// Android отдаёт RMS в децибелах, примерно от -2 (тишина) до 10 (громко).
  void _onSoundLevel(double db) {
    if (_levels.isClosed) return;
    _levels.add(((db + 2) / 12).clamp(0.0, 1.0));
  }

  @override
  Future<void> start() async {
    if (!_available) {
      throw SpeechError(_lastError ?? 'Распознавание недоступно');
    }
    if (_active) return; // уже слушаем

    _lastError = null;
    _pending = Completer<String>();
    await _listen();
  }

  @override
  Future<void> startWake() => start();

  Future<void> _listen() async {
    _active = true;
    _lastText = '';
    try {
      await _speech.listen(
        onResult: _onResult,
        onSoundLevelChange: _onSoundLevel,
        listenOptions: stt.SpeechListenOptions(
          onDevice: _onDevice,
          partialResults: true,
          cancelOnError: true,
          localeId: _localeId,
          pauseFor: pauseFor,
          listenFor: listenFor,
        ),
      );
    } catch (e) {
      _fail('Не удалось включить микрофон: $e');
    }
  }

  /// Последний услышанный текст: им закрывается ожидание, если движок
  /// завершился, не пометив результат финальным.
  String _lastText = '';

  void _onResult(SpeechRecognitionResult result) {
    _lastText = result.recognizedWords;
    if (!_partial.isClosed) _partial.add(_lastText);
    if (result.finalResult) _finish(_lastText);
  }

  void _onError(SpeechRecognitionError error) {
    final code = error.errorMsg;
    // Тишина и «ничего не разобрал» — обычный конец фразы, не сбой.
    if (code == 'error_no_match' || code == 'error_speech_timeout') {
      _finish(null);
      return;
    }
    // Офлайн-пакета нет: переслушиваем фразу обычным распознавателем.
    if (_onDevice &&
        (code == 'error_language_unavailable' ||
            code == 'error_language_not_supported')) {
      _onDevice = false;
      final pending = _pending;
      if (pending != null && !pending.isCompleted) {
        unawaited(_listen());
        return;
      }
    }
    _fail(_describe(code));
  }

  static String _describe(String code) => switch (code) {
    'error_permission' ||
    'error_insufficient_permissions' => 'Нет разрешения на микрофон',
    'error_busy' ||
    'error_recognizer_busy' => 'Микрофон занят другим приложением',
    'error_audio_error' => 'Не удалось записать звук с микрофона',
    'error_language_unavailable' || 'error_language_not_supported' =>
      'Русский язык распознавания не установлен. Скачайте его в настройках '
          'Android: Язык и ввод → Распознавание речи',
    'error_network' ||
    'error_network_timeout' ||
    'error_server' ||
    'error_server_disconnected' =>
      'Распознаватель Android недоступен. Скачайте русский офлайн-пакет '
          'в настройках распознавания речи',
    'error_speech_recognizer_disabled' =>
      'Распознавание речи отключено в настройках Android',
    _ => 'Не удалось распознать речь ($code)',
  };

  /// [text] == null означает «взять то, что успели услышать».
  void _finish(String? text) {
    _active = false;
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    pending.complete(text ?? _lastText);
  }

  void _fail(String message) {
    _active = false;
    _lastError = message;
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    // Если что-то уже услышали — отдаём это, а не ошибку.
    if (_lastText.trim().isNotEmpty) {
      pending.complete(_lastText);
    } else {
      pending.completeError(SpeechError(message));
    }
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
    _finish('');
    await _speech.cancel();
  }

  @override
  Future<void> dispose() async {
    await _speech.cancel();
    _finish('');
    await _partial.close();
    await _levels.close();
  }
}
