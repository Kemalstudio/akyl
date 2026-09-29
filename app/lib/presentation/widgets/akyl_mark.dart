import 'package:flutter/material.dart';

import '../theme/akyl_theme.dart';

/// Фирменный знак: сплошной треугольник со скруглёнными углами и вырезом,
/// который не доходит до правой грани.
///
/// Рисуется кодом, а не картинкой: знак нужен в разных размерах — от 18 px
/// в шапке до 96 px на экране приветствия — и в двух цветах. Геометрия
/// совпадает с tools/make_icons.py, который генерирует иконки Android.
class AkylMark extends StatelessWidget {
  const AkylMark({super.key, this.size = 28, this.color});

  final double size;

  /// По умолчанию — основной цвет текста темы.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(color ?? context.akyl.textPrimary),
      isComplex: false,
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.color);

  final Color color;

  // Те же координаты, что в tools/make_icons.py, в системе 1024x1024.
  static const double _canvas = 1024;
  static const Offset _apex = Offset(512, 196);
  static const Offset _bottomLeft = Offset(208, 824);
  static const Offset _bottomRight = Offset(816, 824);
  static const double _cornerRadius = 62;
  static const double _gapTop = 638;
  static const double _gapBottom = 710;
  static const double _gapRight = 700;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / _canvas;
    Offset p(Offset o) => o * unit;

    final triangle = Path()
      ..moveTo(p(_apex).dx, p(_apex).dy)
      ..lineTo(p(_bottomRight).dx, p(_bottomRight).dy)
      ..lineTo(p(_bottomLeft).dx, p(_bottomLeft).dy)
      ..close();

    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;

    // Углы скругляются обводкой того же цвета: путь задан с запасом на неё.
    final round = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = _cornerRadius * unit * 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Вырез стирает уже нарисованное, поэтому знак пишется в отдельный слой.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawPath(triangle, fill);
    canvas.drawPath(triangle, round);
    canvas.drawRect(
      Rect.fromLTRB(0, _gapTop * unit, _gapRight * unit, _gapBottom * unit),
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.color != color;
}

/// Знак вместе с названием — шапка и экран приветствия.
class AkylWordmark extends StatelessWidget {
  const AkylWordmark({super.key, this.markSize = 22, this.fontSize = 19});

  /// Название приложения — одно место на всё приложение.
  static const String appName = 'Alym AI';

  final double markSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    // Стиль берётся из темы, а не задаётся здесь: иначе название выпадает
    // из общей типографики — в том числе из шрифта, подменяемого в тестах.
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      color: c.textPrimary,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AkylMark(size: markSize),
        SizedBox(width: markSize * 0.42),
        // «AI» приглушено: это уточнение, а не половина имени.
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Alym'),
              TextSpan(
                text: ' AI',
                style: TextStyle(color: c.textMuted),
              ),
            ],
          ),
          style: style,
        ),
      ],
    );
  }
}

/// Аватар помощника в чате: белый знак в фиолетовом круге, как значок
/// ассистента у ChatGPT и Claude.
class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C5CFF), Color(0xFFB44CE0)],
        ),
      ),
      child: AkylMark(size: size * 0.52, color: Colors.white),
    );
  }
}
