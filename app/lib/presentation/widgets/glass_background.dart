import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/akyl_theme.dart';

/// Фон главного экрана: мягкие фиолетовые пятна медленно плывут по кругу,
/// поверх них — матовое стекло.
///
/// Полный круг занимает минуту, пятна двигаются по кривым Лиссажу с целыми
/// частотами, поэтому петля замыкается без рывка.
///
/// Если передан [level], пятна «дышат» в такт голосу: растут и светлеют,
/// пока человек говорит.
class GlassBackground extends StatefulWidget {
  const GlassBackground({
    super.key,
    required this.child,
    this.level,
    this.intensity = 1,
  });

  final Widget child;

  /// Громкость голоса 0..1 или null, если экран не слушает.
  final ValueListenable<double>? level;

  /// Насколько заметны пятна: 1 — ярко, как на экране входа; меньше —
  /// лёгкое свечение за чатом, которое не спорит с текстом.
  final double intensity;

  /// Бесконечная анимация не даёт `pumpAndSettle` дождаться покоя, поэтому
  /// тесты её выключают (см. test/flutter_test_config.dart).
  static bool animate = true;

  @override
  State<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends State<GlassBackground>
    with TickerProviderStateMixin {
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  /// Плавно догоняет громкость: сырые скачки микрофона выглядели бы
  /// дёрганьем, а не дыханием.
  late final _voice = AnimationController(vsync: this);

  /// Фон движется очень медленно (круг — минута), поэтому перерисовывать
  /// его 60 раз в секунду незачем: 20 кадров на глаз неотличимы, а
  /// телефон тратит втрое меньше. Голос — на полной частоте.
  late final _slowTick = FrameThrottle(_loop, const Duration(milliseconds: 50));
  late final Listenable _repaint = Listenable.merge([_slowTick, _voice]);

  @override
  void initState() {
    super.initState();
    widget.level?.addListener(_onLevel);
  }

  @override
  void didUpdateWidget(GlassBackground old) {
    super.didUpdateWidget(old);
    if (old.level == widget.level) return;
    old.level?.removeListener(_onLevel);
    widget.level?.addListener(_onLevel);
  }

  void _onLevel() {
    final target = widget.level?.value ?? 0;
    _voice.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still =
        !GlassBackground.animate || MediaQuery.disableAnimationsOf(context);
    if (still) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    widget.level?.removeListener(_onLevel);
    _slowTick.dispose();
    _voice.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: c.background),
        // Пятна и космос — один слой в своей границе перерисовки: их
        // движение не заставляет перерисовывать экран поверх.
        // Полноэкранного размытия нет: пятна и так мягкие (радиальный
        // градиент), а размытие на каждом кадре было главной причиной
        // подтормаживаний.
        RepaintBoundary(
          child: CustomPaint(
            painter: _BlobPainter(
              _loop,
              _voice,
              repaint: _repaint,
              dark: dark,
              intensity: widget.intensity * 0.8,
            ),
            foregroundPainter: _CosmosPainter(
              _loop,
              _voice,
              repaint: _repaint,
              dark: dark,
              intensity: widget.intensity,
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _Blob {
  const _Blob(
    this.color,
    this.center,
    this.orbit,
    this.fx,
    this.fy,
    this.phase,
    this.radius,
  );

  final Color color;

  /// Центр орбиты и её размах — в долях экрана.
  final Offset center, orbit;

  /// Сколько раз пятно проходит орбиту за минуту по каждой оси.
  final int fx, fy;
  final double phase;

  /// Радиус в долях большей стороны экрана.
  final double radius;
}

const _blobs = [
  _Blob(
    Color(0xFF7C3AED),
    Offset(0.15, 0.18),
    Offset(0.22, 0.12),
    1,
    2,
    0.0,
    0.55,
  ),
  _Blob(
    Color(0xFFA855F7),
    Offset(0.85, 0.35),
    Offset(0.18, 0.20),
    2,
    1,
    1.9,
    0.50,
  ),
  _Blob(
    Color(0xFF4F46E5),
    Offset(0.30, 0.78),
    Offset(0.24, 0.14),
    1,
    1,
    3.4,
    0.55,
  ),
];

class _BlobPainter extends CustomPainter {
  _BlobPainter(
    this.t,
    this.voice, {
    required Listenable repaint,
    required this.dark,
    required this.intensity,
  }) : super(repaint: repaint);

  final Animation<double> t;
  final Animation<double> voice;
  final double intensity;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t.value * 2 * math.pi;
    final side = size.longestSide;
    for (final b in _blobs) {
      final center = Offset(
        (b.center.dx + b.orbit.dx * math.sin(a * b.fx + b.phase)) * size.width,
        (b.center.dy + b.orbit.dy * math.cos(a * b.fy + b.phase)) * size.height,
      );
      // Пятно «дышит»: радиус чуть меняется в такт движению, а пока
      // человек говорит — растёт и светлеет вместе с голосом.
      final v = voice.value;
      final r =
          b.radius * side * (1 + 0.08 * math.sin(a * 2 + b.phase) + 0.3 * v);
      // Приглушённо: фон — атмосфера, а не рисунок. Текст поверх него
      // должен читаться, как на бумаге.
      final base = (dark ? 0.24 : 0.16) * intensity;
      final color = b.color.withValues(alpha: (base + 0.3 * v).clamp(0, 1));
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.dark != dark || old.intensity != intensity;
}

/// Стеклянная подложка: размывает фон под собой и слегка его подсвечивает.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.radius, required this.child});

  final double radius;
  final Widget child;

  // Без размытия фона: под движущимся фоном оно пересчитывалось на каждом
  // кадре и тормозило. «Стекло» дают полупрозрачная заливка и кромка.
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: RepaintBoundary(child: child),
  );
}

/// Редкие звёзды наверху и свечение у горизонта. Все движения укладываются
/// в минутный цикл целым числом периодов, поэтому петля без рывков.
class _CosmosPainter extends CustomPainter {
  _CosmosPainter(
    this.t,
    this.voice, {
    required Listenable repaint,
    required this.dark,
    required this.intensity,
  }) : super(repaint: repaint);

  final Animation<double> t;
  final Animation<double> voice;
  final bool dark;
  final double intensity;

  static final List<(Offset, double, int, double)> _stars = () {
    final random = math.Random(7);
    return [
      for (var i = 0; i < 22; i++)
        (
          // Редкие звёзды только в верхней трети — над шапкой, не под текстом.
          Offset(random.nextDouble(), random.nextDouble() * 0.3),
          0.5 + random.nextDouble() * 1.1,
          8 + random.nextInt(18), // мерцаний за минуту
          random.nextDouble() * math.pi * 2,
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final a = t.value * 2 * math.pi;
    final v = voice.value;
    final strength = (0.55 + 0.45 * intensity).clamp(0.0, 1.0);

    // Звёзды — только в тёмной теме: на светлом фоне они были бы грязью.
    if (dark) {
      final star = Paint();
      for (final (pos, radius, speed, phase) in _stars) {
        final twinkle = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(a * speed + phase));
        star.color = Colors.white.withValues(
          alpha: (0.22 * twinkle * strength).clamp(0.0, 1.0),
        );
        canvas.drawCircle(
          Offset(pos.dx * size.width, pos.dy * size.height),
          radius,
          star,
        );
      }
    }

    // Полос сияния нет: они пересекали заголовки, подписи и кнопки шапки.
    // Атмосферу дают мягкие пятна и свечение горизонта.

    // Свечение горизонта внизу — «дышит» и ярче, когда человек говорит.
    final glow = 0.5 + 0.5 * math.sin(a * 2);
    final center = Offset(size.width * 0.5, size.height * 1.02);
    final radius = size.width * (0.9 + 0.08 * glow + 0.2 * v);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF7C3AED).withValues(
              alpha: ((dark ? 0.22 : 0.12) * strength + 0.25 * v).clamp(0, 1),
            ),
            const Color(0xFF7C3AED).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_CosmosPainter old) =>
      old.dark != dark || old.intensity != intensity;
}

/// Пропускает уведомления [source] не чаще раза в [interval]: медленному
/// фону хватает и 20 кадров в секунду.
class FrameThrottle extends ChangeNotifier {
  FrameThrottle(this.source, this.interval) {
    source.addListener(_tick);
  }

  final Listenable source;
  final Duration interval;
  final _clock = Stopwatch()..start();

  void _tick() {
    if (_clock.elapsed < interval) return;
    _clock.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    source.removeListener(_tick);
    super.dispose();
  }
}
