import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/voice/voice_phase.dart';
import 'akyl_mark.dart';
import 'cosmic.dart';

/// Живой знак Alym AI: сфера с фирменным треугольником, которая показывает,
/// что делает помощник. Не крутящийся индикатор, а один предмет с разными
/// «жестами»:
///
/// * покой — очень медленное дыхание ореола;
/// * жду «Макс» — тонкое кольцо изредка расходится от сферы, как сонар;
/// * услышал имя — короткая вспышка: кольцо быстро раскрывается, знак
///   чуть подпрыгивает;
/// * слушаю команду — три мягких кольца следуют за громкостью голоса;
/// * думаю — два спутника на наклонной орбите и бегущий блик по кромке;
/// * говорю — ореол пульсирует в ритме слов ответа;
/// * ошибка — медленная красная пульсация.
///
/// Слои не переключаются рывком: их веса плавно перетекают к целевым, так
/// что смена состояния — это движение, а не вспышка. Анимация прерываема
/// в любой момент. В покое кадры реже (30 в секунду), без движения
/// (reduced motion, тесты) — ни одного лишнего кадра.
class AlymLogo extends StatefulWidget {
  const AlymLogo({
    super.key,
    required this.phase,
    this.level,
    this.wakeCount = 0,
    this.size = 88,
  });

  final VoicePhase phase;

  /// Громкость 0..1: голос человека или ритм ответа.
  final ValueNotifier<double>? level;

  /// Счётчик обращений: изменился — играем вспышку.
  final int wakeCount;

  final double size;

  @override
  State<AlymLogo> createState() => _AlymLogoState();
}

class _Weights {
  double listen = 0, rings = 0, orbit = 0, speak = 0, error = 0, idle = 1;
}

class _AlymLogoState extends State<AlymLogo> with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  final _w = _Weights();
  Duration _elapsed = Duration.zero;
  Duration _lastFrame = Duration.zero;
  double _time = 0;
  bool _animate = true;

  @override
  void initState() {
    super.initState();
    _snapWeights();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = ambientMotion(context);
    if (_animate) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
      _snapWeights();
    }
  }

  @override
  void didUpdateWidget(AlymLogo old) {
    super.didUpdateWidget(old);
    if (widget.wakeCount != old.wakeCount && _animate) {
      _flash.forward(from: 0);
    }
    if (!_animate) _snapWeights();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _flash.dispose();
    super.dispose();
  }

  _Weights _targets() {
    final t = _Weights()..idle = 0;
    switch (widget.phase) {
      case VoicePhase.listeningForWake:
        t.listen = 1;
      case VoicePhase.wakeDetected || VoicePhase.listeningForCommand:
        t.rings = 1;
      case VoicePhase.processing ||
          VoicePhase.starting ||
          VoicePhase.recovering:
        t.orbit = 1;
      case VoicePhase.speaking:
        t.speak = 1;
      case VoicePhase.error:
        t.error = 1;
      case VoicePhase.disabled || VoicePhase.paused:
        t.idle = 1;
    }
    return t;
  }

  void _snapWeights() {
    final t = _targets();
    _w
      ..listen = t.listen
      ..rings = t.rings
      ..orbit = t.orbit
      ..speak = t.speak
      ..error = t.error
      ..idle = t.idle;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _elapsed).inMicroseconds / 1e6;
    _elapsed = elapsed;
    final calm =
        widget.phase == VoicePhase.disabled ||
        widget.phase == VoicePhase.paused ||
        widget.phase == VoicePhase.listeningForWake;
    // В покое 30 кадров в секунду: медленное дыхание не различит глаз.
    if (calm &&
        !_flash.isAnimating &&
        elapsed - _lastFrame < const Duration(milliseconds: 33)) {
      return;
    }
    final frameDt = (elapsed - _lastFrame).inMicroseconds / 1e6;
    _lastFrame = elapsed;
    _time += frameDt.clamp(0, 0.1);

    // Веса слоёв перетекают к цели за ~250 мс.
    final t = _targets();
    final k = 1 - math.exp(-frameDt * 12);
    double step(double a, double b) => a + (b - a) * k;
    _w
      ..listen = step(_w.listen, t.listen)
      ..rings = step(_w.rings, t.rings)
      ..orbit = step(_w.orbit, t.orbit)
      ..speak = step(_w.speak, t.speak)
      ..error = step(_w.error, t.error)
      ..idle = step(_w.idle, t.idle);
    if (dt >= 0) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final level = widget.level;
    return Semantics(
      label: _describe(widget.phase),
      child: RepaintBoundary(
        child: SizedBox(
          width: size * 1.8,
          height: size * 1.8,
          child: AnimatedBuilder(
            animation: Listenable.merge([_flash, ?level]),
            builder: (context, _) {
              final voice = level?.value ?? 0;
              final flash = Curves.easeOutCubic.transform(_flash.value);
              final hop = math.sin(_flash.value * math.pi) * size * 0.05;
              return CustomPaint(
                painter: _LogoPainter(
                  time: _time,
                  voice: voice,
                  flash: _flash.isAnimating ? flash : 0,
                  w: _w,
                  radius: size / 2,
                ),
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, -hop),
                    child: AkylMark(size: size * 0.36, color: Colors.white),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _describe(VoicePhase phase) => switch (phase) {
    VoicePhase.listeningForWake => 'Жду обращения',
    VoicePhase.wakeDetected || VoicePhase.listeningForCommand => 'Слушаю',
    VoicePhase.processing => 'Думаю',
    VoicePhase.speaking => 'Отвечаю',
    VoicePhase.error => 'Ошибка голоса',
    _ => 'Alym AI',
  };
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({
    required this.time,
    required this.voice,
    required this.flash,
    required this.w,
    required this.radius,
  }) : listen = w.listen,
       rings = w.rings,
       orbit = w.orbit,
       speak = w.speak,
       error = w.error;

  final double time, voice, flash, radius;
  final _Weights w;

  // Копии весов — для shouldRepaint.
  final double listen, rings, orbit, speak, error;

  static const _violet = Color(0xFF8B5CF6);
  static const _lilac = Color(0xFFC4B5FD);
  static const _danger = Color(0xFFF87171);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = radius;
    final breathe = 0.5 + 0.5 * math.sin(time * 2 * math.pi / 5);
    final accent = Color.lerp(_violet, _danger, error)!;

    // Ореол: дышит в покое, разгорается от голоса и ответа.
    final errorPulse = error * (0.5 + 0.5 * math.sin(time * 2 * math.pi / 1.6));
    final haloScale =
        1.35 +
        0.08 * breathe +
        0.35 * voice * (rings + speak) +
        0.15 * errorPulse;
    canvas.drawCircle(
      c,
      r * haloScale,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.5 + 0.3 * voice * (rings + speak)),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r * haloScale)),
    );

    // Сонар ожидания: одно кольцо раз в 2.8 с.
    if (listen > 0.01) {
      final p = (time / 2.8) % 1;
      _ring(
        canvas,
        c,
        r * (1.02 + 0.55 * p),
        _lilac,
        (1 - p) * 0.55 * listen,
        1.4,
      );
    }

    // Кольца голоса: следуют за громкостью, каждое со своей фазой.
    if (rings > 0.01) {
      for (var i = 0; i < 3; i++) {
        final wobble = math.sin(time * 5 + i * 1.7) * 0.04;
        final grow = 1.08 + i * 0.16 + voice * (0.22 + i * 0.1) + wobble;
        _ring(canvas, c, r * grow, _lilac, (0.55 - i * 0.15) * rings, 1.6);
      }
    }

    // Ответ: волны уходят от сферы в ритме слов.
    if (speak > 0.01) {
      for (var i = 0; i < 2; i++) {
        final p = ((time * 0.9) + i * 0.5) % 1;
        _ring(
          canvas,
          c,
          r * (1.05 + 0.5 * p + 0.2 * voice),
          _lilac,
          (1 - p) * (0.35 + 0.4 * voice) * speak,
          2,
        );
      }
    }

    // Вспышка при обращении: быстрое кольцо и отблеск.
    if (flash > 0) {
      _ring(
        canvas,
        c,
        r * (1 + 0.9 * flash),
        Colors.white,
        (1 - flash) * 0.8,
        2.4,
      );
    }

    // Сфера.
    final sphere = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.1,
          colors: [
            Color.lerp(
              const Color(0xFFD9CCFF),
              const Color(0xFFFECACA),
              error,
            )!,
            accent,
            Color.lerp(
              const Color(0xFF3B1E8F),
              const Color(0xFF7F1D1D),
              error,
            )!,
          ],
          stops: const [0, 0.45, 1],
        ).createShader(sphere),
    );

    // Раздумье: блик бежит по кромке, два спутника на наклонной орбите.
    if (orbit > 0.01) {
      final start = time * 2 * math.pi * 0.8;
      canvas.drawArc(
        sphere.inflate(1),
        start,
        math.pi * 0.9,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: start,
            endAngle: start + math.pi * 0.9,
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.9 * orbit),
            ],
            transform: GradientRotation(start),
          ).createShader(sphere),
      );
      final orbitRect = Rect.fromCenter(
        center: c,
        width: r * 3,
        height: r * 0.9,
      );
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-0.3);
      canvas.translate(-c.dx, -c.dy);
      canvas.drawOval(
        orbitRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _lilac.withValues(alpha: 0.35 * orbit),
      );
      for (var i = 0; i < 2; i++) {
        final a = time * 2 * math.pi * 0.6 + i * math.pi;
        final moon = Offset(
          c.dx + orbitRect.width / 2 * math.cos(a),
          c.dy + orbitRect.height / 2 * math.sin(a),
        );
        canvas.drawCircle(
          moon,
          5,
          Paint()..color = _lilac.withValues(alpha: 0.3 * orbit),
        );
        canvas.drawCircle(
          moon,
          2.4,
          Paint()..color = Colors.white.withValues(alpha: orbit),
        );
      }
      canvas.restore();
    } else {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.35),
      );
    }
  }

  void _ring(
    Canvas canvas,
    Offset c,
    double radius,
    Color color,
    double alpha,
    double width,
  ) {
    if (alpha <= 0) return;
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.time != time ||
      old.voice != voice ||
      old.flash != flash ||
      old.listen != listen ||
      old.rings != rings ||
      old.orbit != orbit ||
      old.speak != speak ||
      old.error != error;
}
