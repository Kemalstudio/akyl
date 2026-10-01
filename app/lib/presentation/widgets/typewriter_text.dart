import 'dart:async';

import 'package:flutter/material.dart';

/// Текст, который печатается по буквам с мигающей кареткой — как ответ
/// в ChatGPT. Печатается один раз: при повторной сборке виджета с тем же
/// текстом анимация не начинается заново.
class TypewriterText extends StatefulWidget {
  const TypewriterText(
    this.text, {
    super.key,
    this.style,
    this.animate = true,
    this.onProgress,
  });

  final String text;
  final TextStyle? style;

  /// false — показать сразу целиком (старые сообщения, тесты).
  final bool animate;

  /// Вызывается, пока текст растёт: список прокручивается вслед за ним.
  final VoidCallback? onProgress;

  /// В тестах печать мгновенная: таймеры мешали бы `pumpAndSettle`.
  static bool enabled = true;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  Timer? _timer;
  int _shown = 0;
  bool _cursorOn = true;

  bool get _typing => _shown < widget.text.length;

  @override
  void initState() {
    super.initState();
    final animate =
        widget.animate &&
        TypewriterText.enabled &&
        !WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    if (!animate) {
      _shown = widget.text.length;
      return;
    }
    // Длинный ответ печатается быстрее: вся фраза укладывается примерно
    // в полторы секунды, короткая — не быстрее 22 мс на знак.
    final perChar = (1500 / widget.text.length).clamp(8, 22).round();
    var tick = 0;
    _timer = Timer.periodic(Duration(milliseconds: perChar), (timer) {
      tick++;
      if (!mounted) return;
      setState(() {
        // Пробелы проскакиваем вместе со словом — так печать ровнее.
        _shown = (_shown + 1).clamp(0, widget.text.length);
        while (_shown < widget.text.length && widget.text[_shown - 1] == ' ') {
          _shown++;
        }
        if (tick % 12 == 0) _cursorOn = !_cursorOn;
      });
      widget.onProgress?.call();
      if (!_typing) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: widget.text.substring(0, _shown)),
          if (_typing)
            TextSpan(
              text: ' ●',
              style: style.copyWith(
                fontSize: (style.fontSize ?? 16) * 0.7,
                color: style.color?.withValues(alpha: _cursorOn ? 0.9 : 0.35),
              ),
            ),
          // Непечатанный остаток занимает место невидимо: строки не
          // прыгают, пока текст дописывается.
          if (_typing)
            TextSpan(
              text: widget.text.substring(_shown),
              style: const TextStyle(color: Colors.transparent),
            ),
        ],
      ),
    );
  }
}
