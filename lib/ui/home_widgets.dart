import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/services/balance_service.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Previous / next day arrows with the date in the middle (tap it for a
/// calendar). Can't go past today.
class DayStepper extends StatelessWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;
  final DateTime firstDate;

  DayStepper({
    super.key,
    required this.selected,
    required this.onChanged,
    DateTime? firstDate,
  }) : firstDate = firstDate ?? DateTime(2020, 1, 1);

  String _label(DateTime d) {
    final now = BalanceService.now();
    if (_sameDay(d, now)) return 'Today';
    if (_sameDay(d, BalanceService.addDays(now, -1))) {
      return 'Yesterday';
    }
    final year = d.year == now.year ? '' : ' ${d.year}';
    return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}$year';
  }

  @override
  Widget build(BuildContext context) {
    final now = BalanceService.now();
    final day = DateTime(selected.year, selected.month, selected.day);
    final canGoForward = !_sameDay(day, now) && day.isBefore(now);
    final canGoBack = day.isAfter(firstDate);

    Widget arrow(IconData icon, String tip, bool enabled, int delta) =>
        IconButton(
          tooltip: tip,
          onPressed: enabled
              ? () => onChanged(BalanceService.addDays(day, delta))
              : null,
          icon: Icon(icon),
          color: AppColors.primary,
          disabledColor: AppColors.border,
        );

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          arrow(Icons.chevron_left_rounded, 'Previous day', canGoBack, -1),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: day,
                  firstDate: firstDate,
                  lastDate: now,
                );
                if (picked != null) onChanged(picked);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 16, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Text(
                    _label(day),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          arrow(Icons.chevron_right_rounded, 'Next day', canGoForward, 1),
        ],
      ),
    );
  }
}

/// Equal-width meal tabs (Brekkie / Lunch / Dinner / Snacks).
class MealTabs extends StatelessWidget {
  final List<String> meals;
  final String selected;
  final ValueChanged<String> onSelected;

  /// Calories logged per meal, shown under each label. Empty hides them.
  final Map<String, int> totals;

  const MealTabs({
    super.key,
    required this.meals,
    required this.selected,
    required this.onSelected,
    this.totals = const {},
  });

  IconData _icon(String meal) {
    switch (meal.toLowerCase()) {
      case 'brekkie':
      case 'breakfast':
        return Icons.free_breakfast_outlined;
      case 'lunch':
        return Icons.lunch_dining_outlined;
      case 'dinner':
        return Icons.dinner_dining_outlined;
      default:
        return Icons.cookie_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final meal in meals)
            Expanded(
              child: Semantics(
                selected: meal == selected,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelected(meal),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: meal == selected
                          ? AppColors.primaryDark
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _icon(meal),
                          size: 18,
                          color: meal == selected
                              ? Colors.white
                              : AppColors.muted,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meal,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: meal == selected
                                ? Colors.white
                                : AppColors.muted,
                          ),
                        ),
                        if (totals.isNotEmpty)
                          Text(
                            (totals[meal] ?? 0) > 0
                                ? '${totals[meal]} kcal'
                                : '–',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: meal == selected
                                  ? AppColors.indigo100
                                  : AppColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
