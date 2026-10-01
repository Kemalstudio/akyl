import 'package:flutter/material.dart';

import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import 'glass_background.dart';

/// Общие детали экранов настроек: раздел, стеклянная карточка, строка со
/// значком, заметка и нижний лист. Один набор — один ритм отступов.

class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.child, this.height});
  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    const radius = BorderRadius.vertical(top: Radius.circular(28));
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(
                c.surface,
                const Color(0xFF7C3AED),
                0.14,
              )!.withValues(alpha: 0.86),
              c.surface.withValues(alpha: 0.9),
            ],
          ),
          border: Border(
            top: BorderSide(color: c.accent.withValues(alpha: 0.25)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              if (height == null) child else Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6, bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: context.akyl.accent,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Стеклянная карточка раздела; строки разделены тонкой линией.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Glass(
      radius: 22,
      child: Material(
        color: c.surface.withValues(alpha: 0.78),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: c.border.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 66,
                  color: c.border.withValues(alpha: 0.5),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.live = false,
  });

  final IconData icon;
  final String title, subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  /// Микрофон открыт прямо сейчас — значок мягко пульсирует.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        child: Row(
          children: [
            SettingsBadge(icon: icon, live: live),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.labelLarge),
                  const SizedBox(height: 3),
                  // Подпись меняется вместе с состоянием — перетекает, а не
                  // перескакивает.
                  AnimatedSwitcher(
                    duration: AkylMotion.base,
                    switchInCurve: AkylMotion.enter,
                    switchOutCurve: AkylMotion.exit,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.35),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      subtitle,
                      key: ValueKey(subtitle),
                      style: text.labelMedium?.copyWith(
                        color: live ? c.accent : c.textMuted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// Значок строки в цветной подложке. Пока идёт прослушивание, вокруг него
/// медленно расходится кольцо.
class SettingsBadge extends StatefulWidget {
  const SettingsBadge({super.key, required this.icon, required this.live});
  final IconData icon;
  final bool live;

  @override
  State<SettingsBadge> createState() => _SettingsBadgeState();
}

class _SettingsBadgeState extends State<SettingsBadge>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SettingsBadge old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    // В тестах бесконечная анимация не нужна — как и у фона.
    if (widget.live && GlassBackground.animate) {
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
    return SizedBox(
      width: 38,
      height: 38,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              if (widget.live)
                BoxShadow(
                  color: c.accent.withValues(alpha: 0.5 * (1 - _pulse.value)),
                  spreadRadius: 7 * _pulse.value,
                ),
            ],
          ),
          child: child,
        ),
        child: AnimatedContainer(
          duration: AkylMotion.base,
          curve: AkylMotion.move,
          decoration: BoxDecoration(
            color: c.accent.withValues(alpha: widget.live ? 0.28 : 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SoftSwitcher(
            child: Icon(
              widget.icon,
              key: ValueKey(widget.icon),
              size: 18,
              color: c.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsNotice extends StatelessWidget {
  const SettingsNotice({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Glass(
      radius: 18,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: c.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
