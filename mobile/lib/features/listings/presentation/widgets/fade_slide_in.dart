import 'package:flutter/material.dart';

// Fades a row in while it rises slightly into place; later rows start a
// little after earlier ones, so a new list arrives smoothly.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.index, required this.child});

  static const Duration duration = Duration(milliseconds: 250);
  static const Duration step = Duration(milliseconds: 30);
  static const int maxSteps = 6;

  final int index;
  final Widget child;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration:
        FadeSlideIn.duration +
        FadeSlideIn.step * widget.index.clamp(0, FadeSlideIn.maxSteps),
  )..forward();

  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      1 -
          FadeSlideIn.duration.inMilliseconds /
              _controller.duration!.inMilliseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _progress,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(_progress),
        child: widget.child,
      ),
    );
  }
}
