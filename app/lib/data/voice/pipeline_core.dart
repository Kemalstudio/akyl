import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/ports/voice_pipeline.dart';
import '../../domain/voice/voice_print.dart';
import '../../domain/voice/wake_matcher.dart';

/// Детектор речи: одно окно 512 отсчётов (32 мс на 16 кГц) за вызов.
abstract class VadEngine {
  void accept(Float32List window);

  /// Сейчас идёт речь. Включает задержку отпускания [PipelineCore.vadHangoverMs].
  bool get speech;

  void reset();
}

/// Потоковое распознавание: звук кусками, текст по мере расшифровки.
abstract class AsrEngine {
  void reset();
  void accept(Float32List samples);

  /// Звук кончился: дописать последние слова. До [reset] звук не принимается.
  void flush();

  String get text;
}

/// Логика конвейера без платформы: превращает непрерывный звук в события.
///
/// Экономия энергии построена на трёх ступенях:
/// 1. VAD (Silero, ~0.3 мс на окно) слушает всегда, пока режим не [PipelineMode.muted];
/// 2. T-one включается только на речь — тишина её не будит;
/// 3. в режиме ожидания T-one расшифровывает не больше [PipelineConfig.wakeWindowMs]
///    каждой фразы: если имени в начале не было, дальше — чужой разговор.
///
/// Время считается в отсчётах звука, а не по часам: так поведение не зависит
/// от загрузки телефона и одинаково в тестах.
class PipelineCore {
  PipelineCore({
    required this.vad,
    required this.asr,
    required this.emit,
    PipelineConfig config = const PipelineConfig(),
    int Function()? micros,
  }) : _micros = micros ?? _stopwatchMicros {
    configure(config);
  }

  static const sampleRate = 16000;
  static const window = 512;

  /// Столько VAD держит «речь» после её конца (minSilenceDuration Silero).
  static const vadHangoverMs = 250;

  /// Сколько звука до срабатывания VAD отдавать распознаванию: VAD замечает
  /// речь с опозданием, и без запаса «Макс» терял бы «М».
  static const prerollMs = 600;

  /// Тишина, после которой перестаём ждать команду после обращения.
  static const commandNoSpeechMs = 6000;

  /// Сколько звука после конца фразы дать T-one, прежде чем решить, было ли
  /// в ней имя. Замерено: без хвоста одиночное «Макс» не успевает дописаться.
  static const tailMs = 500;

  final VadEngine vad;
  final AsrEngine asr;
  final void Function(PipelineEvent event) emit;
  final int Function() _micros;

  static final _clock = Stopwatch()..start();
  static int _stopwatchMicros() => _clock.elapsedMicroseconds;

  late PipelineConfig _config;
  late WakeMatcher _matcher;

  PipelineConfig get config => _config;

  int _epoch = 0;
  PipelineMode _mode = PipelineMode.muted;
  PipelineMode get mode => _mode;

  /// Время в отсчётах с создания.
  int _t = 0;

  final Float32List _window = Float32List(window);
  int _windowFill = 0;

  final _preroll = _Ring(sampleRate * prerollMs ~/ 1000);

  bool _vadSpeech = false;

  /// Внутри фразы, которую обрабатываем.
  bool _inSpeech = false;
  int _onset = 0;
  bool _skipping = false;
  int _tail = 0;

  /// Команда продолжает ту же фразу, где прозвучало имя.
  bool _carry = false;

  /// Команда — это текст после имени.
  bool _stripWake = false;

  int _waited = 0;
  int _noSpeechLimit = 0;
  int _silence = 0;
  int _bargeSpeech = 0;
  String _lastPartial = '';
  int _decodeUs = 0;

  /// Звук текущей фразы — для сравнения одиночного слова с голосом человека.
  final _capture = _Recording(sampleRate * captureMaxMs ~/ 1000);
  int _speechEnd = 0;
  MfccExtractor? _mfcc;

  /// Одиночное слово для сравнения с образцом: не короче и не длиннее этого.
  static const captureMinMs = 300;
  static const captureMaxMs = 1500;

  bool levelsEnabled = false;
  double _sumSquares = 0;
  int _levelSamples = 0;

  int _asrUs = 0;
  int _asrSamples = 0;
  int _vadUs = 0;
  int _vadWindows = 0;
  int _statsAt = 0;

  void configure(PipelineConfig config) {
    _config = config;
    _matcher = WakeMatcher(
      phrase: config.wakePhrase,
      sensitivity: config.sensitivity,
    );
  }

  int _samples(int ms) => sampleRate * ms ~/ 1000;
  int _ms(int samples) => samples * 1000 ~/ sampleRate;

  /// Сменить режим извне. Всё незаконченное прежнего режима забывается.
  void setMode(int epoch, PipelineMode mode, {int noSpeechMs = 8000}) {
    _epoch = epoch;
    _mode = mode;
    _noSpeechLimit = _samples(noSpeechMs);
    _resetUtterance();
    _vadSpeech = false;
    vad.reset();
  }

  void _resetUtterance() {
    _inSpeech = false;
    _skipping = false;
    _tail = 0;
    _carry = false;
    _stripWake = false;
    _waited = 0;
    _silence = 0;
    _bargeSpeech = 0;
    _lastPartial = '';
    _decodeUs = 0;
  }

  /// Звук с микрофона: 16 кГц, моно, −1..1, кусками любой длины.
  void feed(Float32List samples) {
    var i = 0;
    while (i < samples.length) {
      final take = math.min(window - _windowFill, samples.length - i);
      _window.setRange(_windowFill, _windowFill + take, samples, i);
      _windowFill += take;
      i += take;
      if (_windowFill == window) {
        _windowFill = 0;
        _processWindow(_window);
      }
    }
  }

  /// 16-битный PCM little-endian, как его отдаёт Android.
  void feedPcm16(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    final count = bytes.length ~/ 2;
    final samples = Float32List(count);
    for (var i = 0; i < count; i++) {
      samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    feed(samples);
  }

  void _processWindow(Float32List w) {
    _t += window;
    if (levelsEnabled) _measureLevel(w);

    if (_mode == PipelineMode.muted) {
      _preroll.push(w);
      return;
    }

    final started = _micros();
    vad.accept(w);
    _vadUs += _micros() - started;
    _vadWindows++;
    final speech = vad.speech;
    if (speech != _vadSpeech) {
      _vadSpeech = speech;
      emit(speech ? SpeechStarted(_epoch) : SpeechEnded(_epoch));
    }

    switch (_mode) {
      case PipelineMode.wake || PipelineMode.bargeIn:
        _wakeWindow(w, speech);
      case PipelineMode.command:
        _commandWindow(w, speech);
      case PipelineMode.enroll:
        _enrollWindow(w, speech);
      case PipelineMode.muted:
        break;
    }
    _preroll.push(w);
    _maybeStats();
  }

  // --- Ожидание обращения ----------------------------------------------------

  void _wakeWindow(Float32List w, bool speech) {
    if (!_inSpeech) {
      if (!speech) return;
      _inSpeech = true;
      _onset = _t;
      _skipping = false;
      _tail = 0;
      _bargeSpeech = 0;
      _speechEnd = 0;
      _capture
        ..clear()
        ..add(_preroll.contents())
        ..add(w);
      _asrReset();
      _asrAccept(_preroll.contents());
      _asrAccept(w);
      _checkWake(atEnd: false);
      return;
    }

    if (speech) {
      _capture.add(w);
    } else if (_speechEnd == 0) {
      _speechEnd = _t;
    }

    if (!speech) {
      if (_skipping) {
        _inSpeech = false;
        return;
      }
      // Фраза кончилась, но T-one выдаёт последние слова с опозданием:
      // ей нужен звук после них. Кормим хвост и только потом решаем.
      _asrAccept(w);
      _tail += window;
      _checkWake(atEnd: false);
      if (_mode != PipelineMode.wake && _mode != PipelineMode.bargeIn) return;
      if (_tail >= _samples(tailMs)) {
        _asrFlush();
        _checkWake(atEnd: true);
        if (_mode != PipelineMode.command) _inSpeech = false;
        _tail = 0;
      }
      return;
    }
    _tail = 0;
    if (_skipping) return;

    _asrAccept(w);
    if (_mode == PipelineMode.bargeIn && !_config.bargeInNeedsWake) {
      _bargeSpeech += window;
      if (_bargeSpeech >= _samples(_config.bargeInSpeechMs)) {
        emit(BargeIn(_epoch));
        _enterCommand(stripWake: false);
        return;
      }
    }
    _checkWake(atEnd: false);
    if (_mode != PipelineMode.command &&
        _t - _onset > _samples(_config.wakeWindowMs)) {
      _skipping = true;
    }
  }

  void _checkWake({required bool atEnd}) {
    final match = _matcher.match(asr.text, complete: atEnd);
    if (match == null) {
      if (atEnd) _checkVoice();
      return;
    }
    // Имя — последнее слово промежуточного текста: это может быть начало
    // «Максим» или «Максу». Ждём следующего слова или паузы.
    if (!atEnd && match.command.isEmpty) return;
    final latency = _ms(_t - _onset);
    if (_mode == PipelineMode.bargeIn) {
      emit(BargeIn(_epoch, command: match.command));
    } else {
      emit(
        WakeDetected(
          _epoch,
          heard: match.heard,
          command: match.command,
          latencyMs: latency,
        ),
      );
    }
    if (atEnd && match.command.isEmpty) {
      // Имя и пауза: команду ждём следующей фразой.
      _enterCommand(stripWake: false);
      _inSpeech = false;
      _carry = false;
      asr.reset();
      emit(AwaitingCommand(_epoch));
      return;
    }
    if (atEnd) {
      // Фраза целиком уже позади и дописана: команда готова.
      _finish(match.command, endpointMs: vadHangoverMs + tailMs);
      return;
    }
    _enterCommand(stripWake: true);
  }

  /// Одиночное короткое слово, которое T-one не расшифровала как имя, —
  /// сравнить по звучанию с образцами голоса человека. Замер: T-one пишет
  /// одиночное «Макс.» пустой строкой, «н», «на» или «нас», а сравнение с
  /// тремя образцами того же голоса узнаёт его в ~80% случаев.
  void _checkVoice() {
    final voice = _config.voice;
    if (voice == null || voice.isEmpty || _mode != PipelineMode.wake) return;
    final length = _ms((_speechEnd == 0 ? _t : _speechEnd) - _onset);

    if (length < captureMinMs || length > captureMaxMs + vadHangoverMs) return;
    // Если T-one ясно услышала другое слово («да», «так») — это не имя.
    final words = asr.text.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length > 1) return;
    if (words.length == 1 && !_nameLike(words.single)) return;
    final started = _micros();
    final word = (_mfcc ??= MfccExtractor()).extract(_capture.samples());
    final matched = voice.matches(word);
    _decodeUs += _micros() - started;
    if (!matched) return;
    emit(
      WakeDetected(
        _epoch,
        heard: 'голос',
        command: '',
        latencyMs: _ms(_t - _onset),
      ),
    );
    _enterCommand(stripWake: false);
    _inSpeech = false;
    _carry = false;
    asr.reset();
    emit(AwaitingCommand(_epoch));
  }

  /// Так T-one записывает одиночное «Макс»: коротко, с носового звука.
  static bool _nameLike(String word) =>
      word.length <= 5 && (word.startsWith('м') || word.startsWith('н'));

  // --- Обучение голосу ------------------------------------------------------

  void _enrollWindow(Float32List w, bool speech) {
    if (!_inSpeech) {
      if (!speech) {
        _waited += window;
        if (_waited >= _noSpeechLimit) _captured(const [], 0);
        return;
      }
      _inSpeech = true;
      _onset = _t;
      _speechEnd = 0;
      _capture
        ..clear()
        ..add(_preroll.contents())
        ..add(w);
      return;
    }
    if (speech) {
      _capture.add(w);
      if (_t - _onset > _samples(captureMaxMs + 1000)) {
        _captured(const [], _ms(_t - _onset)); // это уже не одно слово
      }
      return;
    }
    final length = _ms(_t - _onset) - vadHangoverMs;
    if (length < captureMinMs - 150) {
      // Щелчок или кашель: ждём настоящее слово.
      _inSpeech = false;
      return;
    }
    if (length > captureMaxMs) {
      _captured(const [], length);
      return;
    }
    _captured((_mfcc ??= MfccExtractor()).extract(_capture.samples()), length);
  }

  void _captured(VoicePrint print, int durationMs) {
    emit(WordCaptured(_epoch, print, durationMs: durationMs));
    _mode = PipelineMode.muted;
    _resetUtterance();
  }

  void _enterCommand({required bool stripWake}) {
    _mode = PipelineMode.command;
    _carry = true;
    _stripWake = stripWake;
    _waited = 0;
    _silence = 0;
    _noSpeechLimit = _samples(commandNoSpeechMs);
    _lastPartial = '';
  }

  // --- Команда -----------------------------------------------------------------

  void _commandWindow(Float32List w, bool speech) {
    if (!_inSpeech) {
      if (!speech) {
        _waited += window;
        if (_waited >= _noSpeechLimit) _finish('', endpointMs: 0);
        return;
      }
      _inSpeech = true;
      _onset = _t;
      _silence = 0;
      if (!_carry) {
        _decodeUs = 0;
        _asrReset();
        _asrAccept(_preroll.contents());
      }
      _asrAccept(w);
      _emitPartial();
      return;
    }

    _asrAccept(w);
    _emitPartial();
    _silence = speech ? 0 : _silence + window;

    final quiet = _samples(_config.silenceMs - vadHangoverMs);
    if (_silence >= math.max(quiet, window)) {
      _asrFlush();
      final text = _commandText();
      if (text.isNotEmpty) {
        _finish(text, endpointMs: _config.silenceMs);
        return;
      }
      // Кашель, шорох или одно имя — продолжаем ждать команду.
      if (_stripWake) emit(AwaitingCommand(_epoch));
      asr.reset(); // после flush поток принимает звук только после сброса
      _inSpeech = false;
      _carry = false;
      _stripWake = false;
      _waited = 0;
      return;
    }
    if (_t - _onset > _samples(_config.maxUtteranceMs)) {
      _asrFlush();
      _finish(_commandText(), endpointMs: 0);
    }
  }

  void _asrFlush() {
    final started = _micros();
    asr.flush();
    final spent = _micros() - started;
    _decodeUs += spent;
    _asrUs += spent;
  }

  String _commandText() {
    final text = asr.text;
    if (!_stripWake) return text;
    return _matcher.match(text)?.command ?? text;
  }

  void _emitPartial() {
    final text = _commandText();
    if (text == _lastPartial) return;
    _lastPartial = text;
    emit(PartialText(_epoch, text));
  }

  void _finish(String text, {required int endpointMs}) {
    emit(
      FinalText(
        _epoch,
        text,
        endpointMs: endpointMs,
        decodeMs: _decodeUs ~/ 1000,
      ),
    );
    // Дальше решает VoiceManager: до нового режима звук не обрабатывается,
    // поэтому второго финала у одной команды быть не может.
    _mode = PipelineMode.muted;
    _resetUtterance();
  }

  // --- Распознавание и замеры ------------------------------------------------

  void _asrReset() => asr.reset();

  void _asrAccept(Float32List samples) {
    if (samples.isEmpty) return;
    final started = _micros();
    asr.accept(samples);
    final spent = _micros() - started;
    _decodeUs += spent;
    _asrUs += spent;
    _asrSamples += samples.length;
  }

  static const _levelEvery = window * 3; // ~100 мс

  void _measureLevel(Float32List w) {
    for (final s in w) {
      _sumSquares += s * s;
    }
    _levelSamples += w.length;
    if (_levelSamples < _levelEvery) return;
    final meanSquare = _sumSquares / _levelSamples;
    _sumSquares = 0;
    _levelSamples = 0;
    emit(MicLevel(_epoch, _level(meanSquare)));
  }

  /// Громкость 0..1 по среднеквадратичному: от −50 дБ (тишина) до −10 дБ.
  static double _level(double meanSquare) {
    if (meanSquare <= 0) return 0;
    final db = 10 * math.log(meanSquare) / math.ln10;
    return ((db + 50) / 40).clamp(0.0, 1.0);
  }

  void _maybeStats() {
    if (!levelsEnabled || _t - _statsAt < sampleRate * 5) return;
    _statsAt = _t;
    final audioUs = _asrSamples * 1000000 ~/ sampleRate;
    emit(
      PipelineStats(
        _epoch,
        rtf: audioUs == 0 ? 0 : _asrUs / audioUs,
        vadUs: _vadWindows == 0 ? 0 : _vadUs ~/ _vadWindows,
      ),
    );
    _asrUs = 0;
    _asrSamples = 0;
    _vadUs = 0;
    _vadWindows = 0;
  }
}

/// Звук одной фразы, не длиннее [capacity] отсчётов.
class _Recording {
  _Recording(int capacity) : _data = Float32List(capacity);

  final Float32List _data;
  int _length = 0;

  void clear() => _length = 0;

  void add(Float32List samples) {
    final take = math.min(samples.length, _data.length - _length);
    if (take <= 0) return;
    _data.setRange(_length, _length + take, samples);
    _length += take;
  }

  Float32List samples() => Float32List.sublistView(_data, 0, _length);
}

/// Кольцевой буфер последних отсчётов.
class _Ring {
  _Ring(int capacity) : _data = Float32List(capacity);

  final Float32List _data;
  int _write = 0;
  int _filled = 0;

  void push(Float32List samples) {
    for (final s in samples) {
      _data[_write] = s;
      _write = (_write + 1) % _data.length;
    }
    _filled = math.min(_filled + samples.length, _data.length);
  }

  Float32List contents() {
    final out = Float32List(_filled);
    final start = (_write - _filled + _data.length) % _data.length;
    for (var i = 0; i < _filled; i++) {
      out[i] = _data[(start + i) % _data.length];
    }
    return out;
  }
}
