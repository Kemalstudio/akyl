import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/voice/voice_log.dart';
import '../data/voice/voice_settings_store.dart';
import '../domain/ports/speech_to_text.dart';
import '../domain/ports/text_to_speech.dart';
import '../domain/ports/voice_pipeline.dart';
import '../domain/ports/voice_platform.dart';
import '../domain/voice/voice_phase.dart';
import '../domain/voice/voice_settings.dart';

export '../domain/voice/voice_phase.dart';
export '../domain/voice/voice_settings.dart';

/// Ответ диалога на голосовую команду.
class VoiceReply {
  const VoiceReply(
    this.text, {
    this.expectsReply = false,
    this.alreadySpoken = false,
  });

  final String text;

  /// Помощник задал вопрос («отправить?») — ответ слушаем сразу.
  final bool expectsReply;

  /// Ответ уже произнесён навыком (например, «Звоню маме» до звонка).
  final bool alreadySpoken;
}

typedef VoiceCommandHandler = Future<VoiceReply> Function(String text);

/// Замеры для панели отладки. Время — в миллисекундах.
class VoiceDiagnostics {
  String? lastWake;
  String? lastCommand;
  DateTime? lastWakeAt;
  int wakeCount = 0;
  int? wakeLatency;
  int? sttEndpoint;
  int? sttDecode;
  int? processing;
  int? ttsFirstAudio;
  double? rtf;
  int? vadMicros;
  bool vadSpeech = false;
  String engine = '—';
}

/// Откуда начался текущий разговор.
enum _Session { none, wake, manual, enroll }

/// Единственный владелец микрофона и голосового состояния.
///
/// Никаких «слушателей №2»: экран, фоновая служба, уведомление и панель
/// отладки читают одно [phase]. Микрофон открывает только [_reconcile] —
/// он сравнивает желаемое (настройки, экран, звонок, сессия) с фактическим
/// и делает минимальный шаг. Вызовы сверки идут строго по очереди, поэтому
/// быстрые «вкл-выкл», возврат из фона и события телефона не могут открыть
/// запись дважды.
class VoiceManager extends ChangeNotifier {
  VoiceManager({
    VoicePipeline? pipeline,
    required SpeechToText stt,
    required TextToSpeech tts,
    VoicePlatform platform = const NoopVoicePlatform(),
    VoiceSettingsStore? store,
    VoiceLog? log,
    bool uiVisible = true,
    this.guardAfterSpeech = const Duration(milliseconds: 250),
  }) : _pipeline = pipeline,
       _stt = stt,
       _tts = tts,
       _platform = platform,
       _store = store ?? MemoryVoiceSettingsStore(),
       log = log ?? VoiceLog.instance,
       _uiVisible = uiVisible {
    _settings = _store.load();
    _voice = _store.loadVoice();
    _tts.enabled = _settings.autoSpeak;
  }

  WakeVoice? _voice;

  /// Человек записал своё «Макс»: одиночное имя узнаётся и по звучанию.
  bool get voiceTrained => _voice != null;

  final VoicePipeline? _pipeline;
  final SpeechToText _stt;
  final TextToSpeech _tts;
  final VoicePlatform _platform;
  final VoiceSettingsStore _store;
  final VoiceLog log;

  /// После ответа динамик ещё звучит в комнате: столько не слушаем.
  final Duration guardAfterSpeech;

  /// Обработчик команды — диалог. Задаёт AssistantController.
  VoiceCommandHandler? onCommand;

  /// Диалог ждёт ответа на вопрос: тогда «стоп»/«отмена» — это ответ,
  /// а не просьба замолчать.
  bool Function()? dialogAwaiting;

  late VoiceSettings _settings;
  VoiceSettings get settings => _settings;

  final diagnostics = VoiceDiagnostics();

  // --- Состояние -------------------------------------------------------------

  VoicePhase _phase = VoicePhase.disabled;
  VoicePhase get phase => _phase;

  VoicePauseReason _pause = VoicePauseReason.none;
  VoicePauseReason get pauseReason => _pause;

  String? _error;

  /// Понятная человеку причина ошибки или паузы.
  String? get error => _error;

  String _partial = '';
  String get partialText => _partial;

  /// Громкость голоса 0..1 — и человека, и ответа. Отдельно от
  /// notifyListeners: меняется десятки раз в секунду.
  final ValueNotifier<double> level = ValueNotifier(0);

  bool _permission = false;
  bool _uiVisible;
  bool _locked = false;
  bool _callActive = false;
  bool _silenced = false;
  bool _externalRecognition = false;
  bool _serviceRunning = false;
  bool _backgroundFlag = false;
  bool _pipelineReady = false;
  bool _sttReady = false;
  bool _disposed = false;
  bool _initialized = false;

  _Session _session = _Session.none;
  Completer<void>? _sessionDone;
  int _epoch = -1;
  PipelineMode? _mode;
  int _speakToken = 0;
  bool _speaking = false;
  DateTime? _speakStarted;

  int _failures = 0;
  Timer? _retry;
  Timer? _stable;
  String? _notificationText;

  StreamSubscription<PipelineEvent>? _pipelineSub;
  StreamSubscription<PlatformVoiceEvent>? _platformSub;
  StreamSubscription<double>? _pulseSub;
  StreamSubscription<String>? _sttPartialSub;
  StreamSubscription<double>? _sttLevelSub;

  /// Своя модель поднялась: обращение «Макс» доступно.
  bool get wakeAvailable => _pipelineReady;

  /// Голосом вообще можно пользоваться (своя модель или системная).
  bool get voiceAvailable => _pipelineReady || _sttReady;

  bool get micOpen => _pipeline?.micOpen ?? false;
  bool get listening => _phase == VoicePhase.listeningForCommand;
  bool get wakeListening => _phase == VoicePhase.listeningForWake;
  bool get speaking => _phase == VoicePhase.speaking;
  bool get locked => _locked;
  bool get serviceRunning => _serviceRunning;
  bool get callActive => _callActive;
  bool get uiVisible => _uiVisible;

  /// Обращение ищется только на телефоне — звук никуда не уходит.
  bool get wakeIsLocal => _pipelineReady;

  // --- Запуск ------------------------------------------------------------------

  /// [permission] — есть ли разрешение на микрофон.
  Future<void> init({required bool permission}) async {
    _permission = permission;
    if (!_initialized) {
      _initialized = true;
      try {
        await _tts.init();
      } catch (e) {
        log.add(VoiceTag.tts, 'голос ответа недоступен: $e');
      }
      _platformSub = _platform.events.listen(_onPlatform);
      _pulseSub = _tts.speechPulses.listen(_onPulse);
      try {
        final status = await _platform.status();
        _serviceRunning = status.serviceRunning;
        _locked = status.locked;
        _callActive = status.callActive;
        _silenced = status.micSilenced;
      } catch (e) {
        log.add(VoiceTag.background, 'статус системы недоступен: $e');
      }
      if (_settings.voiceName != null) {
        unawaited(_tts.setVoice(_settings.voiceName).catchError((_) {}));
      }
    }
    if (_permission) await _loadEngines();
    await _reconcile();
    await _takeAssistCommand();
  }

  /// Разрешение выдано позже — поднимаем голос.
  Future<void> permissionGranted() => init(permission: true);

  Future<void> _loadEngines() async {
    final pipeline = _pipeline;
    if (pipeline != null && !_pipelineReady) {
      _setPhase(VoicePhase.starting);
      try {
        await pipeline.init();
        if (_disposed) return;
        _pipelineReady = true;
        diagnostics.engine = 'T-one + Silero VAD (на телефоне)';
        _pipelineSub ??= pipeline.events.listen(_onPipeline);
        pipeline.configure(_pipelineConfig());
        pipeline.setLevelsEnabled(_uiVisible);
      } catch (e) {
        log.add(VoiceTag.stt, 'своя модель недоступна: $e');
      }
    }
    if (!_pipelineReady && !_sttReady) {
      try {
        await _stt.init();
        _sttReady = true;
        diagnostics.engine = 'Распознавание Android';
      } catch (e) {
        log.add(VoiceTag.stt, 'системное распознавание недоступно: $e');
        final reason = e is SpeechError
            ? e.message
            : 'нет движка распознавания';
        _error = 'Голос недоступен: $reason. Команду можно набрать текстом';
      }
    }
  }

  PipelineConfig _pipelineConfig() => PipelineConfig.from(
    _settings,
    echoCancelled: _settings.echoCancellation == AudioProcessing.on,
    voice: _voice,
  );

  MicConfig get _micConfig => MicConfig(
    echoCancellation: _settings.echoCancellation == AudioProcessing.on,
    noiseSuppression: _settings.noiseSuppression == AudioProcessing.on,
  );

  // --- Настройки -------------------------------------------------------------

  Future<void> updateSettings(VoiceSettings next) async {
    if (next == _settings) return;
    final previous = _settings;
    _settings = next;
    _tts.enabled = next.autoSpeak;
    if (next.voiceName != previous.voiceName) {
      unawaited(_tts.setVoice(next.voiceName).catchError((_) {}));
    }
    _pipeline?.configure(_pipelineConfig());
    if (next.wakeEnabled != previous.wakeEnabled ||
        next.background != previous.background) {
      _failures = 0;
      _error = null;
      log.add(
        VoiceTag.voice,
        'обращение ${next.wakeEnabled ? 'включено' : 'выключено'}, '
        'фон ${next.background ? 'включён' : 'выключен'}',
      );
    }
    notifyListeners();
    await _store.save(next);
    await _reconcile();
  }

  // --- Жизненный цикл экрана -------------------------------------------------

  /// Экран приложения виден (resumed/inactive) или скрыт.
  Future<void> setUiVisible(bool visible) async {
    if (_uiVisible == visible) return;
    _uiVisible = visible;
    _pipeline?.setLevelsEnabled(visible);
    log.add(VoiceTag.background, visible ? 'экран открыт' : 'экран скрыт');
    // Без фоновой службы Android заглушит запись, как только экран уйдёт:
    // команда, начатая кнопкой, всё равно не дослушается.
    if (!visible && _session == _Session.manual && !_backgroundActive) {
      await _cancelSession();
    }
    if (visible) {
      _failures = 0;
      if (_phase == VoicePhase.error) _error = null;
    }
    await _reconcile();
  }

  bool get _backgroundActive => _settings.background && _serviceRunning;

  // --- Сверка ----------------------------------------------------------------

  Future<void> _ops = Future.value();

  Future<void> _reconcile() {
    final done = Completer<void>();
    _ops = _ops.then((_) async {
      try {
        await _reconcileNow();
      } catch (e, s) {
        log.add(VoiceTag.voice, 'сбой сверки: $e');
        if (kDebugMode) debugPrintStack(stackTrace: s);
      } finally {
        done.complete();
      }
    });
    return done.future;
  }

  bool get _wantService =>
      _settings.wakeEnabled &&
      _settings.background &&
      _pipelineReady &&
      _permission &&
      !_disposed;

  bool get _wantMic {
    if (!_pipelineReady || !_permission || _disposed) return false;
    if (_callActive || _externalRecognition) return false;
    if (_session != _Session.none) return true;
    if (!_settings.wakeEnabled) return false;
    return _uiVisible || _backgroundActive;
  }

  Future<void> _reconcileNow() async {
    if (_disposed) return;

    // Служба: флаг перезапуска для Android и сама foreground-служба.
    final wantService = _wantService;
    if (wantService != _backgroundFlag) {
      _backgroundFlag = wantService;
      await _safe(() => _platform.setBackgroundEnabled(wantService));
    }
    if (wantService && !_serviceRunning) {
      // Из фона Android запустит microphone-службу только выбранному
      // помощнику; с экрана — всегда. Отказ — не ошибка голоса вообще.
      final started = await _safe(_platform.startService) ?? false;
      _serviceRunning = started;
      log.add(
        VoiceTag.background,
        started ? 'служба микрофона запущена' : 'Android не запустил службу',
      );
    } else if (!wantService && _serviceRunning) {
      await _safe(_platform.stopService);
      _serviceRunning = false;
      log.add(VoiceTag.background, 'служба микрофона остановлена');
    }

    // Микрофон.
    final pipeline = _pipeline;
    final wantMic = _wantMic;
    if (pipeline != null && _pipelineReady) {
      if (wantMic && _phase != VoicePhase.recovering) {
        try {
          final wasOpen = pipeline.micOpen;
          await pipeline.open(_micConfig);
          if (!wasOpen) {
            _mode = null; // после открытия режим задаётся заново
            _armStableTimer();
            // Микрофон открылся — прежняя ошибка больше не актуальна.
            _error = null;
            if (_phase == VoicePhase.error) _phase = VoicePhase.starting;
          }
        } catch (e) {
          _onFailure('$e', fatal: false);
          return;
        }
      } else if (!wantMic && pipeline.micOpen) {
        await pipeline.close();
        _mode = null;
      }
    }

    // Состояние вне разговора.
    if (_session == _Session.none && _phase != VoicePhase.recovering) {
      _applyIdlePhase(wantMic);
    }
    await _syncNotification();
  }

  void _applyIdlePhase(bool wantMic) {
    final micOpen = _pipeline?.micOpen ?? false;
    VoicePhase phase;
    var pause = VoicePauseReason.none;
    if (!_permission) {
      phase = VoicePhase.disabled;
    } else if (!_pipelineReady) {
      phase = _settings.wakeEnabled && _pipeline != null
          ? VoicePhase.error
          : VoicePhase.disabled;
      if (phase == VoicePhase.error) {
        _error ??= 'Модель распознавания не загрузилась';
      }
    } else if (!_settings.wakeEnabled) {
      phase = VoicePhase.disabled;
    } else if (_callActive) {
      phase = VoicePhase.paused;
      pause = VoicePauseReason.call;
    } else if (_externalRecognition) {
      phase = VoicePhase.paused;
      pause = VoicePauseReason.externalRecognition;
    } else if (!wantMic) {
      phase = VoicePhase.paused;
      pause = VoicePauseReason.background;
    } else if (!micOpen) {
      // Хотели открыть, но не вышло: причину уже записал _onFailure.
      phase = VoicePhase.error;
    } else if (_silenced) {
      phase = VoicePhase.paused;
      pause = VoicePauseReason.micBusy;
    } else {
      phase = VoicePhase.listeningForWake;
      _error = null;
    }
    _pause = pause;
    if (micOpen && phase == VoicePhase.listeningForWake) {
      _setMode(PipelineMode.wake);
    } else if (micOpen) {
      _setMode(PipelineMode.muted);
    }
    _setPhase(phase);
  }

  void _setMode(
    PipelineMode mode, {
    int noSpeechMs = 8000,
    bool force = false,
  }) {
    final pipeline = _pipeline;
    if (pipeline == null || !pipeline.micOpen) return;
    if (!force && _mode == mode && mode != PipelineMode.command) return;
    _mode = mode;
    _epoch = pipeline.setMode(mode, noSpeechMs: noSpeechMs);
  }

  void _setPhase(VoicePhase phase) {
    if (_phase == phase) return;
    log.add(VoiceTag.voice, '${_phase.name} → ${phase.name}');
    _phase = phase;
    notifyListeners();
    unawaited(_syncNotification());
  }

  Future<void> _syncNotification() async {
    if (!_serviceRunning) {
      _notificationText = null;
      return;
    }
    final text = notificationText;
    if (text == _notificationText) return;
    _notificationText = text;
    await _safe(() => _platform.updateNotification(text));
  }

  /// Одна строка состояния — в уведомлении и в шапке.
  String get notificationText {
    final phrase = WakePhrases.title(_settings.wakePhrase);
    return switch (_phase) {
      VoicePhase.listeningForWake => 'Жду $phrase · распознавание на телефоне',
      VoicePhase.wakeDetected ||
      VoicePhase.listeningForCommand => 'Слушаю команду',
      VoicePhase.processing => 'Выполняю',
      VoicePhase.speaking => 'Отвечаю',
      VoicePhase.paused => switch (_pause) {
        VoicePauseReason.call => 'Пауза на время разговора',
        VoicePauseReason.micBusy => 'Микрофон занят другим приложением',
        VoicePauseReason.externalRecognition => 'Микрофон у другого приложения',
        _ => 'Пауза',
      },
      VoicePhase.recovering => 'Переподключаю микрофон',
      VoicePhase.error => _error ?? 'Ошибка микрофона',
      VoicePhase.starting => 'Загружаю модель распознавания',
      VoicePhase.disabled => 'Выключено',
    };
  }

  // --- События конвейера -----------------------------------------------------

  void _onPipeline(PipelineEvent e) {
    if (_disposed) return;
    if (e is PipelineFailure) {
      _onFailure(e.message, fatal: e.fatal);
      return;
    }
    if (e.epoch != _epoch) return; // событие прошлого режима
    switch (e) {
      case MicLevel(:final level):
        if (!_speaking) _pushLevel(level);
      // Речь в комнате — частое событие: экран из-за неё не перестраиваем,
      // панель отладки сама опрашивает замеры раз в секунду.
      case SpeechStarted():
        diagnostics.vadSpeech = true;
        _resetFailures();
      case SpeechEnded():
        diagnostics.vadSpeech = false;
      case WakeDetected():
        _onWake(e);
      case AwaitingCommand():
        unawaited(_onAwaitingCommand());
      case PartialText(:final text):
        if (_phase == VoicePhase.listeningForCommand ||
            _phase == VoicePhase.wakeDetected) {
          _partial = text;
          notifyListeners();
        }
      case FinalText():
        unawaited(_onFinal(e));
      case BargeIn():
        _onBargeIn(e);
      case WordCaptured():
        final waiting = _enrollWaiter;
        _enrollWaiter = null;
        if (waiting != null && !waiting.isCompleted) waiting.complete(e);
      case PipelineStats(:final rtf, :final vadUs):
        diagnostics.rtf = rtf;
        diagnostics.vadMicros = vadUs;
      case PipelineFailure():
        break;
    }
  }

  void _onWake(WakeDetected e) {
    diagnostics
      ..lastWake = e.heard
      ..lastWakeAt = DateTime.now()
      ..wakeLatency = e.latencyMs
      ..wakeCount += 1;
    log.add(VoiceTag.wake, 'обращение «${e.heard}» за ${e.latencyMs} мс');
    _session = _Session.wake;
    _sessionDone = Completer<void>();
    _partial = e.command;
    // Конвейер сам перешёл к записи команды — ту же фразу он дослушает.
    _mode = PipelineMode.command;
    _setPhase(VoicePhase.wakeDetected);
    _setPhase(VoicePhase.listeningForCommand);
  }

  Future<void> _onAwaitingCommand() async {
    if (_phase != VoicePhase.listeningForCommand) return;
    switch (_settings.cue) {
      case ActivationCue.tone:
        await _safe(() => _platform.playCue(VoiceCue.listening));
      case ActivationCue.voice:
        // «Слушаю» — при заглушенном микрофоне, затем снова слушаем.
        final finished = await _speak('Слушаю', continueSession: true);
        if (finished && _session != _Session.none) {
          await _listenForCommand(noSpeechMs: 6000);
        }
      case ActivationCue.silent:
        break;
    }
  }

  Future<void> _onFinal(FinalText e) async {
    diagnostics
      ..sttEndpoint = e.endpointMs
      ..sttDecode = e.decodeMs;
    _mode = PipelineMode.muted; // конвейер замолк сам до нового режима
    final text = e.text.trim();
    if (text.isEmpty) {
      log.add(VoiceTag.stt, 'тишина — разговор окончен');
      await _endSession();
      return;
    }
    log.add(VoiceTag.stt, 'команда: «$text»', private: true);
    await _runCommand(text);
  }

  void _onBargeIn(BargeIn e) {
    log.add(VoiceTag.tts, 'ответ перебит');
    _speakToken++;
    _speaking = false;
    unawaited(_tts.stop().catchError((_) {}));
    if (_session == _Session.none) {
      // Перебили ответ на набранную команду — это тоже начало разговора.
      _session = _Session.wake;
      _sessionDone = Completer<void>();
    }
    _mode = PipelineMode.command;
    _partial = e.command;
    level.value = 0;
    _setPhase(VoicePhase.listeningForCommand);
  }

  // --- Разговор -------------------------------------------------------------

  static const _stopWords = {
    'стоп',
    'хватит',
    'замолчи',
    'помолчи',
    'тихо',
    'достаточно',
    'всё',
    'все',
    'спасибо',
  };

  Future<void> _runCommand(String text) async {
    diagnostics.lastCommand = text;
    _partial = text;
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\s]', unicode: true), '')
        .trim();
    if (_stopWords.contains(cleaned) && !(dialogAwaiting?.call() ?? false)) {
      log.add(VoiceTag.voice, 'просьба замолчать');
      await _endSession();
      return;
    }

    _setPhase(VoicePhase.processing);
    _setMode(PipelineMode.muted, force: true);
    final handler = onCommand;
    VoiceReply reply;
    final watch = Stopwatch()..start();
    try {
      reply = handler == null
          ? const VoiceReply('')
          : await handler(text).timeout(const Duration(seconds: 25));
    } catch (e) {
      log.add(VoiceTag.action, 'команда не выполнена: $e');
      reply = const VoiceReply('Не получилось выполнить команду.');
    }
    diagnostics.processing = watch.elapsedMilliseconds;
    log.add(VoiceTag.action, 'выполнено за ${watch.elapsedMilliseconds} мс');
    _partial = '';
    if (_disposed || _session == _Session.none) return;

    if (reply.text.isNotEmpty && !reply.alreadySpoken) {
      final finished = await _speak(reply.text, continueSession: true);
      if (!finished) return; // перебили — уже слушаем новую команду
    }
    if (_disposed || _session == _Session.none) return;

    final followUp = reply.expectsReply
        ? 8000
        : _session == _Session.wake && _settings.conversationSeconds > 0
        ? _settings.conversationSeconds * 1000
        : 0;
    if (followUp > 0) {
      await _listenForCommand(noSpeechMs: followUp);
    } else {
      await _endSession();
    }
  }

  Future<void> _listenForCommand({required int noSpeechMs}) async {
    _partial = '';
    if (_pipelineReady && (_pipeline?.micOpen ?? false)) {
      _setPhase(VoicePhase.listeningForCommand);
      _setMode(PipelineMode.command, noSpeechMs: noSpeechMs, force: true);
      return;
    }
    if (_pipelineReady) {
      // Микрофон закрылся (звонок, сбой) — продолжать разговор нечем.
      await _endSession();
      return;
    }
    await _fallbackListen();
  }

  Future<void> _endSession() async {
    _session = _Session.none;
    _partial = '';
    level.value = 0;
    final done = _sessionDone;
    _sessionDone = null;
    if (done != null && !done.isCompleted) done.complete();
    _mode = null;
    if (_pipeline == null || !_pipelineReady) {
      _setPhase(VoicePhase.disabled);
    }
    notifyListeners();
    await _reconcile();
  }

  Future<void> _cancelSession() async {
    if (_session == _Session.none) return;
    _speakToken++;
    if (_speaking) await _tts.stop().catchError((_) {});
    _speaking = false;
    if (!_pipelineReady) await _stt.stop().catchError((_) {});
    await _endSession();
  }

  // --- Кнопка микрофона -----------------------------------------------------

  /// Нажата кнопка записи: слушаем одну команду. Завершается, когда
  /// разговор окончен.
  Future<void> listen() async {
    if (_disposed) return;
    if (_phase == VoicePhase.processing) return;
    if (_phase == VoicePhase.listeningForCommand) return;
    if (!voiceAvailable) {
      _error = 'Распознавание речи на этом устройстве недоступно';
      notifyListeners();
      return;
    }
    if (_speaking) {
      _speakToken++;
      _speaking = false;
      await _tts.stop().catchError((_) {});
    }
    _session = _Session.manual;
    final done = _sessionDone = Completer<void>();
    if (_pipelineReady) {
      await _reconcile(); // откроет микрофон, даже если обращение выключено
      if (!(_pipeline?.micOpen ?? false)) {
        await _endSession();
        return;
      }
      await _listenForCommand(noSpeechMs: 8000);
    } else {
      unawaited(_fallbackListen());
    }
    await done.future;
  }

  /// Остановить запись без выполнения.
  Future<void> stopListening() async {
    if (_phase != VoicePhase.listeningForCommand) return;
    log.add(VoiceTag.stt, 'запись остановлена');
    if (_pipelineReady) {
      _setMode(PipelineMode.muted, force: true);
    }
    await _cancelSession();
  }

  /// Системное распознавание: только когда своя модель не поднялась.
  Future<void> _fallbackListen() async {
    _setPhase(VoicePhase.listeningForCommand);
    _sttPartialSub = _stt.partialResults().listen((t) {
      _partial = t;
      notifyListeners();
    });
    _sttLevelSub = _stt.soundLevels().listen(_pushLevel);
    var phrase = '';
    try {
      await _tts.stop();
      await _stt.start();
      phrase = await _stt.finalResult();
    } catch (e) {
      _error = e is SpeechError
          ? e.message
          : 'Не удалось включить микрофон: $e';
      log.add(VoiceTag.stt, 'системное распознавание: $_error');
    } finally {
      await _sttPartialSub?.cancel();
      await _sttLevelSub?.cancel();
      _sttPartialSub = null;
      _sttLevelSub = null;
      level.value = 0;
    }
    if (_disposed) return;
    if (phrase.trim().isEmpty) {
      await _endSession();
      return;
    }
    await _runCommand(phrase.trim());
  }

  // --- Ответ голосом ----------------------------------------------------------

  /// Произнести ответ на набранную команду или уведомление навыка.
  /// Микрофон на время ответа заглушается — ассистент не слышит себя.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _speak(text, continueSession: _session != _Session.none);
  }

  /// Сказать ещё раз, даже если голосовые ответы выключены.
  Future<void> speakForced(String text) async {
    final enabled = _tts.enabled;
    _tts.enabled = true;
    try {
      await _speak(text, continueSession: _session != _Session.none);
    } finally {
      _tts.enabled = enabled;
    }
  }

  Future<void> stopSpeaking() async {
    _speakToken++;
    await _tts.stop().catchError((_) {});
  }

  /// true — договорили, false — перебили или отменили.
  Future<bool> _speak(String text, {required bool continueSession}) async {
    if (!_tts.enabled) return true;
    final token = ++_speakToken;
    _speaking = true;
    _speakStarted = DateTime.now();
    diagnostics.ttsFirstAudio = null;
    final canInterrupt = _settings.interrupt && _settings.wakeEnabled;
    _setMode(
      canInterrupt ? PipelineMode.bargeIn : PipelineMode.muted,
      force: true,
    );
    _setPhase(VoicePhase.speaking);
    log.add(VoiceTag.tts, 'ответ: «$text»', private: true);
    try {
      await _tts.speak(text);
    } catch (e) {
      log.add(VoiceTag.tts, 'озвучка не удалась: $e');
      _error = 'Ответ показан на экране: нет русского офлайн-голоса Android';
    }
    if (token != _speakToken) return false;
    _speaking = false;
    level.value = 0;
    // Хвост звука в комнате не должен разбудить конвейер.
    if (guardAfterSpeech > Duration.zero) {
      await Future<void>.delayed(guardAfterSpeech);
    }
    if (token != _speakToken || _disposed) return false;
    if (!continueSession && _session == _Session.none) {
      // Ответ на набранную команду: вернуться в обычное ожидание.
      _mode = null;
      if (_phase == VoicePhase.speaking) _phase = VoicePhase.starting;
      await _reconcile();
    }
    return true;
  }

  void _onPulse(double pulse) {
    if (!_speaking) return;
    final started = _speakStarted;
    if (diagnostics.ttsFirstAudio == null && started != null) {
      diagnostics.ttsFirstAudio = DateTime.now()
          .difference(started)
          .inMilliseconds;
    }
    level.value = math.max(level.value, 0.55 + 0.35 * pulse);
    // Плавное затухание до следующего слова.
    Future<void>.delayed(const Duration(milliseconds: 160), () {
      if (_speaking && !_disposed) level.value = level.value * 0.45;
    });
  }

  void _pushLevel(double value) {
    final current = level.value;
    // Быстро вверх, плавно вниз — как стрелка индикатора.
    level.value = value > current
        ? current + (value - current) * 0.6
        : current + (value - current) * 0.25;
  }

  // --- Сбои и восстановление ------------------------------------------------

  void _onFailure(String message, {required bool fatal}) {
    log.add(VoiceTag.audio, 'сбой: $message');
    _retry?.cancel();
    _stable?.cancel();
    _mode = null;
    final hadSession = _session != _Session.none;
    _session = _Session.none;
    _partial = '';
    final done = _sessionDone;
    _sessionDone = null;
    if (done != null && !done.isCompleted) done.complete();
    if (hadSession && _speaking) unawaited(_tts.stop().catchError((_) {}));
    _speaking = false;

    if (fatal) {
      _error = message;
      _setPhase(VoicePhase.error);
      return;
    }
    _failures++;
    if (_failures > 6) {
      _error = 'Микрофон недоступен: $message';
      _setPhase(VoicePhase.error);
      return;
    }
    _error = message;
    final delay = Duration(seconds: math.min(30, 1 << (_failures - 1)));
    log.add(VoiceTag.audio, 'повтор через ${delay.inSeconds} с');
    _setPhase(VoicePhase.recovering);
    _retry = Timer(delay, () {
      if (_disposed) return;
      _phase = VoicePhase.starting;
      unawaited(_reconcile());
    });
  }

  /// Микрофон проработал без сбоев — счётчик повторов обнуляется.
  void _armStableTimer() {
    _stable?.cancel();
    _stable = Timer(const Duration(seconds: 20), _resetFailures);
  }

  void _resetFailures() {
    if (_failures == 0) return;
    _failures = 0;
    log.add(VoiceTag.audio, 'микрофон стабилен');
  }

  // --- События телефона -------------------------------------------------------

  void _onPlatform(PlatformVoiceEvent e) {
    if (_disposed) return;
    switch (e) {
      case LockChanged(:final locked):
        _locked = locked;
        notifyListeners();
      case CallChanged(:final active):
        if (_callActive == active) return;
        _callActive = active;
        log.add(VoiceTag.audio, active ? 'идёт звонок' : 'звонок окончен');
        if (active) unawaited(_cancelSession());
        unawaited(_reconcile());
      case MicSilenced(:final silenced):
        if (_silenced == silenced) return;
        _silenced = silenced;
        log.add(
          VoiceTag.audio,
          silenced ? 'Android заглушил запись' : 'запись снова слышна',
        );
        unawaited(_reconcile());
      case ServiceChanged(:final running, :final userStopped):
        _serviceRunning = running;
        if (userStopped) {
          log.add(VoiceTag.background, 'выключено из уведомления');
          unawaited(updateSettings(_settings.copyWith(background: false)));
        } else {
          unawaited(_reconcile());
        }
      case AssistInvoked():
        // Команду жеста забираем из очереди: так один жест — одна команда,
        // даже если о нём сообщили и событие, и возврат экрана.
        unawaited(_takeAssistCommand());
      case ExternalRecognition(:final active):
        _externalRecognition = active;
        unawaited(_reconcile());
    }
  }

  Future<void> _takeAssistCommand() async {
    final command = await _safe(_platform.takeCommand);
    if (command == null || _disposed) return;
    if (command.isEmpty) {
      unawaited(listen());
    } else {
      _session = _Session.manual;
      _sessionDone = Completer<void>();
      await _reconcile();
      await _runCommand(command);
    }
  }

  /// Проверить команду из системного жеста помощника (новый Intent).
  Future<void> checkAssistCommand() => _takeAssistCommand();

  // --- Обучение голосу ------------------------------------------------------

  Completer<WordCaptured>? _enrollWaiter;

  /// Записать одно «Макс» для обучения. null — модель не готова или
  /// ничего не услышано; пустой отпечаток с длительностью — сказано слишком
  /// длинно.
  Future<WordCaptured?> captureVoiceSample() async {
    if (!_pipelineReady || _disposed || _session != _Session.none) return null;
    if (_speaking) await stopSpeaking();
    _session = _Session.enroll;
    _sessionDone = Completer<void>();
    final waiter = _enrollWaiter = Completer<WordCaptured>();
    try {
      await _reconcile();
      if (!(_pipeline?.micOpen ?? false)) return null;
      _partial = '';
      _setPhase(VoicePhase.listeningForCommand);
      _setMode(PipelineMode.enroll, noSpeechMs: 6000, force: true);
      return await waiter.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => WordCaptured(_epoch, const [], durationMs: 0),
      );
    } finally {
      _enrollWaiter = null;
      if (_session == _Session.enroll) await _endSession();
    }
  }

  /// Сохранить образцы и сразу включить сравнение по звучанию.
  Future<void> saveVoice(List<VoicePrint> prints) async {
    final voice = WakeVoice.enroll(prints);
    _voice = voice.isEmpty ? null : voice;
    await _store.saveVoice(_voice);
    _pipeline?.configure(_pipelineConfig());
    log.add(
      VoiceTag.wake,
      'обучено на ${voice.prints.length} образцах, порог '
      '${voice.threshold.toStringAsFixed(2)}',
    );
    notifyListeners();
  }

  Future<void> clearVoice() async {
    _voice = null;
    await _store.saveVoice(null);
    _pipeline?.configure(_pipelineConfig());
    notifyListeners();
  }

  // --- Для экрана настроек ---------------------------------------------------

  Future<PlatformVoiceStatus> platformStatus() async =>
      await _safe(_platform.status) ?? const PlatformVoiceStatus();

  Future<void> selectAssistant() async => _safe(_platform.selectAssistant);

  Future<void> openBatterySettings() async =>
      _safe(_platform.openBatterySettings);

  Future<List<TtsVoice>> voices() async => await _safe(_tts.voices) ?? const [];

  /// Проверить голос: короткая фраза выбранным голосом.
  Future<void> previewVoice() =>
      speakForced('Привет! Я Alym. Скажите «Макс», и я помогу.');

  Future<T?> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      log.add(VoiceTag.background, 'системный вызов не удался: $e');
      return null;
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retry?.cancel();
    _stable?.cancel();
    _speakToken++;
    await _pipelineSub?.cancel();
    await _platformSub?.cancel();
    await _pulseSub?.cancel();
    await _sttPartialSub?.cancel();
    await _sttLevelSub?.cancel();
    await _ops;
    await _pipeline?.close();
    await _pipeline?.dispose();
    await _stt.stop().catchError((_) {});
    await _stt.dispose().catchError((_) {});
    level.dispose();
    super.dispose();
  }
}
