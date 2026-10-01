import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/akyl_theme.dart';

/// Переключатель в стиле приложения: фиолетовая капсула с градиентом,
/// ручка переезжает с лёгким пружинящим докатом, внутри ручки — значок.
class AkylSwitch extends StatelessWidget {
  const AkylSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;

  /// null — переключатель неактивен и приглушён.
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  static const _width = 54.0;
  static const _height = 32.0;
  static const _knob = 26.0;
  static const _duration = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              }
            : null,
        child: AnimatedOpacity(
          duration: _duration,
          opacity: enabled ? 1 : 0.45,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: value ? 1 : 0),
            duration: _duration,
            curve: Curves.easeInOutCubic,
            builder: (context, t, _) => Container(
              width: _width,
              height: _height,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_height),
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(c.surfaceRaised, const Color(0xFF7C3AED), t)!,
                    Color.lerp(c.surfaceRaised, const Color(0xFF5B4BE6), t)!,
                  ],
                ),
                border: Border.all(
                  color: Color.lerp(c.borderStrong, Colors.transparent, t)!,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.45 * t),
                    blurRadius: 14 * t,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: AnimatedAlign(
                duration: _duration,
                curve: Curves.easeOutBack,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: _knob - 2,
                  height: _knob - 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(c.textMuted, Colors.white, t),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: _duration,
                    transitionBuilder: (child, animation) => RotationTransition(
                      turns: Tween(begin: 0.75, end: 1.0).animate(animation),
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: Icon(
                      value ? LucideIcons.check : LucideIcons.x,
                      key: ValueKey(value),
                      size: 13,
                      color: value ? const Color(0xFF7C3AED) : c.surface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
