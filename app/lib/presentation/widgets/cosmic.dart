import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/akyl_theme.dart';
import 'akyl_mark.dart';
import 'glass_background.dart';

/// Фирменные градиенты: фиолетовый в индиго, как свечение на фоне.
abstract final class AkylGradients {
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB79CFF), Color(0xFF8B5CF6), Color(0xFF5B5BF0)],
  );

  static const button = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA78BFA), Color(0xFF7C3AED), Color(0xFF4F46E5)],
  );
}

/// Бесконечные «фоновые» анимации: выключаются в тестах и при системной
/// настройке «убрать анимацию».
bool ambientMotion(BuildContext context) =>
    GlassBackground.animate && !MediaQuery.disableAnimationsOf(context);

/// Текст с градиентом. [shimmer] — блик медленно проходит по буквам.
class GradientText extends StatefulWidget {
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient = AkylGradients.brand,
    this.shimmer = false,
  });

  final String text;
  final TextStyle? style;
  final Gradient gradient;
  final bool shimmer;

  @override
  State<GradientText> createState() => _GradientTextState();
}

class _GradientTextState extends State<GradientText>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// Блик проходит раз в несколько секунд, а не крутится без остановки:
  /// между проходами текст не перерисовывается совсем.
  Timer? _every;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _every?.cancel();
    if (widget.shimmer && ambientMotion(context)) {
      _sweep.forward(from: 0);
      _every = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) _sweep.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _every?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          // Между проходами — обычный градиент, как без блика.
          if (!widget.shimmer || !_sweep.isAnimating) {
            return widget.gradient.createShader(bounds);
          }
          // Блик — светлая полоса, проезжающая слева направо.
          final x = -1 + 3 * _sweep.value;
          return LinearGradient(
            begin: Alignment(x - 1, 0),
            end: Alignment(x + 1, 0),
            colors: const [
              Color(0xFF8B5CF6),
              Color(0xFFE9DDFF),
              Color(0xFF8B5CF6),
            ],
            stops: const [0.3, 0.5, 0.7],
            tileMode: TileMode.clamp,
          ).createShader(bounds);
        },
        child: child,
      ),
      child: Text(widget.text, style: widget.style),
    );
  }
}

/// Сфера помощника: светящийся шар со знаком, вокруг — наклонённая орбита
/// со спутником. Шар мягко парит, ореол дышит, орбита вращается.
class AssistantOrb extends StatefulWidget {
  const AssistantOrb({super.key, this.size = 110, this.level});

  final double size;

  /// Громкость голоса: пока человек говорит, ореол разгорается.
  final Listenable? level;

  @override
  State<AssistantOrb> createState() => _AssistantOrbState();
}

class _AssistantOrbState extends State<AssistantOrb>
    with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  /// Шар движется плавно и медленно: 30 кадров в секунду хватает с
  /// запасом, а работы вдвое меньше.
  late final _tick = FrameThrottle(_loop, const Duration(milliseconds: 33));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ambientMotion(context)) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _tick.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return RepaintBoundary(
      child: SizedBox(
        width: size * 1.7,
        height: size * 1.35,
        child: AnimatedBuilder(
          animation: Listenable.merge([_tick, widget.level]),
          builder: (context, _) {
            final a = _loop.value * 2 * math.pi;
            final float = math.sin(a * 2) * size * 0.04;
            final breathe = 0.5 + 0.5 * math.sin(a * 3);
            final voice = widget.level is ValueNotifier<double>
                ? (widget.level! as ValueNotifier<double>).value
                : 0.0;
            return Transform.translate(
              offset: Offset(0, float),
              child: CustomPaint(
                painter: _OrbPainter(angle: a, breathe: breathe, voice: voice),
                child: Center(
                  child: AkylMark(size: size * 0.36, color: Colors.white),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.angle,
    required this.breathe,
    required this.voice,
  });

  final double angle, breathe, voice;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.height / 1.35 / 2;

    // Ореол.
    canvas.drawCircle(
      center,
      r * (1.45 + 0.12 * breathe + 0.35 * voice),
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF8B5CF6).withValues(alpha: 0.55 + 0.3 * voice),
            const Color(0xFF8B5CF6).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r * 1.8)),
    );

    // Орбита: наклонённый эллипс. Задняя половина рисуется до шара,
    // передняя — после, чтобы кольцо «обнимало» сферу.
    final orbit = Rect.fromCenter(
      center: center,
      width: r * 3.1,
      height: r * 0.95,
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = const LinearGradient(
        colors: [Color(0x00A78BFA), Color(0xFFC4B5FD), Color(0x00A78BFA)],
      ).createShader(orbit);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.28);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawArc(orbit, math.pi, math.pi, false, ring);
    canvas.restore();

    // Сфера: объём радиальным градиентом, блик сверху слева.
    final sphere = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.45),
          radius: 1.1,
          colors: [Color(0xFFD9CCFF), Color(0xFF8B5CF6), Color(0xFF3B1E8F)],
          stops: [0, 0.45, 1],
        ).createShader(sphere),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    // Передняя половина орбиты и спутник на ней.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.28);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawArc(orbit, 0, math.pi, false, ring);
    final moon = Offset(
      center.dx + orbit.width / 2 * math.cos(angle),
      center.dy + orbit.height / 2 * math.sin(angle),
    );
    // Спутник виден только на передней половине.
    if (math.sin(angle) > -0.1) {
      canvas.drawCircle(
        moon,
        6,
        Paint()..color = const Color(0xFFC4B5FD).withValues(alpha: 0.35),
      );
      canvas.drawCircle(moon, 2.6, Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.angle != angle || old.breathe != breathe || old.voice != voice;
}

/// Стеклянная панель: размытие под собой, полупрозрачная заливка,
/// светящаяся градиентная кромка. [runningLight] — по кромке бежит блик.
class GlassPanel extends StatefulWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
    this.runningLight = false,
    this.glow = false,
    this.highlighted = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool runningLight;

  /// Мягкое фиолетовое свечение вокруг.
  final bool glow;

  /// Ярче кромка: панель в фокусе или слушает.
  final bool highlighted;

  @override
  State<GlassPanel> createState() => _GlassPanelState();
}

class _GlassPanelState extends State<GlassPanel>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(GlassPanel old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.runningLight && ambientMotion(context)) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(widget.radius);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          if (widget.glow || widget.highlighted)
            BoxShadow(
              color: const Color(
                0xFF8B5CF6,
              ).withValues(alpha: widget.highlighted ? 0.45 : 0.25),
              blurRadius: widget.highlighted ? 36 : 28,
              spreadRadius: -6,
            ),
        ],
      ),
      // Кромка с бликом — отдельный слой поверх: на каждом кадре
      // перерисовывается только тонкая линия, а не тень и содержимое.
      child: Stack(
        children: [
          RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(
                      c.surface,
                      Colors.white,
                      dark ? 0.04 : 0.3,
                    )!.withValues(alpha: dark ? 0.78 : 0.82),
                    Color.lerp(
                      c.surface,
                      const Color(0xFF7C3AED),
                      0.14,
                    )!.withValues(alpha: dark ? 0.7 : 0.78),
                  ],
                ),
              ),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _EdgePainter(
                    radius: widget.radius,
                    spin: _spin,
                    running: widget.runningLight,
                    strong: widget.highlighted,
                    dark: dark,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Кромка панели: тонкая светлая линия, ярче сверху слева. Если
/// [running] — по ней бежит яркий блик.
class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.radius,
    required this.spin,
    required this.running,
    required this.strong,
    required this.dark,
  }) : super(repaint: running ? spin : null);

  final double radius;
  final Animation<double> spin;
  final bool running, strong, dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.6),
      Radius.circular(radius),
    );
    final base = dark ? Colors.white : const Color(0xFF7C3AED);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: strong ? 0.5 : 0.28),
            const Color(0xFF8B5CF6).withValues(alpha: strong ? 0.6 : 0.3),
            base.withValues(alpha: 0.08),
          ],
        ).createShader(rect),
    );
    if (!running) return;
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = SweepGradient(
          transform: GradientRotation(spin.value * 2 * math.pi),
          colors: const [
            Color(0x00C4B5FD),
            Color(0x00C4B5FD),
            Color(0xFFE4DAFF),
            Color(0x00C4B5FD),
          ],
          stops: const [0, 0.72, 0.8, 0.88],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.running != running || old.strong != strong || old.dark != dark;
}

/// Круглая стеклянная кнопка шапки, как в макете. Нажатие чуть сжимает её.
class GlassCircleButton extends StatefulWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 46,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  State<GlassCircleButton> createState() => _GlassCircleButtonState();
}

class _GlassCircleButtonState extends State<GlassCircleButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: enabled ? 1 : 0.4,
            child: SizedBox.square(
              dimension: widget.size,
              child: GlassPanel(
                radius: widget.size / 2,
                child: Center(
                  child: Icon(widget.icon, size: 20, color: c.textPrimary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Светящаяся круглая кнопка с градиентом — голос, отправка.
class GlowCircle extends StatelessWidget {
  const GlowCircle({
    super.key,
    required this.child,
    this.size = 48,
    this.glow = 0.5,
  });

  final Widget child;
  final double size;

  /// 0..1 — сила свечения.
  final double glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AkylGradients.button,
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.3 + 0.4 * glow),
            blurRadius: 14 + 18 * glow,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Center(child: child),
    );
  }
}
