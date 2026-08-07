import 'package:flutter/material.dart';

/// A shimmering placeholder block used while data loads.
///
/// Cold starts previously showed a bare centered spinner that flashed in and
/// out; skeletons that echo the real layout read as far smoother because the
/// page keeps its shape while the numbers arrive.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = scheme.surfaceContainerHigh;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, highlight, base],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value.clamp(0.0, 1.0),
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton stand-in for the dashboard while the first year of data loads.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(width: 160, height: 20),
        const SizedBox(height: 20),
        SkeletonBox(
          height: 150,
          width: double.infinity,
          borderRadius: BorderRadius.circular(18),
        ),
        const SizedBox(height: 20),
        Center(
          child: SkeletonBox(
            width: 220,
            height: 220,
            borderRadius: BorderRadius.circular(110),
          ),
        ),
        const SizedBox(height: 20),
        const SkeletonBox(width: 120, height: 18),
        const SizedBox(height: 16),
        SkeletonBox(
          height: 120,
          width: double.infinity,
          borderRadius: BorderRadius.circular(18),
        ),
      ],
    );
  }
}

/// Skeleton rows shaped like the transaction list.
class ListSkeleton extends StatelessWidget {
  final int rows;
  const ListSkeleton({super.key, this.rows = 7});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, _) => Row(
        children: [
          const SkeletonBox(
            width: 44,
            height: 44,
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 160, height: 14),
                const SizedBox(height: 8),
                SkeletonBox(width: 100, height: 12),
              ],
            ),
          ),
          const SizedBox(width: 14),
          const SkeletonBox(width: 60, height: 14),
        ],
      ),
    );
  }
}
