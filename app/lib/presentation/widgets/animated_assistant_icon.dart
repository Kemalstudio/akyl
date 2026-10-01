import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Bundled Lottie icons: play once, replay on hover, honor reduced motion.
class AnimatedAssistantIcon extends StatefulWidget {
  const AnimatedAssistantIcon({super.key, required this.asset, this.size = 32});
  final String asset;
  final double size;
  @override
  State<AnimatedAssistantIcon> createState() => _AnimatedAssistantIconState();
}

class _AnimatedAssistantIconState extends State<AnimatedAssistantIcon>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(vsync: this);
  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _animation.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: MouseRegion(
      onEnter: (_) {
        if (!MediaQuery.disableAnimationsOf(context)) {
          _animation.forward(from: 0);
        }
      },
      child: Lottie.asset(
        'assets/lottie/${widget.asset}.json',
        width: widget.size,
        height: widget.size,
        controller: _animation,
        repeat: false,
        onLoaded: (composition) {
          if (!mounted) return;
          _animation.duration = composition.duration;
          if (MediaQuery.disableAnimationsOf(context)) {
            _animation.value = 1;
          } else {
            _animation.forward(from: 0);
          }
        },
      ),
    ),
  );
}
