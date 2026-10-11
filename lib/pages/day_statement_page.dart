import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/statement_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/statement_widgets.dart';

/// One day of the statement: its total against the budget and every food,
/// opened from the calendar or a search result.
class DayStatementPage extends StatefulWidget {
  final String userId;
  final DateTime day;

  /// The day when the caller already has it (the calendar does); otherwise
  /// it's loaded, with its `daily_logs` snapshot, so it's judged exactly as
  /// on the statement.
  final DaySummary? initial;
  final double? fallbackBudget;

  const DayStatementPage({
    super.key,
    required this.userId,
    required this.day,
    this.initial,
    this.fallbackBudget,
  });

  @override
  State<DayStatementPage> createState() => _DayStatementPageState();
}

class _DayStatementPageState extends State<DayStatementPage> {
  late Future<Statement>? _load = widget.initial == null ? _fetch() : null;

  Future<Statement> _fetch() {
    final start = BalanceService.startOfDay(widget.day);
    return StatementService.loadRange(
        widget.userId, start, BalanceService.addDays(start, 1));
  }

  Widget _content(DaySummary d, double? fallback) {
    final macros = '${d.protein.round()}g protein · ${d.carbs.round()}g carbs'
        ' · ${d.fat.round()}g fat';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: Breakpoints.contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d.restDay)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '🏖️ Rest day',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                PanelCard(
                  title: formatDayHeading(d.day),
                  trailing: DayTotalChip(day: d, fallbackBudget: fallback),
                  child: d.transactions.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Nothing logged on this day.',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final tx in d.transactions)
                              TransactionTile(tx: tx),
                            const SizedBox(height: 8),
                            Text(
                              macros,
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.muted),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(formatDayShort(widget.day))),
      body: initial != null
          ? _content(initial, widget.fallbackBudget)
          : FutureBuilder<Statement>(
              future: _load,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Couldn't load this day.",
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setState(() => _load = _fetch()),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  );
                }
                final s = snap.data;
                if (s == null || s.days.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _content(s.days.first, s.dailyBudget);
              },
            ),
    );
  }
}
