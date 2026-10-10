import 'package:flutter/material.dart';
import 'package:namer_app/services/coach_service.dart';
import 'package:namer_app/ui/coach_glyph.dart';
import 'package:namer_app/ui/responsive.dart';

/// The gentle note under the card when today has gone over:
/// "You're 320 kcal over today. That's okay…" with a plan to even it out.
/// Tapping it opens Coach (see [CoachNudge]); this is just the look, so the
/// tutorials can show it too.
class CoachNudgeCard extends StatelessWidget {
  final int overBy;
  final double goal;
  final DateTime? today;
  final VoidCallback onTap;

  const CoachNudgeCard({
    super.key,
    required this.overBy,
    this.goal = 2000,
    this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final plan = OffsetPlan.compute(
      overBy: overBy,
      goal: goal,
      today: today ?? DateTime.now(),
    );
    return Semantics(
      button: true,
      label: 'Over by $overBy kcal. Ask Coach for a plan.',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDecor.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDecor.radius),
              border: Border.all(color: AppColors.violet300),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.brandGradient,
                  ),
                  child: const CoachGlyph(size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "You're $overBy kcal over today. That's okay.",
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan.summary,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Ask Coach',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.primaryDark),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [CoachNudgeCard] wired up: opens Coach with the plan as the question.
class CoachNudge extends StatelessWidget {
  final int overBy;
  final double goal;
  final DateTime today;

  /// Opens Coach with [question] (passed in so this file doesn't need to
  /// know about pages).
  final void Function(String question) onAsk;

  const CoachNudge({
    super.key,
    required this.overBy,
    required this.goal,
    required this.today,
    required this.onAsk,
  });

  @override
  Widget build(BuildContext context) {
    return CoachNudgeCard(
      overBy: overBy,
      goal: goal,
      today: today,
      onTap: () => onAsk(OffsetPlan.compute(
        overBy: overBy,
        goal: goal,
        today: today,
      ).question),
    );
  }
}
