import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/pages/achievements_page.dart';
import 'package:namer_app/pages/card_design_page.dart';
import 'package:namer_app/pages/wrapped_page.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:namer_app/services/achievements.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/games_service.dart';
import 'package:namer_app/services/leaderboard_service.dart';
import 'package:namer_app/ui/game_level.dart';
import 'package:namer_app/ui/responsive.dart';

/// Everything you've earned, in one place: your level, streak, badges,
/// card finishes and Monthly Wrapped (they used to be four rows in
/// Profile).
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  late final Stream<GamesProgress> _games = GamesService.watch(_uid);
  late final Stream<Map<String, dynamic>?> _user = BalanceService.db
      .collection('users')
      .doc(_uid)
      .snapshots()
      .map((d) => d.data());
  late final Stream<Map<String, dynamic>?> _badges =
      AchievementService.streamUserAchievements(_uid).map((d) => d.data());
  late final Future<int> _streak = LeaderboardService.streakFor(_uid)
      .then((r) => r.current)
      .catchError((_) => 0);

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Progress')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            children: [
              StreamBuilder<GamesProgress>(
                stream: _games,
                builder: (context, snap) =>
                    LevelCard(progress: snap.data ?? const GamesProgress()),
              ),
              const SizedBox(height: 12),
              StreamBuilder<Map<String, dynamic>?>(
                stream: _user,
                builder: (context, snap) {
                  final user = snap.data;
                  final best =
                      (BalanceService.number(user?['best_streak']) ?? 0)
                          .round();
                  final sense = CalorieSense.thisMonth(user);
                  return Row(
                    children: [
                      Expanded(
                        child: FutureBuilder<int>(
                          future: _streak,
                          builder: (context, s) => _Stat(
                            emoji: '🔥',
                            value: s.hasData ? '${s.data}' : '…',
                            label: best > 0
                                ? 'day streak · best $best'
                                : 'day streak',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Stat(
                          emoji: '🎯',
                          value: sense.count == 0
                              ? '–'
                              : '${sense.average.round()}%',
                          label: sense.count == 0
                              ? 'calorie sense: play the Daily Quiz'
                              : 'calorie sense this month',
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              StreamBuilder<Map<String, dynamic>?>(
                stream: _badges,
                builder: (context, snap) {
                  final data = snap.data ?? const {};
                  final got = Achievements.all
                      .where((a) => data[a.id] == true)
                      .length;
                  return _Row(
                    icon: Icons.emoji_events,
                    color: AppText.amber600,
                    title: 'Badges',
                    subtitle:
                        '$got of ${Achievements.all.length} unlocked',
                    onTap: () => _open(const AchievementsPage()),
                  );
                },
              ),
              _Row(
                icon: Icons.credit_card,
                color: AppText.violet,
                title: 'Card finishes',
                subtitle: 'New looks for your card, unlocked as you go',
                onTap: () => _open(const CardDesignPage()),
              ),
              _Row(
                icon: Icons.auto_graph,
                color: AppText.violet600,
                title: 'Monthly Wrapped',
                subtitle: 'Your month in review, ready to share',
                onTap: () => _open(const WrappedPage()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;

  const _Stat({required this.emoji, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: AppDecor.card,
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  label,
                  maxLines: 2,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.ink)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
