import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/ui/premium_sheet.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/chat_service.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/wrapped_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/statement_widgets.dart';
import 'package:namer_app/services/achievement_service.dart';

/// Monthly statement / "Wrapped": your month in review, shareable to chat.
class WrappedPage extends StatefulWidget {
  const WrappedPage({super.key});

  @override
  State<WrappedPage> createState() => _WrappedPageState();
}

class _WrappedPageState extends State<WrappedPage> {
  final User _user = FirebaseAuth.instance.currentUser!;
  late DateTime _month;
  late Future<MonthWrap> _wrap;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    final now = BalanceService.now();
    _month = DateTime(now.year, now.month, 1);
    _load();
  }

  void _load() {
    _wrap = WrappedService.load(_user.uid, _month);
  }

  /// True when the month before this one needs Premium (free: this month
  /// and last month).
  bool get _previousLocked {
    final now = BalanceService.now();
    final target = DateTime(_month.year, _month.month - 1, 1);
    final oldestFree = DateTime(now.year, now.month - 1, 1);
    return target.isBefore(oldestFree) && !Premium.isPremium;
  }

  void _shiftMonth(int delta) {
    // Free: this month and last month. Premium: every month.
    if (delta < 0 && _previousLocked) {
      showPremiumSheet(
        context,
        title: 'Older Wrapped is Premium',
        message: 'Look back at every month you\'ve logged: your best '
            'streaks, top foods and on-budget days, month by month.',
      );
      return;
    }
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _load();
    });
  }

  bool get _isCurrentMonth {
    final now = BalanceService.now();
    return _month.year == now.year && _month.month == now.month;
  }

  Future<void> _share(MonthWrap wrap) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final friends = await FriendsService.load(_user.uid).catchError(
        (_) => <Friend>[]);
    if (!mounted) return;
    setState(() => _sharing = false);
    final text = wrap.toShareText();
    final target = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy as text'),
              onTap: () => Navigator.pop(sheetContext, 'copy'),
            ),
            if (friends.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Send in chat to',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            for (final f in friends)
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(f.name),
                onTap: () => Navigator.pop(sheetContext, f),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    try {
      if (target == 'copy') {
        await Clipboard.setData(ClipboardData(text: text));
        AchievementService.bump(_user.uid, 'wrapped_shares');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard')));
        }
      } else if (target is Friend) {
        await ChatService.sendToFriend(
          uid: _user.uid,
          myName: await FriendsService.nameFor(_user.uid, email: _user.email),
          friendId: target.id,
          friendName: target.name,
          text: text,
        );
        AchievementService.bump(_user.uid, 'wrapped_shares');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Sent to ${target.name}')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't share that. Try again.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Monthly Wrapped')),
      body: FutureBuilder<MonthWrap>(
        future: _wrap,
        builder: (context, snap) {
          // While a new month loads, don't keep showing the old one.
          final loading = snap.connectionState != ConnectionState.done;
          final wrap = loading ? null : snap.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: _previousLocked
                        ? 'Previous month (Premium)'
                        : 'Previous month',
                    onPressed: () => _shiftMonth(-1),
                    icon: _previousLocked
                        ? const Badge(
                            label: Icon(Icons.lock, size: 10,
                                color: Colors.white),
                            backgroundColor: AppColors.violet600,
                            child: Icon(Icons.chevron_left),
                          )
                        : const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      MonthWrap.nameOf(_month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!loading && snap.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Column(
                    children: [
                      Text(
                        "Couldn't load this month.",
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => setState(_load),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                )
              else if (wrap == null)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (wrap.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Center(
                    child: Text(
                        _isCurrentMonth
                            ? 'Nothing logged this month yet.'
                            : 'Nothing logged in ${MonthWrap.nameOf(_month)}.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted)),
                  ),
                )
              else ...[
                _WrapCard(wrap: wrap),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _sharing ? null : () => _share(wrap),
                  icon: _sharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share),
                  label: const Text('Share'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WrapCard extends StatelessWidget {
  final MonthWrap wrap;

  const _WrapCard({required this.wrap});

  @override
  Widget build(BuildContext context) {
    Widget stat(String emoji, String value, String label) => Expanded(
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              Text(label,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your ${wrap.monthName}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(
            children: [
              stat('🗓️', '${wrap.daysLogged}', 'days logged'),
              stat('✅', '${wrap.onBudgetDays}', 'on budget'),
              stat('🔥', '${wrap.bestStreak}', 'best streak'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              stat('🍽️', formatKcal(wrap.averageCalories), 'avg kcal/day'),
              stat('💪', '${formatKcal(wrap.totalProtein)}g', 'protein'),
              stat(
                  '🎯',
                  wrap.senseGuesses > 0
                      ? '${wrap.calorieSense.round()}%'
                      : '–',
                  'guess accuracy'),
            ],
          ),
          if (wrap.topFoods.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Most logged',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (var i = 0; i < wrap.topFoods.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${i + 1}. ${wrap.topFoods[i].name}  ×${wrap.topFoods[i].count}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
          ],
          if (wrap.topCategory != null) ...[
            const SizedBox(height: 14),
            Text('Biggest spend: ${wrap.topCategory!.label}',
                style: const TextStyle(color: Colors.white70)),
          ],
        ],
      ),
    );
  }
}
