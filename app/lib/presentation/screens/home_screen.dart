import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../assistant_controller.dart';
import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import '../widgets/akyl_mark.dart';
import '../widgets/composer.dart';
import '../widgets/cosmic.dart';
import '../widgets/glass_background.dart';
import '../widgets/history_drawer.dart';
import '../widgets/message_tile.dart';
import '../widgets/status_strip.dart';
import 'assistant_settings.dart';
import 'skills_screen.dart';

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
                    onMenu: () => _scaffold.currentState?.openDrawer(),
                    onSettings: idle ? openSettings : null,
                    onNewChat: empty ? null : controller.startNewConversation,
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
                              itemBuilder: (_, i) => MessageTile(
                                message: history[i],
                                onSpeak: controller.speakAgain,
                                onTyping: i == history.length - 1
                                    ? () => _scrollToBottom(animate: false)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        // Цитата и нижняя панель — только на пустом экране:
                        // в разговоре место отдано переписке.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            ignoring: !empty,
                            child: AnimatedSlide(
                              duration: AkylMotion.slow,
                              curve: Curves.easeInOutCubic,
                              offset: empty
                                  ? Offset.zero
                                  : const Offset(0, 1.3),
                              child: AnimatedOpacity(
                                duration: AkylMotion.base,
                                opacity: empty ? 1 : 0,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _Quote(),
                                    _BottomNav(
                                      level: controller.soundLevel,
                                      listening: controller.listening,
                                      onVoice: controller.voiceAvailable
                                          ? (controller.listening
                                                ? controller.stopListening
                                                : controller.listen)
                                          : null,
                                      onSkills: openSkills,
                                      onHistory: () =>
                                          _scaffold.currentState?.openDrawer(),
                                      onProfile: idle ? openSettings : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        AnimatedAlign(
                          duration: AkylMotion.slow,
                          curve: Curves.easeInOutCubic,
                          alignment: empty
                              ? const Alignment(0, -0.55)
                              : Alignment.bottomCenter,
                          child: _Dock(
                            key: _dockKey,
                            docked: !empty,
                            header: _Greeting(level: controller.soundLevel),
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
                                                    (c) => c.id == entry.value,
                                                  )
                                                  .firstOrNull
                                                  ?.displayName ??
                                              entry.key,
                                        ),
                                    ],
                                    onPick: _send,
                                  )
                                : _Suggestions(onPick: _send),
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
                              wakeListening: controller.wakeListening,
                              level: controller.soundLevel,
                              partialText: controller.partialText,
                              onCancel: awaiting ? controller.cancel : null,
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

/// Шапка как в макете: круглые стеклянные кнопки по краям, в центре —
/// стеклянная «пилюля» со знаком и названием.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onMenu,
    required this.onSettings,
    required this.onNewChat,
  });

  final VoidCallback onMenu;
  final VoidCallback? onSettings;
  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: FadeSlideIn(
        offset: -8,
        child: SizedBox(
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  GlassCircleButton(
                    icon: LucideIcons.menu,
                    tooltip: 'История разговоров',
                    onPressed: onMenu,
                  ),
                  const Spacer(),
                  GlassCircleButton(
                    icon: LucideIcons.slidersHorizontal,
                    tooltip: 'Настройки',
                    onPressed: onSettings,
                  ),
                  const SizedBox(width: 10),
                  GlassCircleButton(
                    icon: LucideIcons.squarePen,
                    tooltip: 'Новый разговор',
                    onPressed: onNewChat,
                  ),
                ],
              ),
              GlassPanel(
                radius: 23,
                padding: const EdgeInsets.fromLTRB(14, 11, 18, 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: AkylGradients.brand.createShader,
                      child: const AkylMark(size: 20, color: Colors.white),
                    ),
                    const SizedBox(width: 9),
                    Text('Alym ', style: text?.copyWith(color: c.textPrimary)),
                    GradientText('AI', style: text),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Нижняя панель: разделы по краям, в центре — светящаяся кнопка голоса.
class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.level,
    required this.listening,
    required this.onVoice,
    required this.onSkills,
    required this.onHistory,
    required this.onProfile,
  });

  final ValueNotifier<double> level;
  final bool listening;
  final VoidCallback? onVoice;
  final VoidCallback onSkills;
  final VoidCallback onHistory;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 10 + bottom),
      child: SizedBox(
        height: 84,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            GlassPanel(
              radius: 30,
              child: SizedBox(
                height: 72,
                child: Row(
                  children: [
                    const _NavItem(
                      icon: LucideIcons.house,
                      label: 'Главная',
                      active: true,
                    ),
                    _NavItem(
                      icon: LucideIcons.search,
                      label: 'Навыки',
                      onTap: onSkills,
                    ),
                    const SizedBox(width: 84),
                    _NavItem(
                      icon: LucideIcons.clock,
                      label: 'История',
                      onTap: onHistory,
                    ),
                    _NavItem(
                      icon: LucideIcons.userRound,
                      label: 'Профиль',
                      onTap: onProfile,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              child: RepaintBoundary(
                child: _VoiceOrbButton(
                  level: level,
                  listening: listening,
                  onTap: onVoice,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final color = active ? c.accent : c.textMuted;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: color,
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
    );
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            active
                ? ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: AkylGradients.brand.createShader,
                    child: Icon(icon, size: 22, color: Colors.white),
                  )
                : Icon(icon, size: 22, color: color),
            const SizedBox(height: 5),
            Text(label, style: style),
          ],
        ),
      ),
    );
  }
}

/// Центральная кнопка голоса: светящийся шар со знаком, вокруг —
/// медленно пульсирующее кольцо; во время записи кольцо следует за голосом.
class _VoiceOrbButton extends StatefulWidget {
  const _VoiceOrbButton({
    required this.level,
    required this.listening,
    required this.onTap,
  });

  final ValueNotifier<double> level;
  final bool listening;
  final VoidCallback? onTap;

  @override
  State<_VoiceOrbButton> createState() => _VoiceOrbButtonState();
}

class _VoiceOrbButtonState extends State<_VoiceOrbButton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  bool _down = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ambientMotion(context)) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.listening ? 'Остановить запись' : 'Сказать голосом',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 140),
          // Двигается только тонкое кольцо; шар с тенью неподвижен и не
          // перерисовывается на каждом кадре.
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_pulse, widget.level]),
                    builder: (context, _) {
                      final voice = widget.level.value;
                      final p = _pulse.value;
                      final size = 66 + 18 * p + 16 * voice;
                      return Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(
                              0xFFA78BFA,
                            ).withValues(alpha: (1 - p) * 0.55),
                            width: 1.5,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                RepaintBoundary(
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-0.3, -0.4),
                        colors: [
                          Color(0xFFD9CCFF),
                          Color(0xFF8B5CF6),
                          Color(0xFF3B1E8F),
                        ],
                        stops: [0, 0.5, 1],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF8B5CF6,
                          ).withValues(alpha: widget.listening ? 0.85 : 0.55),
                          blurRadius: widget.listening ? 36 : 26,
                        ),
                      ],
                    ),
                    child: Center(
                      child: widget.listening
                          ? const Icon(
                              LucideIcons.square,
                              size: 18,
                              color: Colors.white,
                            )
                          : const AkylMark(size: 24, color: Colors.white),
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
}

/// Строка внизу пустого экрана, как в макете.
class _Quote extends StatelessWidget {
  const _Quote();

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
      child: FadeSlideIn(
        delay: AkylMotion.stagger * 8,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.sparkles, size: 16, color: c.accent),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '«Хорошие вопросы\nоткрывают новые миры»',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: c.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Блок с полем ввода. В центре над полем — приветствие, под ним —
/// подсказки; внизу — только поле на мягкой подложке, под которую
/// уходит прокручиваемый текст.
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
  const _Greeting({required this.level});

  final ValueNotifier<double> level;

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
            child: AssistantOrb(size: 78, level: level),
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
              'Напишите или скажите «Макс» — я позвоню,\nнапишу или подскажу.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: c.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Подсказки-«пилюли» под полем, как в макете: стекло, значок в
/// градиентном круге, стрелка. Нажатие сразу выполняет команду.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onPick});

  final ValueChanged<String> onPick;

  /// Значок, подпись на пилюле и сама команда.
  static const _items = [
    (LucideIcons.phone, 'Позвони маме', 'Позвони маме'),
    (LucideIcons.alarmClock, 'Будильник на 7:30', 'Поставь будильник на 7:30'),
    (LucideIcons.flashlight, 'Включи фонарик', 'Включи фонарик'),
    (LucideIcons.calendar, 'Какое сегодня число', 'Какое сегодня число'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _items.length; i++)
            FadeSlideIn(
              delay: AkylMotion.stagger * (3 + i),
              offset: 14,
              child: _Pill(
                icon: _items[i].$1,
                label: _items[i].$2,
                onTap: () => onPick(_items[i].$3),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatefulWidget {
  const _Pill({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: GlassPanel(
          radius: 26,
          highlighted: _down,
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AkylGradients.button,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.45),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Icon(widget.icon, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              Icon(LucideIcons.chevronRight, size: 15, color: c.textMuted),
            ],
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
      _BigTile(
        icon: LucideIcons.siren,
        title: 'SOS',
        subtitle: 'Звонок и SMS близким',
        color: c.danger,
        onTap: () => onPick('помогите'),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
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
