import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/direct_debit_service.dart';
import 'package:namer_app/services/split_service.dart';
import 'package:namer_app/ui/responsive.dart';

/// The Card screen's inbox, like a banking app's notification strip:
/// split-the-bill requests, direct debits due today, balance alerts, the
/// evening "finish your day" nudge and this week's pot.
///
/// Shows one item at a time (swipe for more) so the card stays the hero.
class HomeInbox extends StatefulWidget {
  final String userId;
  final bool isDayFinished;
  final bool hasFoodToday;
  final VoidCallback onFinishDay;

  /// Called after something here changed the balance without logging food
  /// (moving the pot onto the card).
  final VoidCallback onBalanceChanged;

  const HomeInbox({
    super.key,
    required this.userId,
    required this.isDayFinished,
    required this.hasFoodToday,
    required this.onFinishDay,
    required this.onBalanceChanged,
  });

  @override
  State<HomeInbox> createState() => _HomeInboxState();
}

class _HomeInboxState extends State<HomeInbox> {
  StreamSubscription<List<BillSplit>>? _splitSub;
  StreamSubscription<List<DirectDebit>>? _debitSub;
  StreamSubscription<dynamic>? _profileSub;

  List<BillSplit> _splits = const [];
  List<DirectDebit> _debits = const [];
  Map<String, dynamic>? _profile;
  final Set<String> _busy = {};
  final PageController _pages = PageController();
  int _page = 0;

  /// Rebuilds every minute so time-based items (the evening nudge, debits
  /// due after midnight) appear without waiting for another update.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _splitSub = SplitService.pendingFor(widget.userId).listen(
      (v) => setState(() => _splits = v),
      onError: (_) {},
    );
    _debitSub = DirectDebitService.forUser(widget.userId).listen(
      (v) => setState(() => _debits = v),
      onError: (_) {},
    );
    _profileSub = BalanceService.db
        .collection('user_data')
        .where('user_id', isEqualTo: widget.userId)
        .limit(1)
        .snapshots()
        .listen(
      (snap) => setState(
          () => _profile = snap.docs.isEmpty ? null : snap.docs.first.data()),
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _splitSub?.cancel();
    _debitSub?.cancel();
    _profileSub?.cancel();
    _clock?.cancel();
    _pages.dispose();
    super.dispose();
  }

  /// Runs an inbox action. If it returns false, it had already been
  /// handled (e.g. on another device), so say that instead of [done].
  Future<void> _run(String key, Future<Object?> Function() action,
      {String? done}) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      final result = await action();
      if (!mounted) return;
      final message = result == false ? 'Already done on another device' : done;
      if (message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  /// Inbox items. On [narrow] screens, cards with two buttons put the
  /// buttons on their own row under the text.
  List<_InboxCard> _items({bool narrow = false}) {
    final items = <_InboxCard>[];
    final uid = widget.userId;

    for (final split in _splits) {
      final key = 'split:${split.id}';
      items.add(_InboxCard(
        icon: Icons.receipt_long,
        color: AppColors.violet600,
        title: '${split.fromName} split ${split.title}',
        subtitle: 'Your share: ${split.calories.round()} kcal · ${split.meal}',
        busy: _busy.contains(key),
        actions: [
          _InboxAction('Decline', () => _run(key,
              () => SplitService.decline(uid, split))),
          _InboxAction('Accept', () => _run(key,
              () => SplitService.accept(uid, split),
              done: 'Added your share to ${split.meal}'), primary: true),
        ],
        stacked: narrow,
      ));
    }

    for (final debit in _debits.where((d) => d.isDueToday)) {
      final key = 'debit:${debit.id}';
      items.add(_InboxCard(
        icon: Icons.autorenew,
        color: AppColors.sky,
        title: 'Direct debit: ${debit.name}',
        subtitle: '${debit.macros.calories.round()} kcal · ${debit.meal}',
        busy: _busy.contains(key),
        actions: [
          _InboxAction('Skip today',
              () => _run(key, () => DirectDebitService.skipToday(debit))),
          _InboxAction(
              'Pay',
              () => _run(key, () => DirectDebitService.pay(uid, debit),
                  done: 'Logged ${debit.name}'),
              primary: true),
        ],
        stacked: narrow,
      ));
    }

    final profile = _profile;
    if (profile != null &&
        profile['balance_date'] == BalanceService.dateKey(BalanceService.now())) {
      final left = BalanceService.number(profile['calories']) ?? 0;
      final goal = BalanceService.calorieGoalFrom(profile) ?? 0;
      // Going over is handled by the Coach note under the card.
      if (left >= 0 && goal > 0 && left <= goal * 0.1 && widget.hasFoodToday) {
        items.add(_InboxCard(
          icon: Icons.battery_alert,
          color: AppColors.amber700,
          title: 'Low balance: ${left.round()} kcal left',
          subtitle: 'Nearly at your limit for today.',
        ));
      }

      final pot = BalanceService.potFrom(profile);
      if (pot > 0) {
        items.add(_InboxCard(
          icon: Icons.savings_outlined,
          color: AppColors.emerald600,
          title: 'Pot: ${pot.round()} kcal saved this week',
          subtitle: 'Move it onto today\'s card for a treat.',
          busy: _busy.contains('pot'),
          actions: [
            _InboxAction('Move to card', () => _run('pot', () async {
                  await BalanceService.spendPot(uid);
                  widget.onBalanceChanged();
                }, done: 'Pot moved onto your card'), primary: true),
          ],
        ));
      }
    }

    if (BalanceService.now().hour >= 20 &&
        !widget.isDayFinished &&
        widget.hasFoodToday) {
      items.add(_InboxCard(
        icon: Icons.nightlight_round,
        color: AppColors.indigo700,
        title: 'Finish your day?',
        subtitle: 'Finished days count towards streaks and challenges.',
        actions: [
          _InboxAction('Finish day', widget.onFinishDay, primary: true),
        ],
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (_items().isEmpty) return const SizedBox.shrink();
    // Grow with the text size so nothing is clipped.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final textHeight = 50 * scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 340;
        final items = _items(narrow: narrow);
        if (items.isEmpty) return const SizedBox.shrink();
        final page = _page.clamp(0, items.length - 1);
        final anyStacked = items.any((c) => c.stacked && c.actions.length > 1);
        final height = anyStacked
            ? 72 + textHeight
            : math.max(78.0, 22 + textHeight);

        return Column(
          children: [
            SizedBox(
              height: height,
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: items,
              ),
            ),
            if (items.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == page ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color:
                              i == page ? AppColors.primary : AppColors.gray300,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InboxAction {
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  const _InboxAction(this.label, this.onPressed, {this.primary = false});
}

class _InboxCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final List<_InboxAction> actions;
  final bool busy;

  /// Buttons on their own row under the text (narrow screens).
  final bool stacked;

  const _InboxCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.busy = false,
    this.stacked = false,
  });

  Widget _button(_InboxAction a) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: a.primary
          ? FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: a.onPressed,
              child: Text(a.label),
            )
          : TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: a.onPressed,
              child: Text(a.label),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const spinner = Padding(
      padding: EdgeInsets.all(10),
      child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2)),
    );
    final text = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: AppColors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
    final iconBadge = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );

    final Widget body;
    if (stacked && actions.length > 1) {
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              iconBadge,
              const SizedBox(width: 10),
              Expanded(child: text),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (busy) spinner else for (final a in actions) _button(a),
            ],
          ),
        ],
      );
    } else {
      body = Row(
        children: [
          iconBadge,
          const SizedBox(width: 10),
          Expanded(child: text),
          if (busy) spinner else for (final a in actions) _button(a),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: AppDecor.card,
      child: body,
    );
  }
}
