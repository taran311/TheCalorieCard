import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/statement_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/statement_widgets.dart';

/// Keeps a weekly [Statement] fresh: reloads whenever the card balance
/// changes (i.e. food was added or removed anywhere in the app).
class LiveStatement extends StatefulWidget {
  final String userId;
  final int days;
  final Widget Function(BuildContext context, Statement? statement) builder;

  /// Shown instead of [builder] when the first load fails (there's nothing
  /// to show yet). [retry] loads again. Without it, [builder] keeps
  /// getting a null statement.
  final Widget Function(BuildContext context, VoidCallback retry)? onError;

  const LiveStatement({
    super.key,
    required this.userId,
    required this.builder,
    this.days = 7,
    this.onError,
  });

  @override
  State<LiveStatement> createState() => _LiveStatementState();
}

class _LiveStatementState extends State<LiveStatement> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  Statement? _statement;
  bool _failed = false;
  Timer? _debounce;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('user_data')
        .where('user_id', isEqualTo: widget.userId)
        .limit(1)
        .snapshots()
        .listen((_) => _scheduleReload(), onError: (_) {});
    _reload();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _reload);
  }

  Future<void> _reload() async {
    final token = ++_loadToken;
    try {
      final s = await StatementService.load(widget.userId, days: widget.days);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _statement = s;
        _failed = false;
      });
    } catch (_) {
      // Keep showing the last good statement; only flag a failure when
      // there's nothing to show.
      if (!mounted || token != _loadToken) return;
      if (_statement == null) setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _reload();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onError = widget.onError;
    if (_failed && _statement == null && onError != null) {
      return onError(context, _retry);
    }
    return widget.builder(context, _statement);
  }
}

/// Right-hand column on wide desktop screens: today's balance, the week's
/// spending and the latest transactions.
class TodayPanel extends StatelessWidget {
  final String userId;
  final VoidCallback? onOpenStatement;

  const TodayPanel({super.key, required this.userId, this.onOpenStatement});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 24, 24, 24),
      children: [
        PanelCard(
          title: 'Today',
          child: LiveBalanceSummary(userId: userId),
        ),
        const SizedBox(height: 16),
        LiveStatement(
          userId: userId,
          onError: (context, retry) => PanelCard(
            title: 'This week',
            child: SizedBox(
              height: 160,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Couldn't load this week.",
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: retry,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          builder: (context, statement) {
            if (statement == null) {
              return const PanelCard(
                title: 'This week',
                child: SizedBox(
                  height: 160,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final recent = statement.recent.take(6).toList();
            return Column(
              children: [
                PanelCard(
                  title: 'This week',
                  trailing: Text(
                    'avg ${formatKcal(statement.averageCalories)} kcal',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WeeklySpendChart(statement: statement),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const BudgetLegend(),
                          const Spacer(),
                          Text(
                            '${formatDays(statement.daysUnderBudget)} on budget',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              // Darker than the chart's green: it's text.
                              color: AppText.emerald700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PanelCard(
                  title: 'Recent transactions',
                  trailing: onOpenStatement == null
                      ? null
                      : TextButton(
                          onPressed: onOpenStatement,
                          child: const Text('Statement'),
                        ),
                  child: recent.isEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Nothing logged this week yet.',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                      : Column(
                          children: [
                            for (final tx in recent) TransactionTile(tx: tx),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
