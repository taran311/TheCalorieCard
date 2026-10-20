import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A one-off burst of confetti that falls over [child] and then stops.
/// Does nothing when the device asks for reduced motion.
class ConfettiBurst extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final int pieces;

  const ConfettiBurst({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1800),
    this.pieces = 60,
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final List<_Piece> _pieces;
  bool _started = false;

  static const _colors = [
    Color(0xFF7C3AED),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF3B82F6),
    Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    _pieces = [
      for (var i = 0; i < widget.pieces; i++)
        _Piece(
          x: r.nextDouble(),
          drift: (r.nextDouble() - 0.5) * 0.3,
          delay: r.nextDouble() * 0.25,
          speed: 0.7 + r.nextDouble() * 0.5,
          spin: (r.nextDouble() - 0.5) * 12,
          size: 5 + r.nextDouble() * 5,
          color: _colors[i % _colors.length],
        ),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => _c.isAnimating
                  ? CustomPaint(painter: _Painter(_pieces, _c.value))
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class _Piece {
  final double x, drift, delay, speed, spin, size;
  final Color color;
  const _Piece({
    required this.x,
    required this.drift,
    required this.delay,
    required this.speed,
    required this.spin,
    required this.size,
    required this.color,
  });
}

class _Painter extends CustomPainter {
  final List<_Piece> pieces;
  final double t;
  _Painter(this.pieces, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + local * p.speed * (size.height + 40);
      final x = (p.x + p.drift * local) * size.width;
      final fade = local > 0.8 ? (1 - local) / 0.2 : 1.0;
      paint.color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Painter old) => old.t != t;
}

/// Shows confetti over the whole screen once, for a moment.
void showConfetti(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => const IgnorePointer(
      child: ConfettiBurst(pieces: 90, child: SizedBox.expand()),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 2000), () {
    if (entry.mounted) entry.remove();
  });
}

/// A rubber-stamp "CLOSED ✓" that thumps onto the screen and fades.
void showStamp(BuildContext context, String text) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: reduce ? 1 : 1300),
          builder: (context, t, child) {
            // 0–0.25: drop in from big; 0.25–0.7: hold; then fade.
            final drop = (t / 0.25).clamp(0.0, 1.0);
            final scale = 1.8 - 0.8 * Curves.easeOutBack.transform(drop);
            final fade = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3);
            return Opacity(
              opacity: (drop * fade).clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: -0.18,
                child: Transform.scale(scale: scale, child: child),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981), width: 4),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                color: Color(0xFF10B981),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(Duration(milliseconds: reduce ? 900 : 1400), () {
    if (entry.mounted) entry.remove();
  });
}
