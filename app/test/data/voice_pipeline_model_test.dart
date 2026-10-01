import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:akyl/data/nlu/rule_based_nlu.dart';
import 'package:akyl/data/voice/pipeline_core.dart';
import 'package:akyl/domain/entities/dialog_context.dart';
import 'package:akyl/domain/entities/intent.dart';
import 'package:akyl/data/voice/tone_worker.dart';
import 'package:akyl/domain/ports/voice_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Конвейер на настоящих моделях: русская речь синтезируется Piper,
/// распознаётся Silero VAD + T-one через тот же PipelineCore, что на телефоне.
///
/// Нужны модели (tools/fetch_models.ps1, models/vits-piper-ru_RU-denis-medium)
/// и Windows-сборка sherpa-onnx из кэша pub. Без них тест пропускается.
void main() {
  const paths = ToneModelPaths(
    model: 'assets/models/tone.onnx',
    tokens: 'assets/models/tokens.txt',
    vad: 'assets/models/silero_vad.onnx',
  );
  const piper = '../models/vits-piper-ru_RU-denis-medium';
  final native = Directory(
    '${Platform.environment['LOCALAPPDATA']}/Pub/Cache/hosted/pub.dev/'
    'sherpa_onnx_windows-1.13.8/windows',
  );
  final available =
      Platform.isWindows &&
      File(paths.model).existsSync() &&
      File('$piper/ru_RU-denis-medium.onnx').existsSync() &&
      native.existsSync();

  late sherpa.OfflineTts tts;
  late ToneAsr asr;
  late SherpaVad vad;
  final heard = <String>[];

  setUpAll(() {
    if (!available) return;
    // В Windows 11 есть своя onnxruntime.dll (старше нужной) — берём из пакета.
    DynamicLibrary.open('${native.path}/onnxruntime.dll');
    sherpa.initBindings(native.path);
    tts = sherpa.OfflineTts(
      const sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          // Шум синтеза оставлен: без него речь монотонная и T-one слышит
          // её хуже живой. Поэтому каждый прогон — новое произношение,
          // а пороги ниже заданы с запасом под разброс.
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: '$piper/ru_RU-denis-medium.onnx',
            tokens: '$piper/tokens.txt',
            dataDir: '$piper/espeak-ng-data',
          ),
          numThreads: 2,
          debug: false,
        ),
      ),
    );
    asr = ToneAsr(paths);
    vad = SherpaVad(paths);
  });

  tearDownAll(() {
    if (!available) return;
    tts.free();
    asr.free();
    vad.free();
  });

  /// Речь на 16 кГц: Piper говорит на 22 050 Гц.
  Float32List say(String text, {double speed = 1.0}) {
    final audio = tts.generate(text: text, speed: speed);
    return _resample(audio.samples, audio.sampleRate, micSampleRate);
  }

  Float32List silence(int ms) => Float32List(micSampleRate * ms ~/ 1000);

  List<PipelineEvent> run(
    List<Float32List> parts,
    PipelineMode mode, {
    WakeVoice? voice,
  }) {
    final events = <PipelineEvent>[];
    final spy = _SpyAsr(asr)..heard.add('');
    final core = PipelineCore(
      vad: vad,
      asr: spy,
      emit: events.add,
      config: PipelineConfig(voice: voice),
    );
    core.setMode(1, mode, noSpeechMs: 4000);
    for (final part in parts) {
      // Кусками по 32 мс, как их отдаёт MicHub.
      for (var i = 0; i < part.length; i += 512) {
        final end = i + 512 > part.length ? part.length : i + 512;
        core.feed(Float32List.sublistView(part, i, end));
      }
    }
    heard
      ..clear()
      ..addAll(spy.heard.skip(1))
      ..add(asr.text);
    return events;
  }

  /// Одно и то же произношение с образцами и без — честное сравнение.
  int wakesOn(Float32List word, WakeVoice? voice) {
    final events = run(
      [silence(600), word, silence(1500)],
      PipelineMode.wake,
      voice: voice,
    );
    return events.whereType<AwaitingCommand>().isEmpty ? 0 : 1;
  }

  test(
    '«Макс, какое сегодня число» — обращение и команда одной фразой',
    () {
      final events = run([
        silence(800),
        say('Макс, какое сегодня число?'),
        silence(1500),
      ], PipelineMode.wake);

      final wake = events.whereType<WakeDetected>().single;
      expect(wake.heard, anyOf('макс', 'мак', 'маг', 'матс'));
      final done = events.whereType<FinalText>().single;
      expect(done.text, contains('число'));
      expect(done.text, isNot(contains('макс')));
      // ignore: avoid_print
      print(
        'wake ${wake.latencyMs} мс, команда «${done.text}», '
        'расшифровка ${done.decodeMs} мс',
      );
    },
    skip: !available,
  );

  test('«Макс» … пауза … команда: доля срабатываний на 12 синтезах', () {
    var woke = 0;
    var commands = 0;
    for (final speed in [0.85, 0.95, 1.0, 1.05, 1.15, 1.25]) {
      for (var take = 0; take < 2; take++) {
        final events = run([
          silence(600),
          say('Макс.', speed: speed),
          silence(1500),
          say('Позвони маме.'),
          silence(1500),
        ], PipelineMode.wake);
        if (events.whereType<AwaitingCommand>().isNotEmpty) {
          woke++;
        } else {
          // ignore: avoid_print
          print('промах одиночного $speed: ${_describe(events)} слышно $heard');
        }
        final done = events.whereType<FinalText>();
        if (done.isNotEmpty && done.single.text.contains('мам')) {
          commands++;
        } else if (events.whereType<AwaitingCommand>().isNotEmpty) {
          // ignore: avoid_print
          print('команда потеряна $speed: ${_describe(events)} слышно $heard');
        }
      }
    }
    // ignore: avoid_print
    print('одиночное «Макс»: обращение $woke/12, команда $commands/12');
    // Регрессионный порог, а не цель: на синтезе T-one слышит одиночное
    // «Макс.» как «нас», «на» или «н» — замеры дают 5–8 из 12.
    // Одиночное имя — слабое место модели (4–8 из 12, команда 2–7):
    // тест ловит поломку логики, а не качество распознавания.
    expect(woke, greaterThanOrEqualTo(2));
    expect(commands, greaterThanOrEqualTo(1));
  }, skip: !available);

  test('обучение голосу: одиночное «Макс» узнаётся по звучанию', () {
    // Три образца — через тот же режим записи, что на телефоне.
    final prints = <VoicePrint>[];
    for (final speed in [0.95, 1.0, 1.05]) {
      final events = run([
        silence(500),
        say('Макс.', speed: speed),
        silence(900),
      ], PipelineMode.enroll);
      final word = events.whereType<WordCaptured>().single;
      expect(word.print, isNotEmpty, reason: 'образец не записан');
      prints.add(word.print);
    }
    final voice = WakeVoice.enroll(prints);

    int wakes(String text, {required bool trained, required double speed}) {
      final events = run(
        [silence(600), say(text, speed: speed), silence(1500)],
        PipelineMode.wake,
        voice: trained ? voice : null,
      );
      return events.whereType<AwaitingCommand>().isEmpty ? 0 : 1;
    }

    var before = 0, after = 0;
    for (final speed in [0.85, 0.9, 1.0, 1.1, 1.2, 1.25]) {
      for (var take = 0; take < 2; take++) {
        final word = say('Макс.', speed: speed);
        before += wakesOn(word, null);
        after += wakesOn(word, voice);
      }
    }
    var falseWakes = 0;
    for (final text in [
      'Да.',
      'Так.',
      'Нет.',
      'Мама.',
      'Максим.',
      'Алло.',
      'Вакс.',
      'Нас.',
    ]) {
      for (final speed in [0.9, 1.1]) {
        falseWakes += wakes(text, trained: true, speed: speed);
      }
    }
    // ignore: avoid_print
    print(
      'одиночное «Макс»: без обучения $before/12, с обучением $after/12, '
      'ложных на 16 одиночных словах: $falseWakes, порог '
      '${voice.threshold.toStringAsFixed(2)}',
    );
    expect(after, greaterThanOrEqualTo(before));
    expect(after, greaterThanOrEqualTo(6));
    expect(falseWakes, lessThanOrEqualTo(3));
  }, skip: !available);

  test('«Макс, команда»: доля срабатываний на 12 синтезах', () {
    var ok = 0;
    for (final speed in [0.85, 0.95, 1.0, 1.05, 1.15, 1.25]) {
      for (final phrase in ['Макс, который час?', 'Макс, позвони маме.']) {
        final events = run([
          silence(600),
          say(phrase, speed: speed),
          silence(1500),
        ], PipelineMode.wake);
        final done = events.whereType<FinalText>();
        if (events.whereType<WakeDetected>().length == 1 &&
            done.length == 1 &&
            done.single.text.isNotEmpty) {
          ok++;
        } else {
          // ignore: avoid_print
          print('промах $phrase $speed: ${_describe(events)} слышно $heard');
        }
      }
    }
    // ignore: avoid_print
    print('«Макс, команда»: $ok/12');
    // Замеры на синтезе — 8–12 из 12.
    expect(ok, greaterThanOrEqualTo(7));
  }, skip: !available);

  test('речь без обращения не будит помощника (24 фразы)', () {
    var falseWakes = 0;
    for (final speed in [0.9, 1.1]) {
      for (final phrase in [
        'Позвони маме, пожалуйста, я очень прошу тебя.',
        'Сегодня хорошая погода.',
        'У нас дома тепло.',
        'Надень маску.',
        'Максимально быстро.',
        'Мама пришла с работы.',
        'Над городом облака.',
        'Максим пришёл домой.',
        'Позвони Максу вечером.',
        'Мак растёт в саду.',
        'Нас позвали в гости.',
        'Какое сегодня число?',
      ]) {
        final events = run([
          silence(500),
          say(phrase, speed: speed),
          silence(1200),
        ], PipelineMode.wake);
        if (events.whereType<WakeDetected>().isNotEmpty) {
          falseWakes++;
          // ignore: avoid_print
          print('ложное срабатывание: $phrase ($speed)');
        }
      }
    }
    expect(falseWakes, lessThanOrEqualTo(1));
  }, skip: !available);

  test('«Максим» — не обращение', () {
    final events = run([
      silence(600),
      say('Максим пришёл домой.'),
      silence(1200),
    ], PipelineMode.wake);
    expect(events.whereType<WakeDetected>(), isEmpty);
  }, skip: !available);

  test('перебивание: «Макс, стоп» во время ответа (6 синтезов)', () {
    var barged = 0;
    for (final speed in [0.9, 1.0, 1.1]) {
      for (var take = 0; take < 2; take++) {
        final events = run([
          silence(400),
          say('Макс, стоп.', speed: speed),
          silence(1200),
        ], PipelineMode.bargeIn);
        final done = events.whereType<FinalText>();
        if (events.whereType<BargeIn>().length == 1 &&
            done.length == 1 &&
            done.single.text.contains('стоп')) {
          barged++;
        }
      }
    }
    // ignore: avoid_print
    print('перебивание: $barged/6');
    expect(barged, greaterThanOrEqualTo(3));
  }, skip: !available);

  test(
    '«Макс, ставь будильник в семь утра» — от звука до будильника на 07:00',
    () async {
      final nlu = RuleBasedNlu();
      var set = 0;
      for (final speed in [0.9, 1.0, 1.1]) {
        for (var take = 0; take < 2; take++) {
          final events = run([
            silence(600),
            say('Макс, ставь будильник в семь утра.', speed: speed),
            silence(1500),
          ], PipelineMode.wake);
          final done = events.whereType<FinalText>();
          if (done.length != 1) continue;
          final parsed = await nlu.parse(done.single.text, DialogContext());
          // ignore: avoid_print
          print('будильник $speed: «${done.single.text}» → ${parsed.slots}');
          if (parsed.intent == Intent.alarm &&
              parsed.slots[Slot.value] == '07:00') {
            set++;
          }
        }
      }
      // ignore: avoid_print
      print('будильник на 07:00: $set/6');
      expect(set, greaterThanOrEqualTo(4));
    },
    skip: !available,
  );

  test('команда после кнопки: конец фразы по тишине VAD', () {
    final events = run([
      silence(500),
      say('Поставь будильник на семь утра.'),
      silence(1200),
    ], PipelineMode.command);
    final done = events.whereType<FinalText>().single;
    expect(done.text, contains('будильник'));
    expect(done.endpointMs, 700);
  }, skip: !available);

  test('тишина в режиме команды заканчивается пустым результатом', () {
    final events = run([silence(4500)], PipelineMode.command);
    expect(events.whereType<FinalText>().single.text, isEmpty);
    expect(events.whereType<SpeechStarted>(), isEmpty);
  }, skip: !available);
}

Float32List _resample(Float32List input, int from, int to) {
  if (from == to) return input;
  final length = (input.length * to / from).floor();
  final out = Float32List(length);
  for (var i = 0; i < length; i++) {
    final pos = i * from / to;
    final j = pos.floor();
    final frac = pos - j;
    final a = input[j];
    final b = j + 1 < input.length ? input[j + 1] : a;
    out[i] = a + (b - a) * frac;
  }
  return out;
}

String _describe(List<PipelineEvent> events) => events
    .map(
      (e) => switch (e) {
        PartialText(:final text) => '«$text»',
        WakeDetected(:final heard, :final command) => 'WAKE($heard|$command)',
        FinalText(:final text) => 'FINAL($text)',
        SpeechStarted() => '▶',
        SpeechEnded() => '■',
        AwaitingCommand() => 'AWAIT',
        _ => e.runtimeType.toString(),
      },
    )
    .join(' ');

/// Запоминает, что успела расшифровать модель перед каждым сбросом.
class _SpyAsr implements AsrEngine {
  _SpyAsr(this.inner);
  final AsrEngine inner;
  final heard = <String>[];

  @override
  void reset() {
    heard.add(inner.text);
    inner.reset();
  }

  @override
  void accept(Float32List samples) => inner.accept(samples);

  @override
  void flush() => inner.flush();

  @override
  String get text => inner.text;
}
