import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:akyl/data/voice/tone_worker.dart';
import 'package:akyl/domain/ports/voice_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Модели и изолят конвейера с настройками приложения.
///
/// Нужны модели в assets/models (их кладёт tools/fetch_models.ps1) и
/// Windows-сборка sherpa-onnx из кэша pub. Без них тест пропускается.
void main() {
  const paths = ToneModelPaths(
    model: 'assets/models/tone.onnx',
    tokens: 'assets/models/tokens.txt',
    vad: 'assets/models/silero_vad.onnx',
  );
  final native = Directory(
    '${Platform.environment['LOCALAPPDATA']}/Pub/Cache/hosted/pub.dev/'
    'sherpa_onnx_windows-1.13.8/windows',
  );
  final available =
      Platform.isWindows &&
      File(paths.model).existsSync() &&
      native.existsSync();

  setUpAll(() {
    if (!available) return;
    // В Windows 11 есть своя onnxruntime.dll (старше нужной), и загрузчик
    // берёт её. Загружаем версию из пакета первой — дальше берётся она.
    DynamicLibrary.open('${native.path}/onnxruntime.dll');
  });

  test('модели загружаются и переживают тишину и шум', () {
    sherpa.initBindings(native.path);
    final asr = ToneAsr(paths);
    final vad = SherpaVad(paths);

    // Секунда тишины: VAD молчит, текста нет.
    final silence = Float32List(micSampleRate);
    for (var i = 0; i + 512 <= silence.length; i += 512) {
      vad.accept(Float32List.sublistView(silence, i, i + 512));
    }
    expect(vad.speech, isFalse);

    asr.accept(silence);
    final random = math.Random(1);
    final noise = Float32List.fromList([
      for (var i = 0; i < micSampleRate; i++) (random.nextDouble() - .5) * .02,
    ]);
    asr.accept(noise);
    asr.flush();
    expect(asr.text, isEmpty);

    // Новый порог VAD пересоздаёт детектор, а не ломает его.
    vad.setThreshold(0.4);
    vad.accept(Float32List(512));
    expect(vad.speech, isFalse);

    asr.free();
    vad.free();
  }, skip: !available);

  test('изолят: ожидание обращения не заканчивается от тишины, '
      'команда — заканчивается пустым результатом', () async {
    final incoming = ReceivePort();
    final messages = incoming.asBroadcastStream();
    final readyFuture = messages
        .firstWhere((m) => m is List && m[0] == 'ready')
        .timeout(const Duration(seconds: 60));
    final isolate = await Isolate.spawn(toneWorkerMain, [
      incoming.sendPort,
      paths,
      native.path,
    ]);
    try {
      final worker = (await readyFuture as List)[1] as SendPort;
      final finals = <FinalText>[];
      final sub = messages.listen((m) {
        if (m is FinalText) finals.add(m);
      });
      try {
        // Полсекунды 16-битной тишины кусками по 32 мс.
        void feedSilence(int seconds) {
          for (var i = 0; i < seconds * 1000 ~/ 32; i++) {
            worker.send(['pcm', Uint8List(1024)]);
          }
        }

        worker.send(['mode', 1, PipelineMode.wake.index, 8000]);
        feedSilence(10);
        // Сообщения изолята обрабатываются по порядку: смена режима после
        // тишины придёт, когда вся тишина уже разобрана.
        worker.send(['mode', 2, PipelineMode.command.index, 2000]);
        feedSilence(3);
        final done =
            await messages
                    .firstWhere((m) => m is FinalText && m.epoch == 2)
                    .timeout(const Duration(seconds: 20))
                as FinalText;
        expect(done.text, isEmpty);
        expect(finals.where((f) => f.epoch == 1), isEmpty);
      } finally {
        await sub.cancel();
        worker.send(['dispose']);
      }
    } finally {
      isolate.kill(priority: Isolate.immediate);
      incoming.close();
    }
  }, skip: !available);
}
