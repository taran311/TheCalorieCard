import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/statement_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/statement_widgets.dart';
import 'package:namer_app/ui/today_panel.dart';

/// A bank-style statement of everything spent from the calorie card.
class StatementPage extends StatefulWidget {
  const StatementPage({super.key});

  @override
  State<StatementPage> createState() => _StatementPageState();
}

class _StatementPageState extends State<StatementPage> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Statement')),
      body: uid == null
          ? const Center(child: Text('Please sign in'))
          : LiveStatement(
              key: ValueKey(_days),
              userId: uid,
              days: _days,
              builder: (context, statement) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 7, label: Text('7 days')),
                          ButtonSegment(value: 14, label: Text('14 days')),
                          ButtonSegment(value: 30, label: Text('30 days')),
                        ],
                        selected: {_days},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            setState(() => _days = s.first),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (statement == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      _SummaryRow(statement: statement),
                      const SizedBox(height: 16),
                      PanelCard(
                        title: 'Spending',
                        child: WeeklySpendChart(
                          statement: statement,
                          height: 150,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._buildDays(statement),
                    ],
                  ],
                );
              },
            ),
    );
  }

  List<Widget> _buildDays(Statement statement) {
    final budget = statement.dailyBudget;
    final days = statement.days.reversed
        .where((d) => d.transactions.isNotEmpty)
        .toList();

    if (days.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              'No transactions in this period.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ),
      ];
    }

    return [
      for (final d in days)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PanelCard(
            title: formatDayHeading(d.day),
            trailing: _DayTotal(spent: d.calories, budget: budget),
            child: Column(
              children: [
                for (final tx in d.transactions) TransactionTile(tx: tx),
              ],
            ),
          ),
        ),
    ];
  }
}

class _DayTotal extends StatelessWidget {
  final double spent;
  final double? budget;

  const _DayTotal({required this.spent, required this.budget});

  @override
  Widget build(BuildContext context) {
    final over = budget != null && spent > budget!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${formatKcal(spent)} kcal',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        if (budget != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (over ? AppColors.red : AppColors.green)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              over
                  ? '+${formatKcal(spent - budget!)}'
                  : '${formatKcal(budget! - spent)} left',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: over ? AppColors.red : AppColors.green,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final Statement statement;

  const _SummaryRow({required this.statement});

  @override
  Widget build(BuildContext context) {
    final logged = statement.days.where((d) => d.transactions.isNotEmpty);
    return Row(
      children: [
        Expanded(
          child: _Stat(
            label: 'Daily average',
            value: '${formatKcal(statement.averageCalories)} kcal',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Stat(
            label: 'On budget',
            value: '${statement.daysUnderBudget} days',
            color: AppColors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Stat(
            label: 'Days logged',
            value: '${logged.length}/${statement.days.length}',
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Stat({
    required this.label,
    required this.value,
    this.color = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
