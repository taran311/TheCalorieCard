import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/even_out.dart';
import 'package:namer_app/ui/calorie_card.dart' show formatCardKcal;
import 'package:namer_app/ui/calorie_symbol.dart';
import 'package:namer_app/ui/responsive.dart';

/// What to do about going over, picked when closing a day.
enum OverChoice { pot, potAndSpread, spread, leave }

/// Closed a day [over] budget: asks whether to cover it from the pot,
/// spread it over the rest of the week, or leave it. [day] is 'today' or
/// 'yesterday', for the wording. Null if there's nothing but "leave it" to
/// offer, or they dismissed it; [fromPot] is how much the pot would cover.
Future<({OverChoice choice, int fromPot})?> askAboutOverspend(
  BuildContext context, {
  required int over,
  required Map<String, dynamic> data,
  required double goal,
  required String day,
}) async {
  if (over <= 0) return null;
  final now = BalanceService.now();
  final today = BalanceService.dateKey(now);
  final pot = BalanceService.potFrom(data).floor();
  final fromPot = pot >= over ? over : pot;
  final rest = over - fromPot;
  final plan = EvenOutPlan.fromData(data);
  // Already spread today: spreading again would count it twice.
  final spreadToday = plan != null && plan.setOn == today;
  final running = plan != null && !plan.endedBefore(today);
  ({int perDay, int days, int total})? spread(int kcal) => spreadToday
      ? null
      : EvenOut.preview(plan, overBy: kcal, goal: goal, now: now);
  final spreadAll = spread(over);
  final spreadRest = rest > 0 ? spread(rest) : null;
  String lessADay(({int perDay, int days, int total}) p) =>
      '$calSym${p.perDay} less a day for ${p.days} '
      'day${p.days == 1 ? '' : 's'}, from tomorrow'
      '${running ? ', joined with the plan you have' : ''}.';
  final dayTitle = day[0].toUpperCase() + day.substring(1);

  final options = <(OverChoice, IconData, String, String)>[
    if (fromPot > 0 && rest == 0)
      (
        OverChoice.pot,
        Icons.savings_outlined,
        'Cover it from your pot',
        '$calSym$fromPot from your $calSym$pot pot. $dayTitle ends even.',
      ),
    if (fromPot > 0 && spreadRest != null)
      (
        OverChoice.potAndSpread,
        Icons.savings_outlined,
        'Use your pot, spread the rest',
        '$calSym$fromPot from your pot, then ${lessADay(spreadRest)}',
      ),
    if (fromPot > 0 && rest > 0 && spreadRest == null)
      (
        OverChoice.pot,
        Icons.savings_outlined,
        'Use your pot',
        'Your $calSym$pot pot takes $calSym$fromPot off it.',
      ),
    if (spreadAll != null)
      (
        OverChoice.spread,
        Icons.calendar_view_week_outlined,
        'Spread it over the week',
        lessADay(spreadAll)[0].toUpperCase() + lessADay(spreadAll).substring(1),
      ),
  ];
  if (options.isEmpty || !context.mounted) return null;

  final choice = await showModalBottomSheet<OverChoice>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$calSym${formatCardKcal(over)} over $day',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink),
            ),
            const SizedBox(height: 6),
            Text(
              "That's fine. Want to even it out?",
              style: TextStyle(fontSize: 15, color: AppColors.gray700),
            ),
            const SizedBox(height: 12),
            for (final (c, icon, title, subtitle) in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Icon(icon, color: AppColors.primary),
                    title: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(subtitle),
                    onTap: () => Navigator.pop(sheetContext, c),
                  ),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, OverChoice.leave),
              child: const Text("Leave it: one day over doesn't undo anything"),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || choice == OverChoice.leave) return null;
  return (choice: choice, fromPot: fromPot);
}
