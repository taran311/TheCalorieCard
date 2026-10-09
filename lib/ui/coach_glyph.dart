import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Calorie Coach's mark.
///
/// Idle: a soft four-point spark with a small companion spark, gently
/// breathing and turning. Thinking: the spark melts into flowing sound
/// waves (three sine lines drifting past each other), then back again when
/// the answer arrives.
class CoachGlyph extends StatefulWidget {
  final double size;
  final bool thinking;
  final Color color;

  const CoachGlyph({
    super.key,
    this.size = 24,
    this.thinking = false,
    this.color = Colors.white,
  });

  @override
  State<CoachGlyph> createState() => _CoachGlyphState();
}

class _CoachGlyphState extends State<CoachGlyph> with TickerProviderStateMixin {
  // Drives the idle breathing and the wave flow.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  // 0 = spark, 1 = waves.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: widget.thinking ? 1 : 0,
  );

  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.of(context).disableAnimations;
    if (_still) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void didUpdateWidget(CoachGlyph old) {
    super.didUpdateWidget(old);
    if (old.thinking != widget.thinking) {
      if (widget.thinking) {
        _morph.forward();
      } else {
        _morph.reverse();
      }
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_clock, _morph]),
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _GlyphPainter(
            t: _clock.value,
            morph: Curves.easeInOut.transform(_morph.value),
            color: widget.color,
            still: _still,
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final double t;
  final double morph;
  final Color color;
  final bool still;

  _GlyphPainter({
    required this.t,
    required this.morph,
    required this.color,
    required this.still,
  });

  /// A four-point spark with curved (concave) sides.
  static Path _spark(Offset c, double r, double pinch) {
    final k = r * pinch;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
  }

  void _paintSpark(Canvas canvas, Size size, double opacity) {
    if (opacity <= 0) return;
    final s = size.width;
    final breath = still ? 0.5 : 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    // Shrinks a little as it turns into waves.
    final scale = 1 - 0.35 * morph;

    // Main spark, slightly low-left, with a gentle sway.
    final main = Offset(s * 0.44, s * 0.56);
    final r = s * 0.40 * (0.94 + 0.06 * breath) * scale;
    canvas.save();
    canvas.translate(main.dx, main.dy);
    canvas.rotate(still ? 0 : math.sin(t * 2 * math.pi) * 0.08);
    canvas.translate(-main.dx, -main.dy);
    final rect = Rect.fromCircle(center: main, radius: r);
    canvas.drawPath(
      _spark(main, r, 0.16),
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: opacity * 0.82),
          ],
        ).createShader(rect),
    );
    canvas.restore();

    // Companion spark, top right, twinkling out of step.
    final twinkle = still ? 0.6 : 0.5 + 0.5 * math.sin(t * 2 * math.pi + 2.2);
    final small = Offset(s * 0.80, s * 0.20);
    canvas.drawPath(
      _spark(small, s * 0.15 * (0.75 + 0.35 * twinkle) * scale, 0.2),
      Paint()..color = color.withValues(alpha: opacity * (0.6 + 0.4 * twinkle)),
    );

    // A tiny dot, bottom right, for balance.
    canvas.drawCircle(
      Offset(s * 0.82, s * 0.80),
      s * 0.045 * scale,
      Paint()..color = color.withValues(alpha: opacity * 0.7),
    );
  }

  void _paintWaves(Canvas canvas, Size size, double opacity) {
    if (opacity <= 0) return;
    final s = size.width;
    final mid = s / 2;
    final phase = t * 2 * math.pi;
    final layers = [
      // amplitude, frequency, speed, alpha, width
      (0.30, 1.6, 2.0, 1.0, 0.085),
      (0.22, 2.3, -3.0, 0.65, 0.065),
      (0.16, 3.1, 4.0, 0.45, 0.055),
    ];
    for (final (amp, freq, speed, alpha, width) in layers) {
      final path = Path();
      const steps = 28;
      for (var i = 0; i <= steps; i++) {
        final x = i / steps;
        // Taper to nothing at both ends, like a voice wave.
        final envelope = math.sin(math.pi * x);
        final y = mid +
            math.sin(x * freq * 2 * math.pi + phase * speed) *
                amp *
                s *
                envelope *
                morph;
        final px = s * 0.08 + x * s * 0.84;
        if (i == 0) {
          path.moveTo(px, y);
        } else {
          path.lineTo(px, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = s * width
          ..color = color.withValues(alpha: opacity * alpha),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintSpark(canvas, size, 1 - morph);
    _paintWaves(canvas, size, morph);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.t != t ||
      old.morph != morph ||
      old.color != color ||
      old.still != still;
}
