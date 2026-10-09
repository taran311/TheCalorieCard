import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/statement_service.dart';
import 'package:namer_app/ui/responsive.dart';

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String formatKcal(double v) {
  final n = v.round();
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$buf';
}

String formatDayHeading(DateTime day) {
  final now = BalanceService.now();
  final d = DateTime(day.year, day.month, day.day);
  // Compare calendar dates (not hours), so clock changes can't mislabel.
  if (BalanceService.sameDay(d, now)) return 'Today';
  if (BalanceService.sameDay(d, BalanceService.addDays(now, -1))) {
    return 'Yesterday';
  }
  return '${_weekdayShort[d.weekday - 1]} ${d.day} ${_monthShort[d.month - 1]}';
}

String formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// A white rounded panel used for dashboard sections.
class PanelCard extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const PanelCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// Live remaining balance (calories + macros) from the user's card.
class LiveBalanceSummary extends StatelessWidget {
  final String userId;

  const LiveBalanceSummary({super.key, required this.userId});

  double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final data = docs.first.data();
        final goal = BalanceService.calorieGoalFrom(data) ?? 0;
        final remaining = _num(data['calories']) ?? goal;
        final spent = (goal - remaining).clamp(0, double.infinity).toDouble();
        final over = remaining < 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              over ? 'Over budget by' : 'Left to spend today',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatKcal(remaining.abs()),
                  style: TextStyle(
                    fontSize: 34,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: over ? AppColors.red : AppColors.ink,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 3),
                  child: Text('kcal',
                      style: TextStyle(color: AppColors.muted, fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ProgressBar(
              value: goal <= 0 ? 0 : spent / goal,
              color: over ? AppColors.red : AppColors.primary,
            ),
            const SizedBox(height: 6),
            Text(
              '${formatKcal(spent)} of ${formatKcal(goal)} kcal spent',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _MacroRow(
              label: 'Protein',
              color: AppColors.protein,
              remaining: _num(data['protein_balance']) ?? 0,
              goal: _num(data['protein_goal']) ?? 0,
            ),
            _MacroRow(
              label: 'Carbs',
              color: AppColors.carbs,
              remaining: _num(data['carbs_balance']) ?? 0,
              goal: _num(data['carbs_goal']) ?? 0,
            ),
            _MacroRow(
              label: 'Fat',
              color: AppColors.fat,
              remaining: _num(data['fats_balance']) ?? 0,
              goal: _num(data['fats_goal']) ?? 0,
            ),
          ],
        );
      },
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final Color color;
  final double remaining;
  final double goal;

  const _MacroRow({
    required this.label,
    required this.color,
    required this.remaining,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    final used = (goal - remaining).clamp(0, double.infinity).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                remaining >= 0
                    ? '${remaining.round()}g left'
                    : '${remaining.abs().round()}g over',
                style: TextStyle(
                  fontSize: 12,
                  color: remaining >= 0 ? AppColors.muted : AppColors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          _ProgressBar(value: goal <= 0 ? 0 : used / goal, color: color),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  final Color color;

  const _ProgressBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: value.isNaN ? 0 : value.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: color.withValues(alpha: 0.12),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

/// Seven bars, one per day, with the daily budget drawn as a line.
class WeeklySpendChart extends StatelessWidget {
  final Statement statement;
  final double height;

  const WeeklySpendChart({
    super.key,
    required this.statement,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    final budget = statement.dailyBudget ?? 0;
    final maxDay = statement.days
        .fold<double>(0, (m, d) => d.calories > m ? d.calories : m);
    final top = [budget * 1.15, maxDay * 1.05, 1.0]
        .reduce((a, b) => a > b ? a : b);
    final todayKey = BalanceService.dateKey(BalanceService.now());
    final dense = statement.days.length > 14;
    final gap = dense ? 1.5 : 5.0;

    return SizedBox(
      height: height + 22,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final budgetY = budget <= 0 ? null : height * (1 - budget / top);
          return Stack(
            children: [
              Positioned.fill(
                bottom: 22,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final d in statement.days)
                      Expanded(
                        child: Tooltip(
                          message:
                              '${formatDayHeading(d.day)}: ${formatKcal(d.calories)} kcal',
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: gap),
                            child: Container(
                              height: d.calories <= 0
                                  ? 3
                                  : (height * d.calories / top)
                                      .clamp(3.0, height),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: d.calories <= 0
                                    ? AppColors.border
                                    : (budget > 0 && d.calories > budget)
                                        ? AppColors.red.withValues(alpha: 0.85)
                                        : (BalanceService.dateKey(d.day) ==
                                                todayKey
                                            ? AppColors.primary
                                            : AppColors.primary
                                                .withValues(alpha: 0.55)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (budgetY != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: budgetY,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1.5,
                          color: AppColors.green.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 18,
                child: Row(
                  children: [
                    for (final d in statement.days)
                      Expanded(
                        child: Text(
                          dense
                              ? (d.day.weekday == DateTime.monday
                                  ? '${d.day.day}'
                                  : '')
                              : _weekdayShort[d.day.weekday - 1].substring(0, 1),
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                BalanceService.dateKey(d.day) == todayKey
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One food entry shown as a card transaction.
class TransactionTile extends StatelessWidget {
  final CardTransaction tx;
  final bool showTime;

  const TransactionTile({super.key, required this.tx, this.showTime = true});

  IconData get _icon {
    switch (tx.category.toLowerCase()) {
      case 'brekkie':
      case 'breakfast':
        return Icons.free_breakfast_outlined;
      case 'lunch':
        return Icons.lunch_dining_outlined;
      case 'dinner':
        return Icons.dinner_dining_outlined;
      case 'snacks':
      case 'snack':
        return Icons.cookie_outlined;
      default:
        return Icons.restaurant_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_icon, size: 19, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (showTime) formatTime(tx.time),
                    if (tx.category.isNotEmpty) tx.category,
                    '${tx.protein.round()}g protein · ${tx.carbs.round()}g carbs · ${tx.fat.round()}g fat',
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '-${formatKcal(tx.calories)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
