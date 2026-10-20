import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';

/// Grey placeholder rows with a soft shimmer, shown while a list loads
/// (instead of a spinner), so the page keeps its shape. Holds still when
/// the device asks for reduced motion.
class SkeletonList extends StatefulWidget {
  final int rows;
  final EdgeInsetsGeometry padding;

  /// Rows with a round avatar on the left (friends), or a square (recipes).
  final bool roundLeading;

  const SkeletonList({
    super.key,
    this.rows = 5,
    this.padding = const EdgeInsets.symmetric(vertical: 12),
    this.roundLeading = false,
  });

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.border;
    final shine = AppColors.surface;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    final rows = Column(
      children: [
        for (var i = 0; i < widget.rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(
                        widget.roundLeading ? 21 : 10),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: i.isEven ? 0.6 : 0.45,
                        child: bar(double.infinity, 13),
                      ),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: i.isEven ? 0.35 : 0.5,
                        child: bar(double.infinity, 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                bar(44, 13),
              ],
            ),
          ),
      ],
    );
    return Semantics(
      label: 'Loading',
      child: Padding(
        padding: widget.padding,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = _c.value * 3 - 1; // sweep from left of to right of
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment(t - 1, 0),
                end: Alignment(t + 1, 0),
                colors: [base, shine, base],
                stops: const [0.3, 0.5, 0.7],
              ).createShader(rect),
              child: child,
            );
          },
          child: ExcludeSemantics(child: rows),
        ),
      ),
    );
  }
}
