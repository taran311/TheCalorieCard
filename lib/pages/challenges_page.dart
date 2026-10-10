import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/challenge_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/ui/responsive.dart';

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  'Sunday'
];

/// 7-day challenges with friends, starting the day you make them:
/// head-to-head (most days on budget), early logger (most days logged
/// before 11am), or a team goal (finished days, or protein, between you).
/// Scores reward consistency, never eating less.
class ChallengesPage extends StatefulWidget {
  const ChallengesPage({super.key});

  @override
  State<ChallengesPage> createState() => _ChallengesPageState();
}

class _ChallengesPageState extends State<ChallengesPage> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  List<Friend> _friends = const [];
  bool _friendsFailed = false;

  /// Created once: building it in build() would re-subscribe every rebuild.
  late final Stream<List<Challenge>> _challenges =
      ChallengeService.forUser(_uid);

  /// Bumped to make every card fetch its scores again (pull to refresh, or
  /// food logged anywhere in the app).
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    _loadFriends();
    FoodLog.changed.addListener(_onFoodChanged);
  }

  @override
  void dispose() {
    FoodLog.changed.removeListener(_onFoodChanged);
    super.dispose();
  }

  void _onFoodChanged() {
    if (mounted) setState(() => _refreshTick++);
  }

  Future<void> _refresh() async {
    setState(() => _refreshTick++);
    _loadFriends();
    // Give the cards a moment to start their reloads.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  void _loadFriends() {
    FriendsService.load(_uid).then((f) {
      if (mounted) {
        setState(() {
          _friends = f;
          _friendsFailed = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _friendsFailed = true);
    });
  }

  /// Friends by their current name; anyone else by the name saved on the
  /// challenge when it was made.
  String _nameOf(Challenge c, String id) {
    if (id == _uid) return 'You';
    for (final f in _friends) {
      if (f.id == id) return f.name;
    }
    final saved = c.names[id];
    return saved == null || saved.isEmpty ? 'Friend' : saved;
  }

  Future<void> _create() async {
    if (_friends.isEmpty) {
      if (_friendsFailed) {
        _loadFriends();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't load your friends. Try again.")),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some friends to challenge first.')),
      );
      return;
    }
    final created = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _NewChallengeSheet(uid: _uid, friends: _friends),
    );
    if (created == true && mounted) {
      // Runs 7 days including today, so it ends the day before this
      // weekday next week.
      final last = BalanceService.addDays(
          BalanceService.now(), ChallengeService.lengthDays - 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Challenge on. It runs for 7 days, until '
                '${_weekdays[last.weekday - 1]}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Challenges'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'challenges-new',
        tooltip: 'New challenge',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Challenge>>(
        stream: _challenges,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text("Couldn't load challenges."));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return _EmptyChallenges(onCreate: _create);
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                for (final c in list)
                  _ChallengeCard(
                    key: ValueKey(c.id),
                    challenge: c,
                    uid: _uid,
                    refreshTick: _refreshTick,
                    nameOf: (id) => _nameOf(c, id),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptyChallenges extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyChallenges({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 64, color: AppColors.gray400),
            const SizedBox(height: 12),
            const Text('No challenges right now',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Start one today and it runs for 7 days: go head-to-head on '
              'days on budget, or set a team goal together.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('New challenge'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChallengeCard extends StatefulWidget {
  final Challenge challenge;
  final String uid;
  final String Function(String id) nameOf;

  /// Scores are fetched again whenever this changes.
  final int refreshTick;

  const _ChallengeCard({
    super.key,
    required this.challenge,
    required this.uid,
    required this.nameOf,
    this.refreshTick = 0,
  });

  @override
  State<_ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends State<_ChallengeCard> {
  late Future<List<ChallengeScore>> _scores =
      ChallengeService.scores(widget.challenge);

  @override
  void didUpdateWidget(covariant _ChallengeCard old) {
    super.didUpdateWidget(old);
    if (old.challenge.memberIds.length != widget.challenge.memberIds.length ||
        old.refreshTick != widget.refreshTick) {
      // The last scores stay on screen until the new ones arrive.
      final next = ChallengeService.scores(widget.challenge);
      next.then((v) {
        if (mounted) setState(() => _last = v);
      }, onError: (_) {});
      _scores = next;
    }
  }

  /// Most recent scores, shown while fresh ones load (no flicker).
  List<ChallengeScore>? _last;

  String _daysLeft() {
    final c = widget.challenge;
    if (c.isOver) return 'Finished';
    final today = BalanceService.startOfDay(BalanceService.now());
    var left = 0;
    for (var d = today; d.isBefore(c.end); d = BalanceService.addDays(d, 1)) {
      left++;
    }
    return left == 1 ? 'Last day' : '$left days left';
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave challenge?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Stay')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: AppText.red600),
              child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChallengeService.leave(widget.uid, widget.challenge);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't leave. Please try again.")),
        );
      }
    }
  }

  static String _grams(num g) {
    final n = g.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) buf.write(',');
      buf.write(n[i]);
    }
    return '${buf}g';
  }

  /// One person's score, in words.
  String _scoreText(ChallengeType type, ChallengeScore s) => switch (type) {
        ChallengeType.headToHead => '${s.onBudgetDays} on budget',
        ChallengeType.earlyLogger =>
          '${s.earlyDays} early ${s.earlyDays == 1 ? 'day' : 'days'}',
        ChallengeType.group => '${s.finishedDays}',
        ChallengeType.protein => _grams(s.protein),
      };

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    final emoji = switch (c.type) {
      ChallengeType.headToHead => '⚔️',
      ChallengeType.group => '🤝',
      ChallengeType.protein => '💪',
      ChallengeType.earlyLogger => '🌅',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(c.title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ),
              Text(_daysLeft(),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (_) => _leave(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'leave',
                    child: Text(
                      'Leave',
                      style: TextStyle(color: AppText.red600),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<ChallengeScore>>(
            future: _scores,
            builder: (context, snap) {
              // Keep showing the last scores while new ones load.
              final scores = snap.data ?? _last;
              if (scores == null) {
                if (snap.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text("Couldn't load scores. Pull down to try "
                        'again.'),
                  );
                }
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                );
              }
              return c.type.isTeam
                  ? _teamScores(c, scores)
                  : _ranking(c, scores);
            },
          ),
        ],
      ),
    );
  }

  /// Team goals: everyone's total against the target.
  Widget _teamScores(Challenge c, List<ChallengeScore> scores) {
    final isProtein = c.type == ChallengeType.protein;
    final total = scores.fold<num>(0, (s, e) => s + e.valueFor(c.type));
    final target = c.target <= 0 ? 1 : c.target;
    final done = total >= target;
    final String headline;
    if (isProtein) {
      headline = done
          ? '🎉 Goal reached: ${_grams(total)} of ${_grams(c.target)} protein'
          : '${_grams(total)} of ${_grams(c.target)} protein';
    } else {
      headline = done
          ? '🎉 Goal reached: ${total.round()} / ${c.target} days'
          : '${total.round()} / ${c.target} finished days';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline,
          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (total / target).clamp(0.0, 1.0).toDouble(),
            minHeight: 10,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(AppText.emerald600),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final s in scores)
              Chip(
                label: Text(
                    '${widget.nameOf(s.userId)} · ${_scoreText(c.type, s)}'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }

  /// Head-to-head and early logger: a ranking.
  Widget _ranking(Challenge c, List<ChallengeScore> scores) {
    num valueAt(int i) => scores[i].valueFor(c.type);
    final leader = scores.isEmpty ? 0 : valueAt(0);
    // Only crown an outright leader, not a tie.
    final outright =
        leader > 0 && (scores.length < 2 || valueAt(1) < leader);
    return Column(
      children: [
        for (var i = 0; i < scores.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    i == 0 && outright ? '👑' : '#${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.nameOf(scores[i].userId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontWeight: scores[i].userId == widget.uid
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  _scoreText(c.type, scores[i]),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NewChallengeSheet extends StatefulWidget {
  final String uid;
  final List<Friend> friends;

  const _NewChallengeSheet({required this.uid, required this.friends});

  @override
  State<_NewChallengeSheet> createState() => _NewChallengeSheetState();
}

class _NewChallengeSheetState extends State<_NewChallengeSheet> {
  ChallengeType _type = ChallengeType.headToHead;
  final Set<String> _chosen = {};
  double? _target;

  /// Protein goal: grams per person per day.
  double _proteinPerDay = 100;
  bool _saving = false;

  int get _people => _chosen.length + 1;
  int get _defaultTarget => _people * 4;

  int get _proteinTarget => ChallengeService.proteinTarget(_people,
      perPersonPerDay: _proteinPerDay.round());

  Future<void> _start() async {
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final myName =
          await FriendsService.nameFor(widget.uid, email: user?.email);
      await ChallengeService.create(
        uid: widget.uid,
        type: _type,
        friendIds: _chosen.toList(),
        target: switch (_type) {
          ChallengeType.group => (_target ?? _defaultTarget.toDouble())
              .clamp(1.0, (_people * ChallengeService.lengthDays).toDouble())
              .round(),
          ChallengeType.protein => _proteinTarget,
          _ => null,
        },
        names: {
          widget.uid: myName,
          for (final f in widget.friends)
            if (_chosen.contains(f.id)) f.id: f.name,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't start that. Try again.")),
        );
      }
    }
  }

  static const _options = [
    (ChallengeType.headToHead, 'Head-to-head', Icons.sports_mma),
    (ChallengeType.earlyLogger, 'Early logger', Icons.wb_sunny_outlined),
    (ChallengeType.group, 'Team goal', Icons.groups),
    (ChallengeType.protein, 'Protein goal', Icons.fitness_center),
  ];

  String _explainer(int target) => switch (_type) {
        ChallengeType.headToHead =>
          'Most days finished on budget in the next 7 days wins.',
        ChallengeType.earlyLogger =>
          'Most days with something logged before 11am in the next 7 '
              'days wins.',
        ChallengeType.group =>
          'Together, finish $target days in the next 7 days.',
        ChallengeType.protein =>
          'Together, log $_proteinTarget g of protein in the next 7 days '
              '(${_proteinPerDay.round()} g each a day).',
      };

  @override
  Widget build(BuildContext context) {
    final maxTarget = (_people * ChallengeService.lengthDays).toDouble();
    final target =
        (_target ?? _defaultTarget.toDouble()).clamp(1.0, maxTarget).toDouble();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New challenge',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (type, label, icon) in _options)
                          ChoiceChip(
                            avatar: Icon(icon, size: 18),
                            label: Text(label),
                            selected: _type == type,
                            onSelected: (_) => setState(() => _type = type),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _explainer(target.round()),
                      style: TextStyle(color: AppColors.muted),
                    ),
                    if (_type == ChallengeType.group)
                      Slider(
                        value: target,
                        min: 1,
                        max: maxTarget,
                        divisions:
                            maxTarget > 1 ? (maxTarget - 1).round() : null,
                        label: '${target.round()} days',
                        onChanged: (v) => setState(() => _target = v),
                      ),
                    if (_type == ChallengeType.protein)
                      Slider(
                        value: _proteinPerDay,
                        min: 50,
                        max: 200,
                        divisions: 15,
                        label: '${_proteinPerDay.round()} g a day each',
                        semanticFormatterCallback: (v) =>
                            '${v.round()} grams a day each',
                        onChanged: (v) => setState(() => _proteinPerDay = v),
                      ),
                    const SizedBox(height: 4),
                    Text('With',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    for (final f in widget.friends)
                      CheckboxListTile(
                        value: _chosen.contains(f.id),
                        title: Text(f.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _chosen.add(f.id);
                          } else {
                            _chosen.remove(f.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _chosen.isEmpty || _saving ? null : _start,
                  icon: const Icon(Icons.flag),
                  label: Text(_saving ? 'Starting…' : 'Start challenge'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
