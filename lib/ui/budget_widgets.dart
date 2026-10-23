import 'package:flutter/material.dart';
import 'package:namer_app/services/budget_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/calorie_symbol.dart';

/// One budget's progress: "Snacks today · 240 of 300 kcal", a bar and what's
/// left. Amber from 80% (and when over) rather than red: a budget is a
/// guide, and the words say the same thing as the colour.
class BudgetProgressRow extends StatelessWidget {
  final BudgetProgress progress;

  const BudgetProgressRow({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final b = p.budget;
    final near = p.fraction >= 0.8;
    final barColor = near ? AppColors.amber : AppColors.primary;
    final category = b.category;
    final icon = category?.icon ?? Icons.restaurant_menu;
    final iconColor = category?.color ?? AppColors.primary;
    return Semantics(
      label: '${p.summary}. ${p.leftLabel}.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${b.name} ${b.period}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$calSym${BudgetService.kcal(p.used)} of '
                        '$calSym${BudgetService.kcal(b.limit)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: p.fraction.isNaN
                          ? 0
                          : p.fraction.clamp(0.0, 1.0).toDouble(),
                      minHeight: 7,
                      backgroundColor: barColor.withValues(alpha: 0.14),
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    p.leftLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: near ? FontWeight.w700 : FontWeight.w400,
                      color: near ? AppText.amber700 : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
