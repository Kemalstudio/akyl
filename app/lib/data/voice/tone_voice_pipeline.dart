import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/ports/speech_to_text.dart';
import '../../domain/ports/voice_pipeline.dart';
import 'tone_worker.dart';
import 'voice_log.dart';

/// Конвейер на своей модели T-one и Silero VAD — целиком в процессе
/// приложения, без чужих движков и без сети.
///
/// Микрофон пишет MicHub.kt (один AudioRecord на процесс). Подписка на канал
/// открывает запись, отписка — закрывает; между фразами запись не
/// переоткрывается.
class ToneVoicePipeline implements VoicePipeline {
  ToneVoicePipeline({this.assetDir = 'assets/models', VoiceLog? log})
    : _log = log ?? VoiceLog.instance;

  final String assetDir;
  final VoiceLog _log;

  /// Меняется вместе с моделью — тогда файлы копируются заново.
  static const _modelVersion = 'tone-2025-09-08+silero-v4';

  static const _mic = EventChannel('dev.akyl/mic');

  final _events = StreamController<PipelineEvent>.broadcast();

  Isolate? _isolate;
  ReceivePort? _fromWorker;
  SendPort? _toWorker;
  StreamSubscription<Object?>? _audio;
  MicConfig? _micConfig;

  /// Открытие и закрытие идут строго по очереди: иначе быстрый «вкл-выкл»
  /// мог бы оставить за собой вторую подписку на микрофон.
  Future<void> _micOps = Future.value();

  int _epoch = 0;
  PipelineConfig _config = const PipelineConfig();
  bool _levels = false;

  @override
  bool get ready => _toWorker != null;

  @override
  bool get micOpen => _audio != null;

  @override
  Stream<PipelineEvent> get events => _events.stream;

  @override
  Future<void> init() async {
    if (ready) return;
    if (!Platform.isAndroid) {
      throw const SpeechError('Своё распознавание работает только на Android');
    }
    final watch = Stopwatch()..start();
    final paths = await _prepareModels();

    final fromWorker = ReceivePort();
    _fromWorker = fromWorker;
    final readyCompleter = Completer<SendPort>();
    fromWorker.listen((message) {
      if (message is PipelineEvent) {
        if (!_events.isClosed) _events.add(message);
        return;
      }
      final m = message as List<Object?>;
      switch (m[0]) {
        case 'ready':
          if (!readyCompleter.isCompleted) {
            readyCompleter.complete(m[1] as SendPort);
          }
        case 'error':
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(SpeechError('${m[1]}'));
          }
      }
    });
    try {
      _isolate = await Isolate.spawn(toneWorkerMain, [
        fromWorker.sendPort,
        paths,
      ], debugName: 'voice-pipeline');
      // Модель на 140 МБ грузится несколько секунд.
      _toWorker = await readyCompleter.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () =>
            throw const SpeechError('Модель распознавания не загрузилась'),
      );
      _toWorker!.send(['config', _config]);
      _toWorker!.send(['levels', _levels]);
      _log.add(
        VoiceTag.stt,
        'T-one и Silero VAD готовы за ${watch.elapsedMilliseconds} мс',
      );
    } catch (e) {
      fromWorker.close();
      _fromWorker = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _log.add(VoiceTag.stt, 'модель не загрузилась: $e');
      rethrow;
    }
  }

  /// Копирует модели из APK в папку приложения, один раз на версию:
  /// sherpa-onnx читает модель по пути к файлу.
  Future<ToneModelPaths> _prepareModels() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/models');
    final paths = ToneModelPaths(
      model: '${dir.path}/tone.onnx',
      tokens: '${dir.path}/tokens.txt',
      vad: '${dir.path}/silero_vad.onnx',
    );
    final marker = File('${dir.path}/version');
    if (marker.existsSync() &&
        marker.readAsStringSync() == _modelVersion &&
        File(paths.model).existsSync() &&
        File(paths.tokens).existsSync() &&
        File(paths.vad).existsSync()) {
      return paths;
    }

    await dir.create(recursive: true);
    Future<void> copy(String asset, String target) async {
      final data = await rootBundle.load('$assetDir/$asset');
      await File(target).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    await copy('silero_vad.onnx', paths.vad);
    await copy('tokens.txt', paths.tokens);
    await copy('tone.onnx', paths.model);
    await marker.writeAsString(_modelVersion);
    return paths;
  }

  @override
  Future<void> open(MicConfig mic) => _micOps = _micOps.then((_) async {
    if (!ready) throw const SpeechError('Распознавание не готово');
    if (_audio != null && _micConfig == mic) return;
    if (_audio != null) await _closeNow();
    _micConfig = mic;
    _audio = _mic
        .receiveBroadcastStream(mic.toMap())
        .listen(
          (data) {
            if (data is Uint8List) _toWorker?.send(['pcm', data]);
          },
          onError: (Object error) {
            final message = error is PlatformException
                ? error.message ?? 'Микрофон недоступен'
                : 'Микрофон недоступен';
            final fatal =
                error is PlatformException && error.code == 'PERMISSION';
            _log.add(VoiceTag.audio, 'ошибка микрофона: $message');
            // Запись уже мертва — подписку снимаем сразу, иначе повторное
            // открытие решило бы, что всё в порядке.
            final failed = _audio;
            _audio = null;
            _micConfig = null;
            unawaited(failed?.cancel());
            // Сбой микрофона касается любого режима, поэтому номер текущий.
            if (!_events.isClosed) {
              _events.add(PipelineFailure(_epoch, message, fatal: fatal));
            }
          },
          cancelOnError: true,
        );
    _log.add(
      VoiceTag.audio,
      'микрофон открыт (AEC ${mic.echoCancellation ? 'вкл' : 'выкл'}, '
      'NS ${mic.noiseSuppression ? 'вкл' : 'выкл'})',
    );
  });

  @override
  Future<void> close() => _micOps = _micOps.then((_) => _closeNow());

  Future<void> _closeNow() async {
    final audio = _audio;
    if (audio == null) return;
    _audio = null;
    _micConfig = null;
    // Звук после закрытия не нужен: режим «тишина» до следующего открытия.
    _sendMode(PipelineMode.muted, 0);
    await audio.cancel();
    _log.add(VoiceTag.audio, 'микрофон закрыт');
  }

  @override
  int setMode(PipelineMode mode, {int noSpeechMs = 8000}) =>
      _sendMode(mode, noSpeechMs);

  int _sendMode(PipelineMode mode, int noSpeechMs) {
    final epoch = ++_epoch;
    _toWorker?.send(['mode', epoch, mode.index, noSpeechMs]);
    return epoch;
  }

  @override
  void configure(PipelineConfig config) {
    if (config == _config) return;
    _config = config;
    _toWorker?.send(['config', config]);
  }

  @override
  void setLevelsEnabled(bool enabled) {
    if (enabled == _levels) return;
    _levels = enabled;
    _toWorker?.send(['levels', enabled]);
  }

  @override
  Future<void> dispose() async {
    await close();
    await _micOps;
    _toWorker?.send(['dispose']);
    _toWorker = null;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _fromWorker?.close();
    _fromWorker = null;
    await _events.close();
  }
}
