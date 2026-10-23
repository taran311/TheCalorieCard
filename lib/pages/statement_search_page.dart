import 'package:flutter/material.dart';
import 'package:namer_app/pages/day_statement_page.dart';
import 'package:namer_app/services/statement_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/statement_widgets.dart';
import 'package:namer_app/ui/calorie_symbol.dart';

/// Search every food logged in the last year, like a bank's transaction
/// search. Results are grouped by day; tap one to open that day.
class StatementSearchPage extends StatefulWidget {
  final String userId;

  const StatementSearchPage({super.key, required this.userId});

  @override
  State<StatementSearchPage> createState() => _StatementSearchPageState();
}

class _StatementSearchPageState extends State<StatementSearchPage> {
  /// How far back search looks.
  static const days = 365;

  /// Matches shown at most (newest first), so a very common word stays quick.
  static const maxResults = 200;

  final _query = TextEditingController();

  /// The year's food is read once when search opens (just the foods, not
  /// the 365 daily snapshots); every search after that is instant.
  late Future<Statement> _history = _fetch();

  Future<Statement> _fetch() =>
      StatementService.load(widget.userId, days: days, withLogs: false);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _open(DateTime day) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DayStatementPage(userId: widget.userId, day: day),
    ));
  }

  Widget _message(String text, {IconData? icon}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 36, color: AppColors.muted),
              const SizedBox(height: 10),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(Statement statement) {
    final q = _query.text.trim();
    if (q.isEmpty) {
      return _message(
        'Search everything you\'ve logged in the last 12 months, '
        'e.g. "toast" or "oat latte".',
        icon: Icons.search,
      );
    }
    final found = statement.search(q);
    if (found.isEmpty) {
      return _message("No foods match '$q'", icon: Icons.search_off);
    }

    // Newest first, capped at [maxResults] foods.
    final groups = <DaySummary>[];
    var shown = 0;
    var total = 0;
    var totalKcal = 0.0;
    for (final d in found) {
      total += d.transactions.length;
      totalKcal += d.calories;
      if (shown >= maxResults) continue;
      final take = d.transactions.take(maxResults - shown).toList();
      shown += take.length;
      groups.add(DaySummary(d.day, take));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        Text(
          '${total == 1 ? '1 food' : '$total foods'} · '
          '$calSym${formatKcal(totalKcal)} in the last 12 months',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.gray700,
          ),
        ),
        if (total > shown)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Showing the $shown most recent.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
        const SizedBox(height: 12),
        for (final d in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Text(
              formatDayHeading(d.day),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ),
          Material(
            color: AppColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < d.transactions.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.border),
                  _ResultTile(
                    tx: d.transactions[i],
                    onTap: () => _open(d.day),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search your foods',
            border: InputBorder.none,
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_query.clear),
                  ),
          ),
        ),
      ),
      body: FutureBuilder<Statement>(
        future: _history,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Couldn't load your history.",
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _history = _fetch()),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            );
          }
          final s = snap.data;
          if (s == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _results(s);
        },
      ),
    );
  }
}

/// "Falafel wrap · 380 kcal · Lunch · Tue 3 Sep".
class _ResultTile extends StatelessWidget {
  final CardTransaction tx;
  final VoidCallback onTap;

  const _ResultTile({required this.tx, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final details = [
      formatKcal(tx.calories),
      if (tx.category.isNotEmpty) tx.category,
      formatDayShort(tx.time),
    ].join(' · ');
    return Semantics(
      button: true,
      label: '${tx.description}, $details. Open this day',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: AppColors.gray400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
