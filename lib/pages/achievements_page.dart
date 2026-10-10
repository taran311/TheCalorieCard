import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:namer_app/services/achievements.dart';
import 'package:namer_app/ui/responsive.dart';

/// Achievements: grouped by category, with tiers, points and progress.
///
/// Your own page re-checks everything when it opens. A friend's page
/// ([userIdOverride]) shows what they've unlocked and their last progress.
class AchievementsPage extends StatefulWidget {
  final String? userIdOverride;
  final String? titleOverride;

  const AchievementsPage({
    super.key,
    this.userIdOverride,
    this.titleOverride,
  });

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

enum _Filter { all, unlocked, locked }

class _AchievementsPageState extends State<AchievementsPage> {
  late final String? _uid =
      widget.userIdOverride ?? FirebaseAuth.instance.currentUser?.uid;
  late final bool _isMe = widget.userIdOverride == null ||
      widget.userIdOverride == FirebaseAuth.instance.currentUser?.uid;
  late Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream = _open();

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _open() =>
      _uid == null ? null : AchievementService.streamUserAchievements(_uid!);

  void _retry() {
    setState(() => _stream = _open());
    if (_isMe && _uid != null) _check();
  }

  bool _checking = false;
  List<Achievement> _justUnlocked = const [];
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    if (_isMe && _uid != null) _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final fresh = await AchievementService.evaluate(_uid!);
      if (mounted) setState(() => _justUnlocked = fresh);
    } catch (_) {
      // Shows the last saved progress instead.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(widget.titleOverride ?? 'Achievements',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_isMe)
            IconButton(
              tooltip: 'Check again',
              onPressed: _checking ? null : _check,
              icon: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
        ],
      ),
      body: _stream == null
          ? const Center(child: Text('Please sign in'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Couldn't load achievements.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _retry,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _buildList(snap.data!.data() ?? const {});
              },
            ),
    );
  }

  Widget _buildList(Map<String, dynamic> data) {
    bool isUnlocked(Achievement a) => data[a.id] == true;
    final progress = (data['progress'] as Map?) ?? const {};
    int progressOf(Achievement a) {
      final v = progress[a.id];
      return v is num ? v.round() : 0;
    }

    DateTime? unlockedAt(Achievement a) {
      final v = data['${a.id}_unlocked_at'];
      return v is Timestamp ? v.toDate() : null;
    }

    final unlocked = Achievements.all.where(isUnlocked).toList();
    final points = unlocked.fold<int>(0, (s, a) => s + a.tier.points);

    bool show(Achievement a) => switch (_filter) {
          _Filter.all => true,
          _Filter.unlocked => isUnlocked(a),
          _Filter.locked => !isUnlocked(a),
        };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Breakpoints.contentMaxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          children: [
            _Summary(
              unlocked: unlocked.length,
              total: Achievements.all.length,
              points: points,
              totalPoints: Achievements.totalPoints,
              tierCounts: {
                for (final t in AchievementTier.values)
                  t: unlocked.where((a) => a.tier == t).length
              },
            ),
            if (_justUnlocked.isNotEmpty) ...[
              const SizedBox(height: 12),
              _JustUnlocked(achievements: _justUnlocked),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final f in _Filter.values)
                  ChoiceChip(
                    label: Text(switch (f) {
                      _Filter.all => 'All',
                      _Filter.unlocked => 'Unlocked',
                      _Filter.locked => 'To do',
                    }),
                    selected: _filter == f,
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: _filter == f ? Colors.white : AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
            for (final category in AchievementCategory.values)
              ..._section(category, show, isUnlocked, progressOf, unlockedAt),
          ],
        ),
      ),
    );
  }

  /// One category: a header with its count, then its achievements.
  List<Widget> _section(
    AchievementCategory category,
    bool Function(Achievement) show,
    bool Function(Achievement) isUnlocked,
    int Function(Achievement) progressOf,
    DateTime? Function(Achievement) unlockedAt,
  ) {
    final all = Achievements.all.where((a) => a.category == category).toList();
    final items = all.where(show).toList();
    if (items.isEmpty) return const <Widget>[];
    final done = all.where(isUnlocked).length;
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(
          children: [
            Text('${category.emoji}  ${category.label}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            const Spacer(),
            Text('$done / ${all.length}',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.muted)),
          ],
        ),
      ),
      for (final a in items)
        _AchievementTile(
          achievement: a,
          unlocked: isUnlocked(a),
          progress: progressOf(a),
          unlockedAt: unlockedAt(a),
        ),
    ];
  }
}

class _Summary extends StatelessWidget {
  final int unlocked;
  final int total;
  final int points;
  final int totalPoints;
  final Map<AchievementTier, int> tierCounts;

  const _Summary({
    required this.unlocked,
    required this.total,
    required this.points,
    required this.totalPoints,
    required this.tierCounts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$unlocked',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      height: 1)),
              Text(' / $total unlocked',
                  style: const TextStyle(color: Colors.white70, fontSize: 15)),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$points',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  Text('of $totalPoints pts',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : unlocked / total,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final t in AchievementTier.values)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: t.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text('${t.label} ${tierCounts[t] ?? 0}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JustUnlocked extends StatelessWidget {
  final List<Achievement> achievements;

  const _JustUnlocked({required this.achievements});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amber50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.amber300),
      ),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              achievements.length == 1
                  ? 'New: ${achievements.first.title}!'
                  : 'New: ${achievements.map((a) => a.title).join(', ')}!',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppText.amber700),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final Achievement achievement;
  final bool unlocked;
  final int progress;
  final DateTime? unlockedAt;

  const _AchievementTile({
    required this.achievement,
    required this.unlocked,
    required this.progress,
    required this.unlockedAt,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    final tierColor = a.tier.color;
    final shown = progress > a.target ? a.target : progress;
    final fraction = a.target <= 0 ? 0.0 : shown / a.target;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unlocked ? AppColors.surface : AppColors.gray50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unlocked ? tierColor.withValues(alpha: 0.6) : AppColors.border,
          width: unlocked ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unlocked
                  ? tierColor.withValues(alpha: 0.14)
                  : AppColors.border,
              border: Border.all(
                color: unlocked ? tierColor : AppColors.gray300,
                width: 2.5,
              ),
            ),
            child: Opacity(
              opacity: unlocked ? 1 : 0.35,
              child: Text(a.emoji, style: const TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: unlocked ? AppColors.ink : AppColors.gray600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: tierColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${a.tier.label} · ${a.tier.points}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: tierColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  a.description,
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                if (unlocked)
                  Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 16, color: AppText.green),
                      const SizedBox(width: 4),
                      Text(
                        unlockedAt == null
                            ? 'Unlocked'
                            : 'Unlocked ${_date(unlockedAt!)}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppText.emerald600),
                      ),
                    ],
                  )
                else if (a.target > 1)
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: fraction.clamp(0.0, 1.0).toDouble(),
                            minHeight: 6,
                            backgroundColor: AppColors.border,
                            valueColor: AlwaysStoppedAnimation(tierColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$shown / ${a.target}${a.unit.isEmpty ? '' : ' ${a.unit}'}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.gray600),
                      ),
                    ],
                  )
                else
                  Text(
                    'Locked',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
