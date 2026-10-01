import 'dart:typed_data';

import 'package:akyl/domain/dialog/dialog_state.dart';
import 'package:akyl/domain/ports/voice_pipeline.dart';
import 'package:akyl/domain/ports/voice_platform.dart';
import 'package:akyl/presentation/assistant_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

/// Ждёт, пока условие станет верным: сверка состояния идёт цепочкой Future.
Future<void> until(bool Function() ok, {String? reason}) async {
  for (var i = 0; i < 200 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ok(), isTrue, reason: reason);
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late FakePipeline pipeline;
  late FakeVoicePlatform platform;
  late FakeTts tts;

  setUp(() {
    pipeline = FakePipeline();
    platform = FakeVoicePlatform();
    tts = FakeTts();
  });

  Future<AssistantController> start({
    VoiceSettings settings = const VoiceSettings(wakeEnabled: true),
    FakeStt? stt,
    FakePipeline? withPipeline,
  }) async {
    final c = await buildTestController(
      pipeline: withPipeline ?? pipeline,
      platform: platform,
      tts: tts,
      stt: stt,
      settings: settings,
    );
    addTearDown(c.dispose);
    await settle();
    return c;
  }

  group('Запуск и жизненный цикл', () {
    test('запуск с обращением: микрофон открывается ровно один раз', () async {
      final c = await start();
      expect(pipeline.opens, 1);
      expect(pipeline.mode, PipelineMode.wake);
      expect(c.voice.phase, VoicePhase.listeningForWake);
      expect(c.wakeListening, isTrue);
    });

    test('обращение выключено: микрофон не трогается', () async {
      final c = await start(settings: const VoiceSettings());
      expect(pipeline.opens, 0);
      expect(c.voice.phase, VoicePhase.disabled);
      expect(c.voice.micOpen, isFalse);
    });

    test('уход в фон без фонового режима закрывает запись, '
        'возврат не создаёт второго слушателя', () async {
      final c = await start();
      await c.voice.setUiVisible(false);
      expect(pipeline.micOpen, isFalse);
      expect(c.voice.phase, VoicePhase.paused);
      expect(c.voice.pauseReason, VoicePauseReason.background);

      await c.voice.setUiVisible(true);
      await c.voice.setUiVisible(true);
      await settle();
      expect(pipeline.opens, 2);
      expect(pipeline.micOpen, isTrue);
      expect(c.voice.phase, VoicePhase.listeningForWake);
    });

    test(
      'фоновый режим: служба запускается, в фоне запись продолжается',
      () async {
        final c = await start(
          settings: const VoiceSettings(wakeEnabled: true, background: true),
        );
        expect(platform.serviceStarts, 1);
        expect(platform.backgroundFlag, isTrue);
        await c.voice.setUiVisible(false);
        expect(pipeline.micOpen, isTrue);
        expect(pipeline.opens, 1);
        expect(c.voice.phase, VoicePhase.listeningForWake);
        expect(platform.notifications.last, contains('Макс'));
      },
    );

    test('выключение обращения освобождает запись и службу', () async {
      final c = await start(
        settings: const VoiceSettings(wakeEnabled: true, background: true),
      );
      await c.setWakeWordEnabled(false);
      expect(pipeline.micOpen, isFalse);
      expect(platform.serviceStops, 1);
      expect(platform.backgroundFlag, isFalse);
      expect(c.voice.phase, VoicePhase.disabled);
      final opens = pipeline.opens;
      await settle();
      expect(pipeline.opens, opens, reason: 'никаких самовключений');
    });

    test('«Выключить» в уведомлении выключает фон и в настройках', () async {
      final c = await start(
        settings: const VoiceSettings(wakeEnabled: true, background: true),
      );
      await c.voice.setUiVisible(false);
      platform.serviceRunning = false;
      platform.emit(const ServiceChanged(running: false, userStopped: true));
      await until(() => !c.voice.settings.background);
      await until(() => !pipeline.micOpen);
    });

    test('без разрешения на микрофон голос не включается', () async {
      final c = await buildTestController(
        pipeline: pipeline,
        platform: platform,
        phone: FakePhone(permissionsGranted: false),
        settings: const VoiceSettings(wakeEnabled: true),
      );
      addTearDown(c.dispose);
      await settle();
      expect(pipeline.opens, 0);
      expect(c.voice.phase, VoicePhase.disabled);
      expect(c.voiceAvailable, isFalse);
    });

    test('модель не загрузилась: обращение недоступно, кнопка — через '
        'системное распознавание', () async {
      final stt = FakeStt(scripted: 'который час');
      final c = await start(
        stt: stt,
        withPipeline: FakePipeline(failInit: true),
      );
      expect(c.voice.wakeAvailable, isFalse);
      expect(c.voice.phase, VoicePhase.error);
      await c.listen();
      expect(stt.startCount, 1);
      expect(c.history.last.text, contains('16:45'));
    });
  });

  group('Обращение и команда', () {
    test('«Макс, какое сегодня число» — ответ голосом и продолжение '
        'разговора без повторного имени', () async {
      final c = await start();
      pipeline.wake('макс', command: 'какое');
      await settle();
      expect(c.voice.phase, VoicePhase.listeningForCommand);
      expect(c.state, DialogState.listening);

      pipeline.finalText('какое сегодня число');
      await until(() => tts.spoken.isNotEmpty);
      expect(c.history.first.text, 'какое сегодня число');
      expect(tts.spoken.single, contains('28 сентября'));

      // Разговор продолжается: слушаю без «Макс».
      await until(() => c.voice.phase == VoicePhase.listeningForCommand);
      expect(pipeline.mode, PipelineMode.command);

      pipeline.finalText('который час');
      await until(() => tts.spoken.length == 2);
      expect(tts.spoken.last, contains('16:45'));

      // Тишина — разговор окончен, снова жду имя.
      await until(() => c.voice.phase == VoicePhase.listeningForCommand);
      pipeline.finalText('');
      await until(() => c.voice.phase == VoicePhase.listeningForWake);
      expect(pipeline.mode, PipelineMode.wake);
      expect(pipeline.opens, 1, reason: 'микрофон не переоткрывался');
    });

    test('без продолжения разговора после ответа снова жду имя', () async {
      final c = await start(
        settings: const VoiceSettings(
          wakeEnabled: true,
          conversationSeconds: 0,
        ),
      );
      pipeline.wake('макс');
      pipeline.finalText('который час');
      await until(() => tts.spoken.isNotEmpty);
      await until(() => c.voice.phase == VoicePhase.listeningForWake);
      expect(pipeline.mode, PipelineMode.wake);
    });

    test('одно имя и пауза — мягкий сигнал «слушаю»', () async {
      await start();
      pipeline.wake('макс');
      pipeline.awaiting();
      await until(() => platform.cues.isNotEmpty);
      expect(platform.cues.single, VoiceCue.listening);
    });

    test('без звука — сигнала нет', () async {
      await start(
        settings: const VoiceSettings(
          wakeEnabled: true,
          cue: ActivationCue.silent,
        ),
      );
      pipeline.wake('макс');
      pipeline.awaiting();
      await settle();
      expect(platform.cues, isEmpty);
    });

    test('«стоп» в разговоре — тихо заканчивает, без ответа', () async {
      final c = await start();
      pipeline.wake('макс');
      pipeline.finalText('стоп');
      await until(() => c.voice.phase == VoicePhase.listeningForWake);
      expect(c.history, isEmpty);
      expect(tts.spoken, isEmpty);
    });

    test('устаревший результат прошлого режима не выполняется', () async {
      final c = await start();
      final old = pipeline.epoch;
      pipeline.wake('макс');
      await settle();
      await c.stopListening(); // новый режим
      pipeline.finalText('позвони маме', atEpoch: old);
      await settle();
      expect(c.history, isEmpty);
    });
  });

  group('Голос ответа и микрофон', () {
    test('пока звучит ответ, конвейер не слышит динамик', () async {
      tts.hold = true;
      final c = await start(
        settings: const VoiceSettings(wakeEnabled: true, interrupt: false),
      );
      pipeline.wake('макс');
      pipeline.finalText('который час');
      await until(() => tts.isSpeaking);
      expect(c.voice.phase, VoicePhase.speaking);
      expect(pipeline.mode, PipelineMode.muted);
      tts.finishSpeaking();
      await until(() => pipeline.mode == PipelineMode.command);
    });

    test('ответ можно перебить обращением', () async {
      tts.hold = true;
      final c = await start();
      pipeline.wake('макс');
      pipeline.finalText('который час');
      await until(() => tts.isSpeaking);
      expect(pipeline.mode, PipelineMode.bargeIn);

      pipeline.bargeIn(command: 'позвони');
      await until(() => c.voice.phase == VoicePhase.listeningForCommand);
      expect(tts.stopCount, greaterThan(0));
      expect(tts.isSpeaking, isFalse);
      expect(c.partialText, 'позвони');
    });

    test('ответ на набранную команду тоже заглушает микрофон', () async {
      tts.hold = true;
      final c = await start(
        settings: const VoiceSettings(wakeEnabled: true, interrupt: false),
      );
      final done = c.submit('который час');
      await until(() => tts.isSpeaking);
      expect(pipeline.mode, PipelineMode.muted);
      tts.finishSpeaking();
      await done;
      await until(() => pipeline.mode == PipelineMode.wake);
      expect(c.voice.phase, VoicePhase.listeningForWake);
    });

    test('ритм слов ответа двигает анимацию', () async {
      tts.hold = true;
      final c = await start();
      final done = c.submit('который час');
      await until(() => tts.isSpeaking);
      tts.pulse();
      await settle();
      expect(c.soundLevel.value, greaterThan(0.5));
      expect(c.voice.diagnostics.ttsFirstAudio, isNotNull);
      tts.finishSpeaking();
      await done;
    });
  });

  group('Телефон вокруг', () {
    test(
      'звонок забирает микрофон, после звонка ожидание возвращается',
      () async {
        final c = await start();
        platform.emit(const CallChanged(true));
        await until(() => !pipeline.micOpen);
        expect(c.voice.phase, VoicePhase.paused);
        expect(c.voice.pauseReason, VoicePauseReason.call);

        platform.emit(const CallChanged(false));
        await until(() => pipeline.micOpen);
        expect(c.voice.phase, VoicePhase.listeningForWake);
      },
    );

    test('микрофон занят другим приложением — пауза с причиной, без '
        'переоткрытий', () async {
      final c = await start();
      platform.emit(const MicSilenced(true));
      await until(() => c.voice.pauseReason == VoicePauseReason.micBusy);
      expect(pipeline.micOpen, isTrue);
      platform.emit(const MicSilenced(false));
      await until(() => c.voice.phase == VoicePhase.listeningForWake);
      expect(pipeline.opens, 1);
    });

    test('сбой микрофона: повтор по нарастающей задержке', () async {
      final c = await start();
      pipeline.fail('Микрофон перестал передавать звук');
      await until(() => c.voice.phase == VoicePhase.recovering);
      expect(c.voice.error, contains('Микрофон'));
      await until(() => pipeline.micOpen);
      await until(() => c.voice.phase == VoicePhase.listeningForWake);
      expect(pipeline.opens, 2);
    });

    test('отозванное разрешение — ошибка без бесконечных повторов', () async {
      final c = await start();
      pipeline.fail('Нет разрешения на микрофон', fatal: true);
      await until(() => c.voice.phase == VoicePhase.error);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(pipeline.opens, 1);
      expect(c.warning, contains('разрешения'));
    });

    test('заблокированный экран: личное не читается вслух', () async {
      final c = await start();
      platform.emit(const LockChanged(true));
      await settle();
      await c.submit('напиши маме что я опаздываю');
      expect(c.history.last.text, contains('Разблокируйте'));

      platform.emit(const LockChanged(false));
      await settle();
      await c.submit('который час');
      expect(c.history.last.text, contains('16:45'));
    });

    test('жест помощника Android — сразу слушаю команду', () async {
      final c = await start();
      platform.command = '';
      platform.emit(const AssistInvoked());
      await until(() => c.voice.phase == VoicePhase.listeningForCommand);
      expect(pipeline.mode, PipelineMode.command);
    });
  });

  group('Кнопка микрофона', () {
    test(
      'при выключенном обращении открывает запись на одну команду',
      () async {
        final c = await start(settings: const VoiceSettings());
        final session = c.listen();
        await until(() => pipeline.micOpen);
        expect(pipeline.mode, PipelineMode.command);
        pipeline.finalText('который час');
        await session;
        await until(() => !pipeline.micOpen);
        expect(c.history.last.text, contains('16:45'));
        expect(c.voice.phase, VoicePhase.disabled);
      },
    );

    test('остановка записи ничего не выполняет', () async {
      final c = await start();
      final session = c.listen();
      await until(() => c.listening);
      pipeline.partial('позвони маме');
      await c.stopListening();
      await session;
      expect(c.history, isEmpty);
      expect(c.voice.phase, VoicePhase.listeningForWake);
    });

    test('освобождение контроллера закрывает микрофон', () async {
      final c = await buildTestController(
        pipeline: pipeline,
        platform: platform,
        settings: const VoiceSettings(wakeEnabled: true),
      );
      await settle();
      expect(pipeline.micOpen, isTrue);
      c.dispose();
      await until(() => !pipeline.micOpen);
    });
  });

  group('Обучение голосу', () {
    VoicePrint print(double v) => [
      for (var i = 0; i < 20; i++) Float32List.fromList(List.filled(12, v)),
    ];

    test('три записи — образцы сохраняются и уходят в конвейер', () async {
      final c = await start();
      expect(c.voice.voiceTrained, isFalse);
      final prints = <VoicePrint>[];
      for (var i = 0; i < 3; i++) {
        final sample = c.voice.captureVoiceSample();
        await until(() => pipeline.mode == PipelineMode.enroll);
        expect(c.voice.phase, VoicePhase.listeningForCommand);
        pipeline.captured(print(i * 0.1));
        final word = await sample;
        prints.add(word!.print);
        await until(() => c.voice.phase == VoicePhase.listeningForWake);
      }
      await c.voice.saveVoice(prints);
      expect(c.voice.voiceTrained, isTrue);
      expect(pipeline.config?.voice, isNotNull);
      expect(pipeline.config!.voice!.prints, hasLength(3));

      await c.voice.clearVoice();
      expect(c.voice.voiceTrained, isFalse);
      expect(pipeline.config?.voice, isNull);
    });

    test(
      'не расслышал — пустой отпечаток, ожидание «Макс» возвращается',
      () async {
        final c = await start();
        final sample = c.voice.captureVoiceSample();
        await until(() => pipeline.mode == PipelineMode.enroll);
        pipeline.captured(const [], durationMs: 0);
        final word = await sample;
        expect(word!.print, isEmpty);
        await until(() => c.voice.phase == VoicePhase.listeningForWake);
      },
    );

    test('запись работает и при выключенном обращении, потом микрофон '
        'закрывается', () async {
      final c = await start(settings: const VoiceSettings());
      final sample = c.voice.captureVoiceSample();
      await until(
        () => pipeline.micOpen && pipeline.mode == PipelineMode.enroll,
      );
      pipeline.captured(print(0.2));
      await sample;
      await until(() => !pipeline.micOpen);
    });
  });
}
