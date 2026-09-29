import 'package:flutter/material.dart';

/// Длительности и кривые движения — одни на всё приложение.
///
/// Ассистент отвечает за доли секунды, и если интерфейс при этом дёргается,
/// быстрым он не ощущается. Поэтому всё появляется плавно и всегда по одной
/// схеме: элемент выезжает снизу с прозрачностью, уходит — на месте, гаснув.
abstract final class AkylMotion {
  /// Смена иконки, подсветка рамки.
  static const Duration instant = Duration(milliseconds: 160);

  /// Появление реплики, смена подписи.
  static const Duration quick = Duration(milliseconds: 260);

  /// Переходы между состояниями экрана.
  static const Duration base = Duration(milliseconds: 380);

  /// Смена экрана целиком.
  static const Duration slow = Duration(milliseconds: 520);

  /// Появление: быстрый старт, долгое мягкое торможение.
  /// Именно это ощущается «плавным» — линейная кривая выглядит механической.
  static const Curve enter = Cubic(0.16, 1.0, 0.3, 1.0);

  /// Исчезновение: короче входа, чтобы не задерживать следующий кадр.
  static const Curve exit = Curves.easeInCubic;

  /// Движение внутри экрана: прокрутка, изменение размера.
  static const Curve move = Curves.easeOutCubic;

  /// Задержка между соседними элементами в цепочке появления.
  static const Duration stagger = Duration(milliseconds: 55);
}

/// Появление снизу с проявлением — общий приём для всего приложения.
///
/// Анимация играет один раз при вставке в дерево. [delay] выстраивает
/// элементы в цепочку: заголовок, потом подзаголовок, потом карточки.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AkylMotion.base,
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// На сколько пикселей элемент приподнимается снизу.
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    // Задержка — часть самой анимации (Interval), а не отдельный таймер:
    // таймер пережил бы экран, закрытый раньше срока.
    final total = widget.delay + widget.duration;
    _controller = AnimationController(vsync: this, duration: total);
    final start = total.inMicroseconds == 0
        ? 0.0
        : widget.delay.inMicroseconds / total.inMicroseconds;
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: AkylMotion.enter),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Мягкая замена одного содержимого другим: старое гаснет, новое проявляется
/// и чуть подрастает. Используется там, где элемент не переезжает, а меняется.
class SoftSwitcher extends StatelessWidget {
  const SoftSwitcher({
    super.key,
    required this.child,
    this.duration = AkylMotion.quick,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AkylMotion.enter,
      switchOutCurve: AkylMotion.exit,
      // Уходящее не должно толкать приходящее: они лежат друг на друге.
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Переход между экранами в стиле приложения: новый экран проявляется
/// и чуть подрастает, старый в это время немного отступает в глубину.
/// Стандартный сдвиг Android на стеклянном фоне выглядел бы рывком.
class SoftPageRoute<T> extends PageRouteBuilder<T> {
  SoftPageRoute({required WidgetBuilder builder})
    : super(
        transitionDuration: AkylMotion.slow,
        reverseTransitionDuration: AkylMotion.base,
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (context, animation, secondary, child) {
          final enter = CurvedAnimation(
            parent: animation,
            curve: AkylMotion.enter,
            reverseCurve: AkylMotion.exit,
          );
          final behind = CurvedAnimation(
            parent: secondary,
            curve: AkylMotion.move,
          );
          return FadeTransition(
            opacity: enter,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(enter),
              child: FadeTransition(
                opacity: Tween<double>(begin: 1, end: 0.6).animate(behind),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1, end: 0.97).animate(behind),
                  child: child,
                ),
              ),
            ),
          );
        },
      );
}
