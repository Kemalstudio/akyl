import 'dart:typed_data';

import 'package:akyl/data/voice/pipeline_core.dart';
import 'dart:math' as math;

import 'package:akyl/domain/ports/voice_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Речь — громкий кусок; как и Silero, детектор держит «речь» ещё 250 мс.
class FakeVad implements VadEngine {
  int calls = 0;
  int _hangover = 0;
  bool _speech = false;

  @override
  void accept(Float32List window) {
    calls++;
    final loud = window.any((s) => s.abs() > 0.05);
    if (loud) {
      _speech = true;
      _hangover = PipelineCore.vadHangoverMs * 16 ~/ PipelineCore.window;
    } else if (_hangover > 0) {
      _hangover--;
    } else {
      _speech = false;
    }
  }

  @override
  bool get speech => _speech;

  @override
  void reset() {
    _speech = false;
    _hangover = 0;
  }
}

/// Текст появляется по мере накопления звука, как у потоковой модели.
class FakeAsr implements AsrEngine {
  FakeAsr(this.script);

  /// (сколько мс звука с последнего сброса, какой текст к этому моменту).
  List<(int, String)> script;
  int samples = 0;
  int totalSamples = 0;
  int resets = 0;
  bool flushed = false;

  @override
  void reset() {
    samples = 0;
    resets++;
    flushed = false;
  }

  @override
  void accept(Float32List s) {
    expect(flushed, isFalse, reason: 'звук после flush без сброса');
    samples += s.length;
    totalSamples += s.length;
  }

  @override
  void flush() => flushed = true;

  @override
  String get text {
    if (flushed && script.isNotEmpty) return script.last.$2;
    final ms = samples ~/ 16;
    var out = '';
    for (final (at, t) in script) {
      if (ms >= at) out = t;
    }
    return out;
  }
}

Float32List speech(int ms) => Float32List.fromList(List.filled(ms * 16, 0.2));
Float32List silence(int ms) => Float32List(ms * 16);

/// «Слово»: звук, меняющийся во времени, как речь, — скольжение тона от
/// [from] до [to] Гц. Ровный тон не годится: после вычитания среднего все
/// его кадры одинаковы.
Float32List tone(int ms, double from, [double? to]) {
  final n = ms * 16;
  final end = to ?? from * 3;
  var phase = 0.0;
  return Float32List.fromList([
    for (var i = 0; i < n; i++)
      0.3 *
          math.sin(
            phase += 2 * math.pi * (from + (end - from) * i / n) / 16000,
          ),
  ]);
}

void main() {
  late FakeVad vad;
  late FakeAsr asr;
  late List<PipelineEvent> events;
  late PipelineCore core;

  void build(List<(int, String)> script, {PipelineConfig? config}) {
    vad = FakeVad();
    asr = FakeAsr(script);
    events = [];
    core = PipelineCore(
      vad: vad,
      asr: asr,
      emit: events.add,
      config: config ?? const PipelineConfig(),
      micros: () => 0,
    );
  }

  void feed(List<Float32List> parts) {
    for (final p in parts) {
      for (var i = 0; i < p.length; i += 512) {
        core.feed(
          Float32List.sublistView(
            p,
            i,
            i + 512 > p.length ? p.length : i + 512,
          ),
        );
      }
    }
  }

  test('имя и команда одной фразой: обращение, затем команда без имени', () {
    // Предзапись 600 мс входит в звук распознавания.
    build([
      (900, 'макс'),
      (1200, 'макс какое'),
      (1800, 'макс какое сегодня число'),
    ]);
    core.setMode(7, PipelineMode.wake);
    feed([silence(700), speech(1400), silence(1200)]);

    final wake = events.whereType<WakeDetected>().single;
    expect(wake.epoch, 7);
    expect(wake.heard, 'макс');
    expect(wake.command, 'какое');
    expect(wake.latencyMs, greaterThan(0));
    final done = events.whereType<FinalText>().single;
    expect(done.text, 'какое сегодня число');
    expect(done.endpointMs, 700);
    expect(core.mode, PipelineMode.muted, reason: 'после финала — тишина');
  });

  test('одно имя и пауза: сигнал «слушаю» и команда следующей фразой', () {
    build([(700, 'макс')]);
    core.setMode(1, PipelineMode.wake);
    feed([silence(700), speech(400), silence(900)]);
    expect(events.whereType<WakeDetected>(), hasLength(1));
    expect(events.whereType<AwaitingCommand>(), hasLength(1));
    expect(core.mode, PipelineMode.command);

    asr.script = [(700, 'позвони'), (1200, 'позвони маме')];
    feed([speech(800), silence(900)]);
    expect(events.whereType<FinalText>().single.text, 'позвони маме');
  });

  test('без имени — ни обращения, ни команды', () {
    build([(700, 'позвони'), (1200, 'позвони маме')]);
    core.setMode(1, PipelineMode.wake);
    feed([silence(700), speech(900), silence(1500)]);
    expect(events.whereType<WakeDetected>(), isEmpty);
    expect(events.whereType<FinalText>(), isEmpty);
    expect(events.whereType<SpeechStarted>(), hasLength(1));
  });

  test('«Максим»: промежуточное «макс» не засчитывается', () {
    build([(700, 'макс'), (900, 'максим'), (1300, 'максим пришел')]);
    core.setMode(1, PipelineMode.wake);
    feed([silence(700), speech(900), silence(1500)]);
    expect(events.whereType<WakeDetected>(), isEmpty);
  });

  test('неточное «нась» принимается только перед командой', () {
    build([(800, 'нась'), (1100, 'нась позвони'), (1500, 'нась позвони маме')]);
    core.setMode(1, PipelineMode.wake);
    feed([silence(700), speech(1100), silence(1500)]);
    expect(events.whereType<FinalText>().single.text, 'позвони маме');

    build([(800, 'нас'), (1100, 'нас позвали'), (1500, 'нас позвали в гости')]);
    core.setMode(1, PipelineMode.wake);
    feed([silence(700), speech(1100), silence(1500)]);
    expect(events.whereType<WakeDetected>(), isEmpty);
  });

  test('долгая чужая речь: T-one выключается после окна поиска имени', () {
    build([(700, 'телевизор говорит'), (3000, 'телевизор говорит долго')]);
    core.setMode(1, PipelineMode.wake);
    feed([silence(700), speech(10000), silence(1000)]);
    // Окно 2.5 с + предзапись, а не все 10 секунд.
    expect(asr.totalSamples ~/ 16, lessThan(3800));
    expect(events.whereType<WakeDetected>(), isEmpty);
  });

  test('ожидание команды без речи заканчивается пустым результатом', () {
    build([]);
    core.setMode(3, PipelineMode.command, noSpeechMs: 2000);
    feed([silence(1900)]);
    expect(events.whereType<FinalText>(), isEmpty);
    feed([silence(200)]);
    final done = events.whereType<FinalText>().single;
    expect(done.text, isEmpty);
    expect(done.epoch, 3);
  });

  test('шорох без слов не закрывает ожидание команды', () {
    build([]);
    core.setMode(1, PipelineMode.command, noSpeechMs: 3000);
    feed([speech(300), silence(1000)]);
    expect(events.whereType<FinalText>(), isEmpty);
    asr.script = [(600, 'который час')];
    feed([speech(700), silence(900)]);
    expect(events.whereType<FinalText>().single.text, 'который час');
  });

  test('заглушённый режим не тратит VAD и распознавание', () {
    build([(100, 'макс позвони')]);
    core.setMode(1, PipelineMode.muted);
    feed([speech(2000), silence(1000)]);
    expect(vad.calls, 0);
    expect(asr.totalSamples, 0);
    expect(events, isEmpty);
  });

  test('смена режима забывает незаконченную фразу прежнего', () {
    // Звук распознавания = предзапись 600 мс + речь: имя ещё не дописано.
    build([(1300, 'макс'), (1600, 'макс позвони')]);
    core.setMode(1, PipelineMode.wake);
    feed([silence(700), speech(500)]);
    core.setMode(2, PipelineMode.muted);
    feed([speech(800), silence(1500)]);
    expect(events.whereType<WakeDetected>(), isEmpty);
    expect(events.whereType<FinalText>(), isEmpty);
  });

  test('перебивание именем во время ответа', () {
    build([(700, 'мак'), (900, 'мак стоп')]);
    core.setMode(5, PipelineMode.bargeIn);
    feed([silence(700), speech(600), silence(1500)]);
    final barge = events.whereType<BargeIn>().single;
    expect(barge.epoch, 5);
    expect(events.whereType<WakeDetected>(), isEmpty);
    expect(events.whereType<FinalText>().single.text, 'стоп');
  });

  test('перебивание речью, когда есть подавление эха', () {
    build([
      (1500, 'подожди'),
    ], config: const PipelineConfig(bargeInNeedsWake: false));
    core.setMode(1, PipelineMode.bargeIn);
    feed([silence(700), speech(500)]);
    expect(events.whereType<BargeIn>(), hasLength(1));
    feed([speech(800), silence(1000)]);
    expect(events.whereType<FinalText>().single.text, 'подожди');
  });

  test('без подавления эха голос ответа не перебивает сам себя', () {
    build([(700, 'сегодня двадцать девятое сентября')]);
    core.setMode(1, PipelineMode.bargeIn);
    feed([silence(700), speech(2500), silence(1500)]);
    expect(events.whereType<BargeIn>(), isEmpty);
  });

  test('слишком длинная команда обрезается пределом', () {
    build([
      (500, 'напиши'),
    ], config: const PipelineConfig(maxUtteranceMs: 3000));
    core.setMode(1, PipelineMode.command);
    feed([speech(4000)]);
    expect(events.whereType<FinalText>().single.text, 'напиши');
  });

  test('громкость шлётся, только когда её кто-то показывает', () {
    build([]);
    core.setMode(1, PipelineMode.wake);
    feed([speech(500)]);
    expect(events.whereType<MicLevel>(), isEmpty);
    core.levelsEnabled = true;
    feed([speech(500)]);
    final levels = events.whereType<MicLevel>().toList();
    expect(levels.length, inInclusiveRange(4, 6));
    expect(levels.last.level, greaterThan(0.5));
  });

  test('16-битный PCM переводится в отсчёты', () {
    build([]);
    core.setMode(1, PipelineMode.wake);
    final bytes = ByteData(1024);
    for (var i = 0; i < 512; i++) {
      bytes.setInt16(i * 2, 16000, Endian.little);
    }
    core.feedPcm16(bytes.buffer.asUint8List());
    expect(vad.calls, 1);
    expect(vad.speech, isTrue);
  });

  group('Обучение голосу', () {
    test('запись образца: одно слово — отпечаток', () {
      build([]);
      core.setMode(4, PipelineMode.enroll, noSpeechMs: 3000);
      feed([silence(600), tone(500, 300), silence(600)]);
      final word = events.whereType<WordCaptured>().single;
      expect(word.epoch, 4);
      expect(word.print, isNotEmpty);
      expect(word.durationMs, inInclusiveRange(400, 700));
      expect(core.mode, PipelineMode.muted);
    });

    test('слишком длинная фраза — пустой отпечаток с длительностью', () {
      build([]);
      core.setMode(1, PipelineMode.enroll, noSpeechMs: 3000);
      feed([silence(300), tone(3000, 300), silence(600)]);
      final word = events.whereType<WordCaptured>().single;
      expect(word.print, isEmpty);
      expect(word.durationMs, greaterThan(1500));
    });

    test('тишина при записи — пустой отпечаток без длительности', () {
      build([]);
      core.setMode(1, PipelineMode.enroll, noSpeechMs: 2000);
      feed([silence(2100)]);
      final word = events.whereType<WordCaptured>().single;
      expect(word.print, isEmpty);
      expect(word.durationMs, 0);
    });

    WakeVoice trained() {
      build([]);
      final prints = <VoicePrint>[];
      for (final hz in [300.0, 305.0, 295.0]) {
        core.setMode(1, PipelineMode.enroll, noSpeechMs: 3000);
        feed([silence(600), tone(500, hz), silence(600)]);
        prints.add(events.whereType<WordCaptured>().last.print);
      }
      return WakeVoice.enroll(prints);
    }

    test('нерасшифрованное короткое слово узнаётся по звучанию', () {
      final voice = trained();
      build([], config: PipelineConfig(voice: voice));
      core.setMode(2, PipelineMode.wake);
      feed([silence(700), tone(500, 300), silence(1200)]);
      expect(events.whereType<WakeDetected>().single.heard, 'голос');
      expect(events.whereType<AwaitingCommand>(), hasLength(1));
      expect(core.mode, PipelineMode.command);
    });

    test('другое звучание — не обращение', () {
      final voice = trained();
      build([], config: PipelineConfig(voice: voice));
      core.setMode(2, PipelineMode.wake);
      feed([silence(700), tone(500, 900, 300), silence(1200)]);
      expect(events.whereType<WakeDetected>(), isEmpty);
    });

    test('T-one ясно услышала другое слово — сравнение не спасает', () {
      final voice = trained();
      build([(300, 'да')], config: PipelineConfig(voice: voice));
      core.setMode(2, PipelineMode.wake);
      feed([silence(700), tone(500, 300), silence(1200)]);
      expect(events.whereType<WakeDetected>(), isEmpty);
    });

    test('без обучения короткое слово без текста не будит', () {
      build([]);
      core.setMode(2, PipelineMode.wake);
      feed([silence(700), tone(500, 300), silence(1200)]);
      expect(events.whereType<WakeDetected>(), isEmpty);
    });

    test('образцы переживают сохранение', () {
      final voice = trained();
      final copy = WakeVoice.fromJson(voice.toJson())!;
      expect(copy.prints.length, voice.prints.length);
      expect(copy.threshold, voice.threshold);
      expect(copy.distance(voice.prints.first), closeTo(0, 1e-3));
    });
  });
}
