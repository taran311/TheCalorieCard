import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:namer_app/services/coach_service.dart';
import 'package:namer_app/ui/coach_glyph.dart';
import 'package:namer_app/ui/responsive.dart';

/// The round, gently animated Calorie Coach button in the middle of the
/// bottom bar: a slowly turning colour ring, a soft breathing glow and the
/// Coach spark, which turns into flowing waves while Coach is thinking.
class CoachOrb extends StatefulWidget {
  final VoidCallback onTap;
  final bool selected;
  final double size;

  const CoachOrb({
    super.key,
    required this.onTap,
    this.selected = false,
    this.size = 60,
  });

  @override
  State<CoachOrb> createState() => _CoachOrbState();
}

class _CoachOrbState extends State<CoachOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect "reduce motion".
    if (MediaQuery.of(context).disableAnimations) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  static const _ring = SweepGradient(colors: [
    Color(0xFF6366F1), // indigo
    Color(0xFFA855F7), // purple
    Color(0xFFEC4899), // pink
    Color(0xFF22D3EE), // cyan
    Color(0xFF6366F1),
  ]);

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      button: true,
      label: 'Calorie Coach',
      child: Tooltip(
        message: 'Calorie Coach',
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1,
            duration: const Duration(milliseconds: 120),
            child: ValueListenableBuilder<bool>(
              valueListenable: CoachService.thinking,
              builder: (context, thinking, _) => AnimatedBuilder(
              animation: _spin,
              builder: (context, _) {
                final t = _spin.value;
                // Two slow breaths per turn of the ring (quicker and brighter
                // while Coach is thinking).
                final breath =
                    0.5 + 0.5 * math.sin(t * (thinking ? 12 : 4) * math.pi);
                return Container(
                  width: s,
                  height: s,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (thinking ? const Color(0xFFA855F7) : AppColors.primary)
                            .withValues(alpha: 0.22 + (thinking ? 0.3 : 0.18) * breath),
                        blurRadius: 14 + (thinking ? 16 : 10) * breath,
                        spreadRadius: 1 + 2 * breath,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: t * 2 * math.pi,
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _ring,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(3),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.brandGradient,
                            border: widget.selected
                                ? Border.all(color: Colors.white, width: 2)
                                : null,
                          ),
                        ),
                      ),
                      CoachGlyph(size: s * 0.46, thinking: thinking),
                    ],
                  ),
                );
              },
            ),
            ),
          ),
        ),
      ),
    );
  }
}
