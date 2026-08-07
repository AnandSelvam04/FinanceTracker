import 'package:flutter/material.dart';

/// Fades and slides its [child] up into place once, on first build.
///
/// Used to give short, statically-built lists (menus, tutorial steps,
/// dashboard sections) a gentle staggered entrance. Pass an increasing [delay]
/// per item to stagger them.
///
/// Deliberately not used on long, recycled `ListView.builder` rows: those
/// widgets are rebuilt as they scroll back into view, which would replay the
/// animation and read as jank.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Vertical offset (in logical pixels) the child travels while fading in.
  final double offset;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 350),
    this.offset = 16,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
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
      opacity: _fade,
      child: AnimatedBuilder(
        animation: _fade,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, widget.offset * (1 - _fade.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
