import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/chat_service.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/wrapped_service.dart';
import 'package:namer_app/ui/responsive.dart';
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

  void _shiftMonth(int delta) {
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
    final friends = await FriendsService.load(_user.uid).catchError(
        (_) => <Friend>[]);
    if (!mounted) return;
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
          myName: FriendsService.displayName(_user.email),
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
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => _shiftMonth(-1),
                    icon: const Icon(Icons.chevron_left),
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
                const Center(child: Text("Couldn't load this month."))
              else if (wrap == null)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (wrap.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                    child: Text('Nothing logged this month yet.',
                        style: TextStyle(color: AppColors.muted)),
                  ),
                )
              else ...[
                _WrapCard(wrap: wrap),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _share(wrap),
                  icon: const Icon(Icons.ios_share),
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
              stat('🍽️', '${wrap.averageCalories.round()}', 'avg kcal/day'),
              stat('💪', '${wrap.totalProtein.round()}g', 'protein'),
              stat(
                  '🎯',
                  wrap.senseGuesses > 0
                      ? '${wrap.calorieSense.round()}%'
                      : '–',
                  'calorie sense'),
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
