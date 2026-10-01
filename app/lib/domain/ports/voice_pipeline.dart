import '../voice/voice_print.dart';
import '../voice/voice_settings.dart';

export '../voice/voice_print.dart' show VoicePrint, WakeVoice;

/// Что конвейер делает с непрерывным звуком микрофона.
enum PipelineMode {
  /// Звук отбрасывается, VAD не работает.
  muted,

  /// Ждёт речь и ищет в ней обращение.
  wake,

  /// Записывает команду до паузы.
  command,

  /// Ответ звучит: слушает только перебивание.
  bargeIn,

  /// Обучение: записать одно слово и вернуть его отпечаток.
  enroll,
}

/// Параметры конвейера, которые меняются настройками.
class PipelineConfig {
  const PipelineConfig({
    this.wakePhrase = WakePhrases.max,
    this.sensitivity = WakeSensitivity.medium,
    this.speechThreshold = 0.5,
    this.silenceMs = 700,
    this.maxUtteranceMs = 15000,
    this.wakeWindowMs = 2500,
    this.bargeInNeedsWake = true,
    this.bargeInSpeechMs = 400,
    this.voice,
  });

  factory PipelineConfig.from(
    VoiceSettings s, {
    required bool echoCancelled,
    WakeVoice? voice,
  }) => PipelineConfig(
    voice: voice,
    wakePhrase: s.wakePhrase,
    sensitivity: s.sensitivity,
    speechThreshold: s.speechThreshold,
    silenceMs: s.silenceMs,
    maxUtteranceMs: s.maxUtteranceMs,
    // Без подавления эха динамик слышен в микрофон как речь: перебить
    // можно только обращением, которого в ответе нет.
    bargeInNeedsWake: !echoCancelled,
  );

  final String wakePhrase;
  final WakeSensitivity sensitivity;
  final double speechThreshold;

  /// Тишина после речи, после которой команда считается законченной.
  final int silenceMs;
  final int maxUtteranceMs;

  /// Сколько секунд речи расшифровывать в поисках обращения. Дальше —
  /// чужой разговор или телевизор: T-one выключается до паузы.
  final int wakeWindowMs;

  final bool bargeInNeedsWake;

  /// Сколько непрерывной речи считать перебиванием, если обращение не нужно.
  final int bargeInSpeechMs;

  /// Образцы «Макс» голосом человека: одиночное слово, которое T-one не
  /// расшифровала, сравнивается с ними по звучанию.
  final WakeVoice? voice;

  @override
  bool operator ==(Object other) =>
      other is PipelineConfig &&
      other.wakePhrase == wakePhrase &&
      other.sensitivity == sensitivity &&
      other.speechThreshold == speechThreshold &&
      other.silenceMs == silenceMs &&
      other.maxUtteranceMs == maxUtteranceMs &&
      other.wakeWindowMs == wakeWindowMs &&
      other.bargeInNeedsWake == bargeInNeedsWake &&
      other.bargeInSpeechMs == bargeInSpeechMs &&
      identical(other.voice, voice);

  @override
  int get hashCode => Object.hash(
    wakePhrase,
    sensitivity,
    speechThreshold,
    silenceMs,
    maxUtteranceMs,
    wakeWindowMs,
    bargeInNeedsWake,
    bargeInSpeechMs,
    voice,
  );
}

/// Обработка звука платформой при открытии микрофона.
class MicConfig {
  const MicConfig({
    this.echoCancellation = false,
    this.noiseSuppression = true,
  });

  final bool echoCancellation;
  final bool noiseSuppression;

  Map<String, Object> toMap() => {
    'aec': echoCancellation,
    'ns': noiseSuppression,
  };

  @override
  bool operator ==(Object other) =>
      other is MicConfig &&
      other.echoCancellation == echoCancellation &&
      other.noiseSuppression == noiseSuppression;

  @override
  int get hashCode => Object.hash(echoCancellation, noiseSuppression);
}

/// События конвейера. [epoch] — номер режима, в котором событие родилось:
/// VoiceManager отбрасывает всё, что пришло от прошлого режима, поэтому
/// запоздавший результат старой фразы не может закрыть новую.
sealed class PipelineEvent {
  const PipelineEvent(this.epoch);
  final int epoch;
}

class SpeechStarted extends PipelineEvent {
  const SpeechStarted(super.epoch);
}

class SpeechEnded extends PipelineEvent {
  const SpeechEnded(super.epoch);
}

/// Обращение услышано. [latencyMs] — от начала речи до срабатывания.
class WakeDetected extends PipelineEvent {
  const WakeDetected(
    super.epoch, {
    required this.heard,
    required this.command,
    required this.latencyMs,
  });
  final String heard;
  final String command;
  final int latencyMs;
}

/// Прозвучало одно имя и пауза: пора подать сигнал и ждать команду.
class AwaitingCommand extends PipelineEvent {
  const AwaitingCommand(super.epoch);
}

class PartialText extends PipelineEvent {
  const PartialText(super.epoch, this.text);
  final String text;
}

/// Конец команды. Пустой текст — тишина или ничего не разобрано.
/// [endpointMs] — сколько тишины понадобилось, [decodeMs] — сколько времени
/// процессора ушло на расшифровку фразы.
class FinalText extends PipelineEvent {
  const FinalText(
    super.epoch,
    this.text, {
    this.endpointMs = 0,
    this.decodeMs = 0,
  });
  final String text;
  final int endpointMs;
  final int decodeMs;
}

/// Человек перебил ответ. [command] — что успел сказать после имени.
class BargeIn extends PipelineEvent {
  const BargeIn(super.epoch, {this.command = ''});
  final String command;
}

/// Обучение: записано одно слово. Пустой [print] — не расслышал или
/// сказано слишком длинно ([durationMs] подскажет, что именно).
class WordCaptured extends PipelineEvent {
  const WordCaptured(super.epoch, this.print, {required this.durationMs});
  final VoicePrint print;
  final int durationMs;
}

/// Громкость 0..1 — только пока экран её показывает.
class MicLevel extends PipelineEvent {
  const MicLevel(super.epoch, this.level);
  final double level;
}

/// Нагрузка: [rtf] — доля реального времени, которую занимает T-one.
class PipelineStats extends PipelineEvent {
  const PipelineStats(super.epoch, {required this.rtf, required this.vadUs});
  final double rtf;

  /// Среднее время одного окна VAD, микросекунды.
  final int vadUs;
}

/// Микрофон или модель отказали.
class PipelineFailure extends PipelineEvent {
  const PipelineFailure(super.epoch, this.message, {this.fatal = false});
  final String message;

  /// true — повтор не поможет (нет разрешения).
  final bool fatal;
}

/// Непрерывный конвейер: микрофон → VAD → обращение → команда.
///
/// Микрофон открывается один раз и не закрывается между фразами: так нет
/// щелчков, системных сигналов и пропущенного «Макс» в паузах переоткрытия.
abstract class VoicePipeline {
  /// Загрузить модели. Один раз при старте.
  Future<void> init();

  bool get ready;

  /// Микрофон открыт.
  bool get micOpen;

  Stream<PipelineEvent> get events;

  /// Открыть микрофон. Повторный вызов с теми же параметрами ничего не
  /// делает; с другими — переоткрывает.
  Future<void> open(MicConfig mic);

  /// Закрыть микрофон и освободить запись.
  Future<void> close();

  /// Сменить режим. Возвращает номер нового режима — события с меньшим
  /// номером устарели.
  int setMode(PipelineMode mode, {int noSpeechMs = 8000});

  void configure(PipelineConfig config);

  /// Слать ли громкость. Пока экран скрыт, она никому не нужна.
  void setLevelsEnabled(bool enabled);

  Future<void> dispose();
}
