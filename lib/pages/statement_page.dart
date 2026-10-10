import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/ui/shell_back.dart';
import 'package:namer_app/services/spend_category.dart';
import 'package:namer_app/services/statement_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/share_to_chat_sheet.dart';
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
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  /// Full days only, so it doesn't change during the day: loaded once.
  late Future<WeekDigest>? _digest =
      _uid == null ? null : StatementService.weekDigest(_uid!);

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: ShellBack.button(context),
        title: const Text('Statement'),
      ),
      body: uid == null
          ? const Center(child: Text('Please sign in'))
          : LiveStatement(
              key: ValueKey(_days),
              userId: uid,
              days: _days,
              onError: (context, retry) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off,
                          size: 40, color: AppColors.muted),
                      const SizedBox(height: 12),
                      Text(
                        "Couldn't load your statement.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: retry,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
              builder: (context, statement) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
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
                    if (_digest != null)
                      _WeekDigestCard(
                        digest: _digest!,
                        onRetry: () => setState(() {
                          _digest = StatementService.weekDigest(uid);
                        }),
                      ),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            WeeklySpendChart(
                              statement: statement,
                              height: 150,
                            ),
                            if ((statement.dailyBudget ?? 0) > 0) ...[
                              const SizedBox(height: 10),
                              const BudgetLegend(),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      PanelCard(
                        title: 'Where it went',
                        child: _WhereItWent(statement: statement),
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
      return [
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
            trailing: _DayTotal(day: d, fallbackBudget: budget),
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
  final DaySummary day;
  final double? fallbackBudget;

  const _DayTotal({required this.day, required this.fallbackBudget});

  @override
  Widget build(BuildContext context) {
    final spent = day.calories;
    final onBudget = day.onBudget(fallbackBudget);
    final budget = day.budget(fallbackBudget);
    // A finished day shows what was left on the card when it closed (pot
    // top-ups included), the same figure Hiscores judge it by.
    final closing = day.finished ? day.closingBalance : null;
    final left = closing ?? (budget == null ? null : budget - spent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${formatKcal(spent)} kcal',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        if (left != null && onBudget != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (onBudget ? AppColors.green : AppColors.red)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              onBudget
                  ? '${formatKcal(left.abs())} left'
                  : '${formatKcal(left.abs())} over',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: onBudget ? AppText.emerald700 : AppText.red600,
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
    final average = _Stat(
      label: 'Daily average',
      value: '${formatKcal(statement.averageCalories)} kcal',
    );
    final onBudget = _Stat(
      label: 'On budget',
      value: formatDays(statement.daysUnderBudget),
      color: AppText.emerald700,
    );
    final daysLogged = _Stat(
      label: 'Days logged',
      value: '${logged.length}/${statement.days.length}',
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Three across gets cramped on small phones: two, then one.
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: average),
                  const SizedBox(width: 12),
                  Expanded(child: onBudget),
                ],
              ),
              const SizedBox(height: 12),
              daysLogged,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: average),
            const SizedBox(width: 12),
            Expanded(child: onBudget),
            const SizedBox(width: 12),
            Expanded(child: daysLogged),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Stat({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color ?? AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spending categories, like a banking app's "where your money went".
class _WhereItWent extends StatelessWidget {
  final Statement statement;

  const _WhereItWent({required this.statement});

  @override
  Widget build(BuildContext context) {
    final rows = SpendInsights.breakdown([
      for (final tx in statement.recent)
        (description: tx.description, isRecipe: false, calories: tx.calories)
    ]);
    if (rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Log some food to see where your calories go.',
            style: TextStyle(color: AppColors.muted)),
      );
    }
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: r.category.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(r.category.icon,
                      size: 18, color: r.category.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(r.category.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                          Text('${formatKcal(r.calories)} kcal',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: r.share.clamp(0.0, 1.0).toDouble(),
                          minHeight: 6,
                          backgroundColor: AppColors.border,
                          valueColor:
                              AlwaysStoppedAnimation(r.category.color),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${(r.share * 100).round()}% · ${r.count} item${r.count == 1 ? '' : 's'}',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Your week": the last 7 full days against the 7 before, with a button
/// to share it in chat.
class _WeekDigestCard extends StatelessWidget {
  final Future<WeekDigest> digest;
  final VoidCallback onRetry;

  const _WeekDigestCard({required this.digest, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeekDigest>(
      future: digest,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: PanelCard(
              title: 'Your week',
              trailing: TextButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
              child: Text(
                "Couldn't load your week.",
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          );
        }
        final d = snap.data;
        // Quietly skip it until it's loaded, and for brand-new accounts.
        if (d == null || d.isEmpty) return const SizedBox.shrink();
        final t = d.thisWeek, l = d.lastWeek;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: PanelCard(
            title: 'Your week',
            trailing: Text(
              'vs the week before',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DigestRow(
                  label: 'Days on budget',
                  value: '${t.daysOnBudget}',
                  now: t.daysOnBudget,
                  before: l.daysOnBudget,
                  upIsGood: true,
                ),
                _DigestRow(
                  label: 'Finished days',
                  value: '${t.finishedDays}',
                  now: t.finishedDays,
                  before: l.finishedDays,
                  upIsGood: true,
                ),
                _DigestRow(
                  label: 'Average a day',
                  value: '${formatKcal(t.averageCalories)} kcal',
                  now: t.averageCalories,
                  before: l.averageCalories,
                ),
                _DigestRow(
                  label: 'Protein a day',
                  value: '${t.averageProtein.round()}g',
                  now: t.averageProtein,
                  before: l.averageProtein,
                  unit: 'g',
                  upIsGood: true,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => shareToChat(context,
                        text: d.toShareText(), title: 'Share your week'),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Share to a friend or group'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DigestRow extends StatelessWidget {
  final String label;
  final String value;
  final num now;
  final num before;
  final String unit;

  /// Up is shown in green when true. Calories have no "good" direction
  /// (it depends on your goal), so they stay neutral.
  final bool upIsGood;

  const _DigestRow({
    required this.label,
    required this.value,
    required this.now,
    required this.before,
    this.unit = '',
    this.upIsGood = false,
  });

  @override
  Widget build(BuildContext context) {
    final diff = (now - before).round();
    final change = WeekDigest.change(now, before, unit: unit);
    final Color color;
    if (diff == 0 || !upIsGood) {
      color = AppColors.muted;
    } else {
      color = diff > 0 ? AppText.emerald700 : AppText.amber700;
    }
    final spoken = diff == 0
        ? 'same as the week before'
        : '${diff > 0 ? 'up' : 'down'} ${diff.abs()}$unit on the week before';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Semantics(
        label: '$label: $value, $spoken',
        excludeSemantics: true,
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 14, color: AppColors.gray700)),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: Text(
                change,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
