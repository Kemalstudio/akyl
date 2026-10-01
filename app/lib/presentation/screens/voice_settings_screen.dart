import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/ports/text_to_speech.dart';
import '../../domain/ports/voice_platform.dart';
import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import '../voice_manager.dart';
import '../widgets/akyl_switch.dart';
import '../widgets/alym_logo.dart';
import '../widgets/glass_background.dart';
import '../widgets/premium_controls.dart';
import '../widgets/settings_kit.dart';
import '../widgets/voice_training_sheet.dart';
import 'voice_debug_screen.dart';

/// Голос и обращение: как помощник слушает, отвечает и работает в фоне.
///
/// Каждый переключатель меняет реальное поведение — здесь нет «выбора
/// модели», которой в офлайн-приложении нет.
class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key, required this.voice});

  final VoiceManager voice;

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen>
    with WidgetsBindingObserver {
  VoiceManager get voice => widget.voice;
  PlatformVoiceStatus _status = const PlatformVoiceStatus();
  List<TtsVoice> _voices = const [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    voice.addListener(_refresh);
    _loadStatus();
    unawaited(
      voice.voices().then((v) {
        if (mounted) setState(() => _voices = v);
      }),
    );
    // Статус службы и роли помощника меняется в системных настройках.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _loadStatus());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await voice.platformStatus();
    if (mounted) setState(() => _status = status);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    voice.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _update(VoiceSettings Function(VoiceSettings s) change) async {
    unawaited(HapticFeedback.selectionClick());
    await voice.updateSettings(change(voice.settings));
    await _loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    final s = voice.settings;
    final wake = voice.wakeAvailable;

    var order = 0;
    Widget enter(Widget child) => FadeSlideIn(
      delay: AkylMotion.stagger * 1.2 * order++,
      duration: AkylMotion.slow,
      offset: 16,
      child: child,
    );

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: c.background.withValues(alpha: 0.35),
          flexibleSpace: const Glass(radius: 0, child: SizedBox.expand()),
          title: const Text('Голос и обращение'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                enter(_Hero(voice: voice)),
                const SizedBox(height: 24),

                enter(const SettingsSection('Обращение')),
                enter(
                  SettingsCard(
                    children: [
                      SettingsRow(
                        icon: LucideIcons.ear,
                        title: 'Откликаться на обращение',
                        subtitle: !wake
                            ? 'Нужна модель распознавания на телефоне'
                            : s.wakeEnabled
                            ? 'Слушаю ${WakePhrases.title(s.wakePhrase)} на телефоне'
                            : 'Выключено · только кнопка микрофона',
                        live: voice.wakeListening,
                        onTap: wake
                            ? () => _update(
                                (s) => s.copyWith(wakeEnabled: !s.wakeEnabled),
                              )
                            : null,
                        trailing: AkylSwitch(
                          semanticLabel: 'Откликаться на обращение',
                          value: s.wakeEnabled,
                          onChanged: wake
                              ? (v) =>
                                    _update((s) => s.copyWith(wakeEnabled: v))
                              : null,
                        ),
                      ),
                      SettingsRow(
                        icon: voice.voiceTrained
                            ? LucideIcons.badgeCheck
                            : LucideIcons.fingerprint,
                        title: 'Мой голос для «Макс»',
                        subtitle: voice.voiceTrained
                            ? 'Обучено · одиночное «Макс» узнаётся по голосу'
                            : 'Три записи — и «Макс» с паузой срабатывает надёжнее',
                        onTap: wake && s.wakePhrase != WakePhrases.alym
                            ? () => showVoiceTraining(context, voice)
                            : null,
                        trailing: voice.voiceTrained
                            ? IconButton(
                                tooltip: 'Сбросить обучение',
                                icon: Icon(
                                  LucideIcons.rotateCcw,
                                  size: 18,
                                  color: c.textMuted,
                                ),
                                onPressed: voice.clearVoice,
                              )
                            : _chevron(c),
                      ),
                      SettingsRow(
                        icon: LucideIcons.audioLines,
                        title: 'Фраза',
                        subtitle: WakePhrases.title(s.wakePhrase),
                        onTap: _pickPhrase,
                        trailing: _chevron(c),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                enter(
                  _SliderCard(
                    title: 'Чувствительность',
                    hint: switch (s.sensitivity) {
                      WakeSensitivity.low =>
                        'Только точное «Макс» в начале фразы. Меньше ложных срабатываний.',
                      WakeSensitivity.medium =>
                        'Похожие формы и «привет, Макс». Хороший баланс.',
                      WakeSensitivity.high =>
                        'Слышит тихую речь и неточное имя. Возможны ложные срабатывания.',
                    },
                    child: SegmentedSlider<WakeSensitivity>(
                      semanticLabel: 'Чувствительность обращения',
                      value: s.sensitivity,
                      stops: const [
                        SliderStop(WakeSensitivity.low, 'Низкая'),
                        SliderStop(WakeSensitivity.medium, 'Средняя'),
                        SliderStop(WakeSensitivity.high, 'Высокая'),
                      ],
                      onChanged: (v) =>
                          _update((s) => s.copyWith(sensitivity: v)),
                    ),
                  ),
                ),
                const SizedBox(height: 26),

                enter(const SettingsSection('Работа в фоне')),
                enter(
                  SettingsCard(
                    children: [
                      SettingsRow(
                        icon: LucideIcons.radio,
                        title: 'Слушать, когда приложение закрыто',
                        subtitle: !s.wakeEnabled
                            ? 'Сначала включите обращение'
                            : !s.background
                            ? 'Выключено · слушаю, пока экран открыт'
                            : _status.serviceRunning
                            ? 'Работает · и на заблокированном экране'
                            : 'Включено · жду запуска службы',
                        live: s.background && _status.serviceRunning,
                        onTap: s.wakeEnabled
                            ? () => _update(
                                (s) => s.copyWith(background: !s.background),
                              )
                            : null,
                        trailing: AkylSwitch(
                          semanticLabel: 'Слушать, когда приложение закрыто',
                          value: s.background,
                          onChanged: s.wakeEnabled
                              ? (v) => _update((s) => s.copyWith(background: v))
                              : null,
                        ),
                      ),
                      SettingsRow(
                        icon: _status.assistantSelected
                            ? LucideIcons.circleCheck
                            : LucideIcons.circleAlert,
                        title: 'Помощник Android',
                        subtitle: _status.assistantSelected
                            ? 'Alym AI выбран · запуск после перезагрузки'
                            : 'Выберите Alym AI — тогда «Макс» переживёт перезагрузку',
                        onTap: voice.selectAssistant,
                        trailing: _chevron(c),
                      ),
                      SettingsRow(
                        icon: _status.ignoringBatteryOptimizations
                            ? LucideIcons.batteryFull
                            : LucideIcons.batteryWarning,
                        title: 'Оптимизация батареи',
                        subtitle: _status.ignoringBatteryOptimizations
                            ? 'Не ограничивает Alym AI'
                            : 'Может усыплять службу · нажмите, чтобы исключить',
                        onTap: voice.openBatterySettings,
                        trailing: _chevron(c),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),

                enter(const SettingsSection('Разговор')),
                enter(
                  _SliderCard(
                    title: 'Продолжение без «Макс»',
                    hint: s.conversationSeconds == 0
                        ? 'После каждого ответа нужно снова сказать обращение.'
                        : 'После ответа ${s.conversationSeconds} с слушаю продолжение: «А завтра?», «Позвони ему».',
                    child: SegmentedSlider<int>(
                      semanticLabel: 'Время ожидания продолжения разговора',
                      value: s.conversationSeconds,
                      stops: const [
                        SliderStop(0, 'Выкл', semantic: 'выключено'),
                        SliderStop(5, '5 с', semantic: '5 секунд'),
                        SliderStop(10, '10 с', semantic: '10 секунд'),
                        SliderStop(15, '15 с', semantic: '15 секунд'),
                        SliderStop(30, '30 с', semantic: '30 секунд'),
                      ],
                      onChanged: (v) =>
                          _update((s) => s.copyWith(conversationSeconds: v)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                enter(
                  SettingsCard(
                    children: [
                      SettingsRow(
                        icon: LucideIcons.volume2,
                        title: 'Отвечать голосом',
                        subtitle: s.autoSpeak
                            ? 'Ответ звучит вслух'
                            : 'Ответ только текстом',
                        onTap: () =>
                            _update((s) => s.copyWith(autoSpeak: !s.autoSpeak)),
                        trailing: AkylSwitch(
                          semanticLabel: 'Отвечать голосом',
                          value: s.autoSpeak,
                          onChanged: (v) =>
                              _update((s) => s.copyWith(autoSpeak: v)),
                        ),
                      ),
                      SettingsRow(
                        icon: LucideIcons.hand,
                        title: 'Можно перебить',
                        subtitle: s.interrupt
                            ? (s.echoCancellation == AudioProcessing.on
                                  ? 'Скажите что угодно — ответ остановится'
                                  : '«Макс, стоп» останавливает ответ')
                            : 'Ответ всегда договаривается',
                        onTap: () =>
                            _update((s) => s.copyWith(interrupt: !s.interrupt)),
                        trailing: AkylSwitch(
                          semanticLabel: 'Можно перебить',
                          value: s.interrupt,
                          onChanged: (v) =>
                              _update((s) => s.copyWith(interrupt: v)),
                        ),
                      ),
                      SettingsRow(
                        icon: LucideIcons.bellRing,
                        title: 'Когда услышал имя',
                        subtitle: switch (s.cue) {
                          ActivationCue.tone => 'Мягкий сигнал',
                          ActivationCue.voice => 'Говорю «Слушаю»',
                          ActivationCue.silent => 'Без звука',
                        },
                        onTap: _pickCue,
                        trailing: _chevron(c),
                      ),
                      SettingsRow(
                        icon: LucideIcons.userRoundCog,
                        title: 'Голос ответа',
                        subtitle: s.voiceName == null
                            ? 'Лучший офлайн-голос'
                            : _voiceTitle(s.voiceName!),
                        onTap: _voices.isEmpty ? null : _pickVoice,
                        trailing: _chevron(c),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),

                enter(const SettingsSection('Звук')),
                enter(
                  SettingsCard(
                    children: [
                      SettingsRow(
                        icon: LucideIcons.waves,
                        title: 'Шумоподавление',
                        subtitle: _processing(s.noiseSuppression),
                        onTap: () => _pickProcessing(noise: true),
                        trailing: _chevron(c),
                      ),
                      SettingsRow(
                        icon: LucideIcons.speaker,
                        title: 'Подавление эха',
                        subtitle:
                            s.echoCancellation == AudioProcessing.on &&
                                !_status.echoCancellerAvailable
                            ? 'Включено, но телефон его не поддерживает'
                            : _processing(s.echoCancellation),
                        onTap: () => _pickProcessing(noise: false),
                        trailing: _chevron(c),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),

                enter(const SettingsSection('Приватность')),
                enter(
                  SettingsNotice(
                    icon: LucideIcons.shieldCheck,
                    color: c.accent,
                    text: voice.wakeIsLocal
                        ? 'Обращение и команды распознаются на телефоне моделью '
                              'T-one. Звук никуда не отправляется: у приложения нет '
                              'доступа в интернет.'
                        : 'Своя модель не загрузилась — голос распознаёт движок '
                              'Android в режиме «только на устройстве».',
                  ),
                ),
                const SizedBox(height: 12),
                enter(
                  SettingsCard(
                    children: [
                      SettingsRow(
                        icon: LucideIcons.lockKeyhole,
                        title: 'Личное на заблокированном экране',
                        subtitle: s.personalOnLockScreen
                            ? 'Читаю SMS и звонки без разблокировки'
                            : 'SMS, звонки и заметки — только после разблокировки',
                        onTap: () => _update(
                          (s) => s.copyWith(
                            personalOnLockScreen: !s.personalOnLockScreen,
                          ),
                        ),
                        trailing: AkylSwitch(
                          semanticLabel: 'Личное на заблокированном экране',
                          value: s.personalOnLockScreen,
                          onChanged: (v) => _update(
                            (s) => s.copyWith(personalOnLockScreen: v),
                          ),
                        ),
                      ),
                      SettingsRow(
                        icon: LucideIcons.activity,
                        title: 'Панель отладки голоса',
                        subtitle: 'Состояние, задержки, журнал событий',
                        onTap: () => Navigator.of(context).push(
                          SoftPageRoute<void>(
                            builder: (_) => VoiceDebugScreen(voice: voice),
                          ),
                        ),
                        trailing: _chevron(c),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                enter(
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Надёжнее всего звучит имя сразу с командой: «Макс, который час?» '
                      'или «Привет, Макс». В фоне Android показывает уведомление, пока '
                      'микрофон слушает; «Выключить» в нём останавливает прослушивание.',
                      style: text.labelMedium?.copyWith(
                        color: c.textMuted,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chevron(AkylColors c) =>
      Icon(LucideIcons.chevronRight, size: 16, color: c.textMuted);

  static String _processing(AudioProcessing p) => switch (p) {
    AudioProcessing.auto => 'Авто · без лишней обработки',
    AudioProcessing.on => 'Включено',
    AudioProcessing.off => 'Выключено',
  };

  String _voiceTitle(String name) {
    final i = _voices.indexWhere((v) => v.name == name);
    return i < 0 ? name : 'Голос ${String.fromCharCode(0x41 + i)}';
  }

  Future<void> _pickPhrase() async {
    final picked = await showOptionSheet<String>(
      context,
      title: 'Фраза обращения',
      subtitle: 'Все варианты распознаются на телефоне.',
      selected: voice.settings.wakePhrase,
      items: const [
        OptionItem(
          value: WakePhrases.max,
          title: '«Макс»',
          description: 'Коротко и быстро. Можно «Макс, …» или «Привет, Макс».',
          icon: LucideIcons.sparkles,
          badge: 'рекомендую',
        ),
        OptionItem(
          value: WakePhrases.heyMax,
          title: '«Эй, Макс»',
          description: 'Реже срабатывает случайно, если дома есть Максим.',
          icon: LucideIcons.messageCircle,
        ),
        OptionItem(
          value: WakePhrases.alym,
          title: '«Алым»',
          description:
              'Имя помощника. Распознаётся хуже «Макс» — проверьте у себя.',
          icon: LucideIcons.bot,
          badge: 'эксперимент',
        ),
      ],
    );
    if (picked != null) await _update((s) => s.copyWith(wakePhrase: picked));
  }

  Future<void> _pickCue() async {
    final picked = await showOptionSheet<ActivationCue>(
      context,
      title: 'Когда услышал имя',
      subtitle: 'Если имя прозвучало без команды — как дать знать, что слушаю.',
      selected: voice.settings.cue,
      items: const [
        OptionItem(
          value: ActivationCue.tone,
          title: 'Мягкий сигнал',
          description: 'Две тихие ноты — не мешает и не задерживает.',
          icon: LucideIcons.music2,
          badge: 'быстро',
        ),
        OptionItem(
          value: ActivationCue.voice,
          title: '«Слушаю»',
          description: 'Помощник отвечает голосом, затем слушает команду.',
          icon: LucideIcons.messageSquareText,
        ),
        OptionItem(
          value: ActivationCue.silent,
          title: 'Без звука',
          description: 'Только анимация на экране.',
          icon: LucideIcons.volumeOff,
        ),
      ],
    );
    if (picked != null) await _update((s) => s.copyWith(cue: picked));
  }

  Future<void> _pickProcessing({required bool noise}) async {
    final current = noise
        ? voice.settings.noiseSuppression
        : voice.settings.echoCancellation;
    final picked = await showOptionSheet<AudioProcessing>(
      context,
      title: noise ? 'Шумоподавление' : 'Подавление эха',
      subtitle: noise
          ? 'Обработка Android поверх микрофона. Распознаванию обычно лучше без неё.'
          : 'Убирает голос помощника из микрофона — тогда перебивать можно просто речью.',
      selected: current,
      items: [
        const OptionItem(
          value: AudioProcessing.auto,
          title: 'Авто',
          description: 'Чистый звук для распознавания, без обработки звонков.',
          icon: LucideIcons.wandSparkles,
          badge: 'рекомендую',
        ),
        OptionItem(
          value: AudioProcessing.on,
          title: 'Включено',
          description: noise
              ? 'Помогает на улице и в машине.'
              : 'Режим связи Android: голос помощника вычитается.',
          icon: LucideIcons.circleCheck,
          available: noise || _status.echoCancellerAvailable,
          badge: !noise && !_status.echoCancellerAvailable
              ? 'нет на телефоне'
              : null,
        ),
        const OptionItem(
          value: AudioProcessing.off,
          title: 'Выключено',
          description: 'Звук микрофона как есть.',
          icon: LucideIcons.circleOff,
        ),
      ],
    );
    if (picked == null) return;
    await _update(
      (s) => noise
          ? s.copyWith(noiseSuppression: picked)
          : s.copyWith(echoCancellation: picked),
    );
  }

  Future<void> _pickVoice() async {
    final picked = await showOptionSheet<String>(
      context,
      title: 'Голос ответа',
      subtitle: 'Установленные на телефоне русские голоса без интернета.',
      selected: voice.settings.voiceName ?? '',
      items: [
        const OptionItem(
          value: '',
          title: 'Автоматически',
          description: 'Самый качественный из установленных.',
          icon: LucideIcons.wandSparkles,
        ),
        for (var i = 0; i < _voices.length; i++)
          OptionItem(
            value: _voices[i].name,
            title: 'Голос ${String.fromCharCode(0x41 + i)}',
            description: 'Качество ${_voices[i].quality ~/ 100} из 5',
            icon: LucideIcons.userRound,
          ),
      ],
    );
    if (picked == null) return;
    await _update(
      (s) => picked.isEmpty
          ? s.copyWith(clearVoiceName: true)
          : s.copyWith(voiceName: picked),
    );
    unawaited(voice.previewVoice());
  }
}

/// Шапка экрана: живой знак и одна строка о том, что происходит сейчас.
class _Hero extends StatelessWidget {
  const _Hero({required this.voice});
  final VoiceManager voice;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        AlymLogo(
          phase: voice.phase,
          level: voice.level,
          wakeCount: voice.diagnostics.wakeCount,
          size: 72,
        ),
        const SizedBox(height: 4),
        SoftSwitcher(
          child: Text(
            voice.notificationText,
            key: ValueKey(voice.notificationText),
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Dot(on: voice.micOpen),
            const SizedBox(width: 8),
            Text(
              voice.micOpen ? 'Микрофон включён' : 'Микрофон выключен',
              style: text.labelMedium?.copyWith(color: c.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return AnimatedContainer(
      duration: AkylMotion.quick,
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? const Color(0xFF34D399) : c.textMuted,
        boxShadow: [
          if (on)
            BoxShadow(
              color: const Color(0xFF34D399).withValues(alpha: 0.6),
              blurRadius: 8,
            ),
        ],
      ),
    );
  }
}

/// Карточка с заголовком, ступенчатым ползунком и пояснением под ним.
class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.title,
    required this.hint,
    required this.child,
  });

  final String title, hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    return Glass(
      radius: 22,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.border.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.labelLarge),
            const SizedBox(height: 12),
            child,
            const SizedBox(height: 4),
            AnimatedSize(
              duration: AkylMotion.base,
              curve: AkylMotion.move,
              alignment: Alignment.topCenter,
              child: SoftSwitcher(
                alignment: Alignment.topLeft,
                child: Text(
                  hint,
                  key: ValueKey(hint),
                  style: text.labelMedium?.copyWith(
                    color: c.textMuted,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
