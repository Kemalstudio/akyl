import 'package:flutter/material.dart';

import '../../domain/dialog/dialog_state.dart';
import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';

/// Тонкая строка состояния автомата диалога (ТЗ, раздел 5).
///
/// В покое её не видно вовсе: пустой экран — тоже сообщение. Появляется, только
/// когда ассистент чем-то занят или ждёт ответа, и тогда занимает одну строку
/// с бегущей точкой — чтобы «думаю» отличалось от «завис».
class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, required this.state, required this.busy});

  final DialogState state;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;

    final (label, color, animated) = switch (state) {
      DialogState.listening => ('Слушаю', c.accent, true),
      DialogState.processing => ('Думаю', c.textSecondary, true),
      DialogState.executing => ('Выполняю', c.textSecondary, true),
      // Вопрос и кнопки ответа уже в самой реплике — не дублируем.
      DialogState.awaitingConfirmation => (null, c.accent, false),
      DialogState.awaitingChoice => ('Жду выбора', c.accent, false),
      DialogState.idle => (null, c.textMuted, false),
    };

    return AnimatedSize(
      duration: AkylMotion.quick,
      curve: AkylMotion.move,
      alignment: Alignment.topCenter,
      child: label == null
          ? const SizedBox(width: double.infinity, height: 0)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                AkylShape.gutter,
                0,
                AkylShape.gutter,
                10,
              ),
              child: Row(
                children: [
                  _Pulse(color: color, animated: animated || busy),
                  const SizedBox(width: 8),
                  Flexible(
                    child: SoftSwitcher(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        key: ValueKey(label),
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(color: color),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Точка: пульсирует, пока идёт работа, и стоит ровно, пока ждут человека.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, required this.animated});

  final Color color;
  final bool animated;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  // Контроллер создаётся сразу, а не лениво: при `late final` он в непульсирующем
  // состоянии впервые инициализировался бы прямо в dispose(), а создание тикера
  // читает TickerMode из дерева — которого на этот момент уже нет.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.animated) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Pulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated == oldWidget.animated) return;
    if (widget.animated) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.animated
          ? Tween<double>(begin: 0.28, end: 1).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
            )
          : const AlwaysStoppedAnimation(1),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
