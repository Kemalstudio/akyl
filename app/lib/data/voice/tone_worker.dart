import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../domain/ports/voice_pipeline.dart';
import 'pipeline_core.dart';

/// Частота, на которой обучена T-one (телефонная речь). Silero VAD принимает
/// 16 кГц, и T-one получает тот же звук: sherpa сама понижает его до 8 кГц.
const int toneSampleRate = 8000;
const int micSampleRate = PipelineCore.sampleRate;

/// Пути к моделям на диске телефона.
class ToneModelPaths {
  const ToneModelPaths({
    required this.model,
    required this.tokens,
    required this.vad,
  });

  final String model, tokens, vad;
}

/// T-one в потоковом режиме. Концы фраз определяет VAD, а не правила
/// распознавателя: так пауза настраивается одним числом в настройках.
sherpa.OnlineRecognizer createToneRecognizer(ToneModelPaths paths) =>
    sherpa.OnlineRecognizer(
      sherpa.OnlineRecognizerConfig(
        feat: const sherpa.FeatureConfig(sampleRate: toneSampleRate),
        model: sherpa.OnlineModelConfig(
          toneCtc: sherpa.OnlineToneCtcModelConfig(model: paths.model),
          tokens: paths.tokens,
          numThreads: 2,
          debug: false,
        ),
        enableEndpoint: false,
      ),
    );

sherpa.VoiceActivityDetector createToneVad(
  ToneModelPaths paths, {
  double threshold = 0.5,
}) => sherpa.VoiceActivityDetector(
  config: sherpa.VadModelConfig(
    sileroVad: sherpa.SileroVadModelConfig(
      model: paths.vad,
      threshold: threshold,
      minSilenceDuration: PipelineCore.vadHangoverMs / 1000,
      minSpeechDuration: 0.15,
      windowSize: PipelineCore.window,
      maxSpeechDuration: 30,
    ),
    sampleRate: micSampleRate,
    debug: false,
  ),
  bufferSizeInSeconds: 30,
);

/// Silero VAD из sherpa-onnx. Готовые отрезки речи не нужны — T-one
/// получает звук потоком, — поэтому очередь отрезков сразу очищается.
class SherpaVad implements VadEngine {
  SherpaVad(this.paths, {double threshold = 0.5})
    : _threshold = threshold,
      _vad = createToneVad(paths, threshold: threshold);

  final ToneModelPaths paths;
  sherpa.VoiceActivityDetector _vad;
  double _threshold;

  /// Порог Silero задаётся при создании: новый порог — новый детектор.
  void setThreshold(double threshold) {
    if (threshold == _threshold) return;
    _vad.free();
    _threshold = threshold;
    _vad = createToneVad(paths, threshold: threshold);
  }

  @override
  void accept(Float32List window) {
    _vad.acceptWaveform(window);
    while (!_vad.isEmpty()) {
      _vad.pop();
    }
  }

  @override
  bool get speech => _vad.isDetected();

  @override
  void reset() => _vad.reset();

  void free() => _vad.free();
}

class ToneAsr implements AsrEngine {
  ToneAsr(ToneModelPaths paths) : recognizer = createToneRecognizer(paths) {
    stream = recognizer.createStream();
  }

  final sherpa.OnlineRecognizer recognizer;
  late final sherpa.OnlineStream stream;
  String _text = '';

  @override
  void reset() {
    recognizer.reset(stream);
    _text = '';
  }

  @override
  void accept(Float32List samples) {
    stream.acceptWaveform(samples: samples, sampleRate: micSampleRate);
    var decoded = false;
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
      decoded = true;
    }
    if (decoded) _text = recognizer.getResult(stream).text.trim();
  }

  @override
  void flush() {
    stream.inputFinished();
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    _text = recognizer.getResult(stream).text.trim();
  }

  @override
  String get text => _text;

  void free() {
    stream.free();
    recognizer.free();
  }
}

/// Конвейер в отдельном изоляте: расшифровка T-one заняла бы главный поток,
/// и интерфейс подтормаживал бы, пока человек говорит.
///
/// Сюда: `['pcm', Uint8List]`, `['mode', epoch, index, noSpeechMs]`,
/// `['config', PipelineConfig]`, `['levels', bool]`, `['dispose']`.
/// Отсюда: `['ready', SendPort]`, `['error', текст]`, события [PipelineEvent].
void toneWorkerMain(List<Object> args) {
  final toMain = args[0] as SendPort;
  final paths = args[1] as ToneModelPaths;
  final inbox = ReceivePort();

  late final SherpaVad vad;
  late final ToneAsr asr;
  try {
    if (args.length > 2) {
      sherpa.initBindings(args[2] as String);
    } else {
      sherpa.initBindings();
    }
    asr = ToneAsr(paths);
    vad = SherpaVad(paths);
  } catch (e) {
    toMain.send(['error', 'Не удалось загрузить модель распознавания: $e']);
    inbox.close();
    return;
  }

  final core = PipelineCore(vad: vad, asr: asr, emit: toMain.send);
  toMain.send(['ready', inbox.sendPort]);

  inbox.listen((message) {
    final m = message as List<Object?>;
    switch (m[0]) {
      case 'pcm':
        core.feedPcm16(m[1] as Uint8List);
      case 'mode':
        core.setMode(
          m[1] as int,
          PipelineMode.values[m[2] as int],
          noSpeechMs: m[3] as int,
        );
      case 'config':
        final config = m[1] as PipelineConfig;
        vad.setThreshold(config.speechThreshold);
        core.configure(config);
      case 'levels':
        core.levelsEnabled = m[1] as bool;
      case 'dispose':
        asr.free();
        vad.free();
        inbox.close();
    }
  });
}
