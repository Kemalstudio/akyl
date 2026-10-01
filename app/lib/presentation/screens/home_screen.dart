import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/dialog/dialog_state.dart';
import '../assistant_controller.dart';
import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import '../widgets/akyl_mark.dart';
import '../widgets/alym_logo.dart';
import '../widgets/composer.dart';
import '../widgets/cosmic.dart';
import '../widgets/glass_background.dart';
import '../widgets/history_drawer.dart';
import '../widgets/message_tile.dart';
import '../widgets/status_strip.dart';
import 'assistant_settings.dart';
import 'skills_screen.dart';
import 'voice_settings_screen.dart';

/// Главный экран в духе ChatGPT (ТЗ, FR-10).
///
/// Пока разговор пуст, приветствие и поле ввода стоят в центре. С первой
/// репликой поле плавно съезжает вниз, а над ним появляется история. Это
/// один и тот же виджет, а не два разных экрана, поэтому он не прыгает,
/// а переезжает.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AssistantController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _dockKey = GlobalKey();
  final _scaffold = GlobalKey<ScaffoldState>();

  /// Высота нижнего блока с полем ввода: на столько же список отступает
  /// снизу, чтобы последняя реплика не пряталась под полем.
  double _dockHeight = 140;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          end,
          duration: AkylMotion.base,
          curve: AkylMotion.move,
        );
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  /// Замеряет нижний блок после кадра: его высота меняется с кнопкой
  /// «Отмена», строкой состояния и многострочным текстом.
  void _measureDock() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _dockKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final height = box.size.height;
      if ((height - _dockHeight).abs() > 1 && mounted) {
        setState(() => _dockHeight = height);
      }
    });
  }

  Future<void> _send(String text) async => widget.controller.submit(text);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final history = controller.history;
    final empty = history.isEmpty;
    final awaiting = controller.state.isAwaiting;
    final idle = !controller.busy && !controller.listening;
    final voice = controller.voice;
    // Клавиатура открыта: приветствие и нижняя панель уходят, поле ввода
    // стоит прямо над клавиатурой. Высоту даёт сам Scaffold (adjustResize),
    // без жёстких отступов.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final intro = empty && !keyboard;
    _measureDock();

    void openSettings() => Navigator.of(context).push(
      SoftPageRoute<void>(
        builder: (_) => AssistantSettings(controller: controller),
      ),
    );
    void openSkills() => Navigator.of(
      context,
    ).push(SoftPageRoute<void>(builder: (_) => SkillsScreen(onPick: _send)));

    return GlassBackground(
      level: controller.soundLevel,
      child: Scaffold(
        key: _scaffold,
        backgroundColor: Colors.transparent,
        drawer: HistoryDrawer(controller: controller),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  _TopBar(
                    voice: voice,
                    onMenu: () => _scaffold.currentState?.openDrawer(),
                    onSettings: idle ? openSettings : null,
                    onStatus: () => Navigator.of(context).push(
                      SoftPageRoute<void>(
                        builder: (_) => VoiceSettingsScreen(voice: voice),
                      ),
                    ),
                  ),
                  // Полоса не выталкивает разговор рывком: высота
                  // набирается плавно.
                  AnimatedSize(
                    duration: AkylMotion.base,
                    curve: AkylMotion.move,
                    alignment: Alignment.topCenter,
                    child: controller.warning == null
                        ? const SizedBox(width: double.infinity, height: 0)
                        : _WarningBar(
                            text: controller.warning!,
                            onDismiss: controller.dismissWarning,
                          ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: AnimatedOpacity(
                            duration: AkylMotion.slow,
                            opacity: empty ? 0 : 1,
                            child: ListView.builder(
                              controller: _scroll,
                              padding: EdgeInsets.fromLTRB(
                                AkylShape.gutter,
                                8,
                                AkylShape.gutter,
                                _dockHeight + 12,
                              ),
                              itemCount: history.length,
                              itemBuilder: (_, i) {
                                final last = i == history.length - 1;
                                final asking =
                                    last &&
                                    controller.state ==
                                        DialogState.awaitingConfirmation;
                                return MessageTile(
                                  message: history[i],
                                  showActions: last,
                                  onSpeak: controller.speakAgain,
                                  onTyping: last
                                      ? () => _scrollToBottom(animate: false)
                                      : null,
                                  onConfirm: asking ? () => _send('да') : null,
                                  onReject: asking ? controller.cancel : null,
                                );
                              },
                            ),
                          ),
                        ),
                        AnimatedAlign(
                          duration: AkylMotion.slow,
                          curve: Curves.easeInOutCubic,
                          alignment: intro
                              ? const Alignment(0, -0.55)
                              : Alignment.bottomCenter,
                          // Прокрутка всегда в дереве (иначе смена клавиатуры
                          // пересоздала бы поле ввода и сняла фокус), но
                          // включается, только если приветствие не влезает.
                          child: SingleChildScrollView(
                            physics: intro
                                ? const ClampingScrollPhysics()
                                : const NeverScrollableScrollPhysics(),
                            child: _Dock(
                              key: _dockKey,
                              docked: !intro,
                              header: _Greeting(voice: voice),
                              footer: controller.simpleMode
                                  ? _BigActions(
                                      relatives: [
                                        for (final entry
                                            in controller.relationships.entries)
                                          (
                                            role: entry.key,
                                            name:
                                                controller.contacts
                                                    .where(
                                                      (c) =>
                                                          c.id == entry.value,
                                                    )
                                                    .firstOrNull
                                                    ?.displayName ??
                                                entry.key,
                                          ),
                                      ],
                                      onPick: _send,
                                    )
                                  : _Suggestions(
                                      onPick: _send,
                                      onMore: openSkills,
                                    ),
                              status: StatusStrip(
                                state: controller.state,
                                busy: controller.busy,
                              ),
                              composer: Composer(
                                controller: _input,
                                onSubmit: _send,
                                onListen: controller.listen,
                                onStopListening: controller.stopListening,
                                busy: controller.busy,
                                listening: controller.listening,
                                awaiting: awaiting,
                                voiceAvailable: controller.voiceAvailable,
                                voicePhase: voice.phase,
                                wakePhrase: voice.settings.wakePhrase,
                                onStopSpeaking: voice.stopSpeaking,
                                level: controller.soundLevel,
                                partialText: controller.partialText,
                                // На «отправить?» отвечают кнопками в самой
                                // реплике; «Отмена» под полем — только для выбора.
                                onCancel:
                                    controller.state ==
                                        DialogState.awaitingChoice
                                    ? controller.cancel
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Шапка: по одной круглой кнопке с каждой стороны, в центре — знак и
/// живая точка состояния голоса. Симметрия важнее лишней кнопки: новый
/// разговор начинается из панели истории.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.voice,
    required this.onMenu,
    required this.onSettings,
    required this.onStatus,
  });

  final VoiceManager voice;
  final VoidCallback onMenu;
  final VoidCallback? onSettings;
  final VoidCallback onStatus;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: FadeSlideIn(
        offset: -8,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              GlassCircleButton(
                icon: LucideIcons.menu,
                tooltip: 'История разговоров',
                onPressed: onMenu,
              ),
              Expanded(
                child: Center(
                  child: Semantics(
                    button: true,
                    label: 'Alym AI. ${voice.notificationText}',
                    child: GestureDetector(
                      onTap: onStatus,
                      child: GlassPanel(
                        radius: 23,
                        padding: const EdgeInsets.fromLTRB(14, 11, 16, 11),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: AkylGradients.brand.createShader,
                              child: const AkylMark(
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 9),
                            ExcludeSemantics(
                              child: Text(
                                'Alym ',
                                style: text?.copyWith(color: c.textPrimary),
                              ),
                            ),
                            ExcludeSemantics(
                              child: GradientText('AI', style: text),
                            ),
                            // Выключенный голос — без точки: серая точка
                            // выглядела бы соринкой, а не состоянием.
                            if (voice.phase != VoicePhase.disabled) ...[
                              const SizedBox(width: 10),
                              _StatusDot(phase: voice.phase),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              GlassCircleButton(
                icon: LucideIcons.slidersHorizontal,
                tooltip: 'Настройки',
                onPressed: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Точка состояния микрофона в шапке: видно издалека, слушает ли помощник.
/// Зелёная — ждёт обращения, фиолетовая — разговор, красная — ошибка,
/// серая — микрофон выключен.
class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.phase});
  final VoicePhase phase;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_StatusDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.phase.micActive && ambientMotion(context)) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final color = switch (widget.phase) {
      VoicePhase.listeningForWake => const Color(0xFF34D399),
      VoicePhase.error => c.danger,
      VoicePhase.recovering || VoicePhase.paused => const Color(0xFFFBBF24),
      final p when p.inSession => const Color(0xFFA78BFA),
      _ => c.textMuted,
    };
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            if (widget.phase.micActive)
              BoxShadow(
                color: color.withValues(alpha: 0.6 * (1 - _pulse.value)),
                spreadRadius: 5 * _pulse.value,
              ),
          ],
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({
    super.key,
    required this.docked,
    required this.header,
    required this.footer,
    required this.status,
    required this.composer,
  });

  final bool docked;
  final Widget header;
  final Widget footer;
  final Widget status;
  final Widget composer;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return AnimatedContainer(
      duration: AkylMotion.slow,
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.background.withValues(alpha: 0),
            c.background.withValues(alpha: docked ? 0.55 : 0),
            c.background.withValues(alpha: docked ? 0.75 : 0),
          ],
          stops: const [0, 0.3, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AkylShape.gutter,
            18,
            AkylShape.gutter,
            12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Collapsible(visible: !docked, child: header),
              status,
              composer,
              _Collapsible(visible: !docked, child: footer),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плавно сворачивается и гаснет — приветствие и подсказки уходят,
/// когда начинается разговор.
class _Collapsible extends StatelessWidget {
  const _Collapsible({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AkylMotion.slow,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.center,
      child: AnimatedOpacity(
        duration: AkylMotion.base,
        opacity: visible ? 1 : 0,
        child: visible
            ? child
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.voice});

  final VoiceManager voice;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    final title = text.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      fontSize: 32,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          FadeSlideIn(
            duration: AkylMotion.slow,
            offset: 20,
            child: AlymLogo(
              phase: voice.phase,
              level: voice.level,
              wakeCount: voice.diagnostics.wakeCount,
              size: 62,
            ),
          ),
          const SizedBox(height: 8),
          FadeSlideIn(
            delay: AkylMotion.stagger,
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                Text('Чем могу ', style: title),
                GradientText('помочь?', style: title, shimmer: true),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            delay: AkylMotion.stagger * 2,
            child: Text(
              voice.settings.wakeEnabled && voice.wakeAvailable
                  ? 'Скажите ${WakePhrases.title(voice.settings.wakePhrase)} — '
                        'я позвоню,\nнапишу или напомню.'
                  : 'Нажмите на микрофон или напишите —\nя позвоню, напишу или напомню.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: c.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          // Одно касание вместо поиска в настройках: обращение и фон сразу.
          if (!voice.settings.wakeEnabled && voice.wakeAvailable)
            FadeSlideIn(
              delay: AkylMotion.stagger * 3,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _EnableWakeButton(voice: voice),
              ),
            ),
        ],
      ),
    );
  }
}

/// «Включить «Макс»»: обращение и работу в фоне — одним касанием.
class _EnableWakeButton extends StatelessWidget {
  const _EnableWakeButton({required this.voice});
  final VoiceManager voice;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Semantics(
      button: true,
      label: 'Включить обращение «Макс» без открытия приложения',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          voice.updateSettings(
            voice.settings.copyWith(wakeEnabled: true, background: true),
          );
        },
        child: GlassPanel(
          radius: 24,
          highlighted: true,
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AkylGradients.button,
                ),
                child: const Icon(
                  LucideIcons.ear,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Включить «Макс» — без открытия приложения',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Подсказки на пустом экране: ровная сетка 2×2 карточек с одинаковой
/// высотой — не «лесенка» пилюль разной ширины. Касание сразу выполняет
/// команду; «Все навыки» открывает полный список.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onPick, required this.onMore});

  final ValueChanged<String> onPick;
  final VoidCallback onMore;

  /// Значок, заголовок, пояснение и сама команда.
  static const _items = [
    (LucideIcons.phone, 'Позвони маме', 'Звонок сразу', 'Позвони маме'),
    (
      LucideIcons.alarmClock,
      'Будильник на 7:30',
      'В «Часах» Android',
      'Поставь будильник на 7:30',
    ),
    (
      LucideIcons.bellRing,
      'Напомни завтра',
      'В 10 утра — позвонить',
      'Напомни мне завтра в 10 позвонить маме',
    ),
    (
      LucideIcons.calendar,
      'Какое число',
      'Скажу голосом',
      'Какое сегодня число',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          for (var row = 0; row < 2; row++) ...[
            if (row > 0) const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var col = 0; col < 2; col++) ...[
                    if (col > 0) const SizedBox(width: 10),
                    Expanded(
                      child: FadeSlideIn(
                        delay: AkylMotion.stagger * (3 + row * 2 + col),
                        offset: 12,
                        child: _SuggestionCard(
                          icon: _items[row * 2 + col].$1,
                          title: _items[row * 2 + col].$2,
                          hint: _items[row * 2 + col].$3,
                          onTap: () => onPick(_items[row * 2 + col].$4),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: onMore,
            icon: const Icon(LucideIcons.layoutGrid, size: 16),
            label: const Text('Все навыки'),
            style: TextButton.styleFrom(
              foregroundColor: c.textSecondary,
              minimumSize: const Size(0, 44),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatefulWidget {
  const _SuggestionCard({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String title, hint;
  final VoidCallback onTap;

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${widget.title}. ${widget.hint}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: AkylMotion.instant,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: AkylMotion.instant,
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: _down ? 0.9 : 0.62),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.border.withValues(alpha: 0.7)),
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, size: 17, color: c.accent),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: c.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Простой режим: крупные плитки вместо подсказок. Одно касание — звонок
/// близкому; красная SOS — звонок и SMS всем близким с местом.
class _BigActions extends StatelessWidget {
  const _BigActions({required this.relatives, required this.onPick});

  final List<({String role, String name})> relatives;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final tiles = <Widget>[
      for (final r in relatives.take(4))
        _BigTile(
          icon: LucideIcons.phone,
          title: r.name,
          subtitle: 'Позвонить',
          color: c.accent,
          onTap: () => onPick('позвони ${_dative(r.role)}'),
        ),
      _BigTile(
        icon: LucideIcons.clock,
        title: 'Который час',
        subtitle: 'Скажу вслух',
        color: c.textSecondary,
        onTap: () => onPick('который час'),
      ),
      _BigTile(
        icon: LucideIcons.phoneIncoming,
        title: 'Кто звонил',
        subtitle: 'Последние звонки',
        color: c.textSecondary,
        onTap: () => onPick('кто звонил'),
      ),
    ];
    // SOS — отдельно и во всю ширину: самая важная кнопка не должна
    // оказаться «лишней» плиткой в сетке.
    final sos = _BigTile(
      icon: LucideIcons.siren,
      title: 'SOS',
      subtitle: 'Звонок и SMS близким с местом',
      color: c.danger,
      onTap: () => onPick('помогите'),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: [
              for (var i = 0; i < tiles.length; i++)
                FadeSlideIn(
                  delay: AkylMotion.stagger * (3 + i),
                  offset: 8,
                  child: tiles[i],
                ),
            ],
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            delay: AkylMotion.stagger * (3 + tiles.length),
            offset: 8,
            child: SizedBox(height: 96, width: double.infinity, child: sos),
          ),
        ],
      ),
    );
  }

  /// «мама» -> «маме»: так команда звучит естественно в чате.
  static String _dative(String role) => switch (role) {
    'мама' => 'маме',
    'папа' => 'папе',
    'бабушка' => 'бабушке',
    'дедушка' => 'дедушке',
    'сестра' => 'сестре',
    'жена' => 'жене',
    'дочь' => 'дочке',
    'тётя' => 'тёте',
    'дядя' => 'дяде',
    _ => '${role}у',
  };
}

class _BigTile extends StatelessWidget {
  const _BigTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 26, color: color),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: text.labelMedium?.copyWith(color: c.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Контакты недоступны — ассистент запустится, но найти никого не сможет.
class _WarningBar extends StatelessWidget {
  const _WarningBar({required this.text, required this.onDismiss});

  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AkylShape.gutter,
        4,
        AkylShape.gutter,
        4,
      ),
      child: Container(
        key: const ValueKey('warning'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.danger.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.triangleAlert, size: 17, color: c.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: c.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(LucideIcons.x, size: 16, color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
