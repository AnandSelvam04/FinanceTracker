import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/haptics.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

/// Marks a win — a goal reached, a loan cleared, a month under budget — with
/// a burst of confetti over the screen and a line saying what was achieved.
///
/// The confetti is skipped when the phone asks for reduced motion; the
/// message still shows.
void celebrate(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Row(
      children: [
        const Text('🎉', style: TextStyle(fontSize: FontSizes.title)),
        const SizedBox(width: Space.sm),
        Expanded(child: Text(message)),
      ],
    ),
  ));
  showConfetti(context);
}

/// The confetti alone, for a screen that already says what happened.
void showConfetti(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  Haptics.medium();
  if (overlay == null || reduceMotion) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Confetti(onDone: () {
      if (entry.mounted) entry.remove();
    }),
  );
  overlay.insert(entry);
}

class _Confetti extends StatefulWidget {
  final VoidCallback onDone;
  const _Confetti({required this.onDone});

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _Piece {
  final double x; // start, 0..1 of the width
  final double drift; // sideways travel, in widths
  final double speed; // fall distance, in heights
  final double delay; // 0..0.3 of the run
  final double size;
  final double spin;
  final Color color;
  const _Piece(this.x, this.drift, this.speed, this.delay, this.size, this.spin,
      this.color);
}

class _ConfettiState extends State<_Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Piece> _pieces;

  static const _colors = [
    Color(0xFFFFC107),
    Color(0xFF4CAF50),
    Color(0xFF29B6F6),
    Color(0xFFEC407A),
    Color(0xFF7E57C2),
    Color(0xFFFF7043),
  ];

  @override
  void initState() {
    super.initState();
    // Seeded: the burst looks the same each time, and tests are repeatable.
    final random = math.Random(7);
    _pieces = [
      for (var i = 0; i < 70; i++)
        _Piece(
          random.nextDouble(),
          (random.nextDouble() - 0.5) * 0.3,
          0.7 + random.nextDouble() * 0.6,
          random.nextDouble() * 0.3,
          6 + random.nextDouble() * 6,
          (random.nextDouble() - 0.5) * 12,
          _colors[i % _colors.length],
        ),
    ];
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Purely decorative: never takes a tap and says nothing to a screen
    // reader (the snackbar carries the message).
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(_pieces, _controller),
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final Animation<double> progress;
  _ConfettiPainter(this.pieces, this.progress) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final paint = Paint();
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // Fades out over the last third of its fall.
      final alpha = local < 0.66 ? 1.0 : (1 - local) / 0.34;
      paint.color = p.color.withValues(alpha: alpha.clamp(0.0, 1.0));
      final dx = (p.x + p.drift * local) * size.width;
      final dy = -20 + local * p.speed * size.height;
      canvas
        ..save()
        ..translate(dx, dy)
        ..rotate(p.spin * local)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: p.size, height: p.size * 0.55),
            const Radius.circular(1.5),
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => false;
}
