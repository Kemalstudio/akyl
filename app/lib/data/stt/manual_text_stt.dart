import 'dart:async';

import '../../domain/ports/speech_to_text.dart';

/// Заглушка распознавания на этап 1: текст вводится с клавиатуры.
///
/// Нужна, чтобы весь конвейер — NLU, поиск контакта, навыки, диалог — работал и
/// проверялся до того, как подключён sherpa-onnx (этап 2). Реализует тот же
/// интерфейс, поэтому замена на VoskStt/TOneStt не трогает ни ядро, ни UI.
class ManualTextStt implements SpeechToText {
  final _partial = StreamController<String>.broadcast();
  final _completerLock = <Completer<String>>[];

  @override
  Future<void> init() async {}

  @override
  Stream<String> partialResults() => _partial.stream;

  @override
  Future<void> start() async {}

  /// Ждёт, пока UI вызовет [submit].
  @override
  Future<String> finalResult() {
    final c = Completer<String>();
    _completerLock.add(c);
    return c.future;
  }

  @override
  Future<void> stop() async {
    for (final c in _completerLock) {
      if (!c.isCompleted) c.complete('');
    }
    _completerLock.clear();
  }

  /// Вызывается из UI: имитирует промежуточный и финальный результат.
  void submit(String text) {
    _partial.add(text);
    for (final c in _completerLock) {
      if (!c.isCompleted) c.complete(text);
    }
    _completerLock.clear();
  }

  @override
  Future<void> dispose() async {
    await _partial.close();
  }
}
