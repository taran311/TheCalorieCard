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
          color: AppText.primary,
          disabledColor: AppColors.border,
        );

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                  Icon(Icons.calendar_today_rounded,
                      size: 16, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _label(day),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
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

/// One line of macros, each in its own colour: "P 20 · C 35 · F 8".
/// Replaces three stacked tiny lines, so it reads at a glance.
class MacroText extends StatelessWidget {
  final double protein;
  final double carbs;
  final double fat;
  final double fontSize;

  const MacroText({
    super.key,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.fontSize = 12,
  });

  static String _g(double v) => v.isFinite ? '${v.round()}' : '0';

  @override
  Widget build(BuildContext context) {
    final dot = TextSpan(
      text: ' · ',
      style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500),
    );
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: 'P ${_g(protein)}',
            style: TextStyle(color: AppColors.proteinText)),
        dot,
        TextSpan(
            text: 'C ${_g(carbs)}',
            style: TextStyle(color: AppColors.carbsText)),
        dot,
        TextSpan(
            text: 'F ${_g(fat)}', style: TextStyle(color: AppColors.fatText)),
      ]),
      semanticsLabel: '${_g(protein)} grams protein, ${_g(carbs)} grams '
          'carbs, ${_g(fat)} grams fat',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Small "est." mark on a food whose calories were estimated by AI.
class EstimateMark extends StatelessWidget {
  const EstimateMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'AI estimate — tap to check',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.amber100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded,
                size: 12, color: AppText.amber700),
            const SizedBox(width: 3),
            Text(
              'est.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppText.amber800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
