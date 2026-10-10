import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/challenge_service.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/ui/responsive.dart';

/// Weekly challenges with friends: head-to-head (most days on budget) or a
/// team goal (finished days between you). Scores come from finished days,
/// so they reward consistency, never eating less.
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

  @override
  void initState() {
    super.initState();
    _loadFriends();
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

  String _nameOf(String id) {
    if (id == _uid) return 'You';
    for (final f in _friends) {
      if (f.id == id) return f.name;
    }
    return 'Friend';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Challenge on! It runs until Sunday.')),
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              for (final c in list)
                _ChallengeCard(
                  key: ValueKey(c.id),
                  challenge: c,
                  uid: _uid,
                  nameOf: _nameOf,
                ),
            ],
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
            const Text('No challenges this week',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Go head-to-head on days on budget, or set a team goal for '
              'finished days.',
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

  const _ChallengeCard({
    super.key,
    required this.challenge,
    required this.uid,
    required this.nameOf,
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
    if (old.challenge.memberIds.length != widget.challenge.memberIds.length) {
      _scores = ChallengeService.scores(widget.challenge);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    final isGroup = c.type == ChallengeType.group;
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
              Text(isGroup ? '🤝' : '⚔️', style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(c.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Text(_daysLeft(),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
              PopupMenuButton<String>(
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
              if (snap.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text("Couldn't load scores."),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                );
              }
              final scores = snap.data!;
              if (isGroup) {
                final total =
                    scores.fold<int>(0, (s, e) => s + e.finishedDays);
                final target = c.target <= 0 ? 1 : c.target;
                final done = total >= target;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done
                          ? '🎉 Goal reached: $total / ${c.target} days'
                          : '$total / ${c.target} finished days',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (total / target).clamp(0.0, 1.0).toDouble(),
                        minHeight: 10,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation(
                            AppText.emerald600),
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
                                '${widget.nameOf(s.userId)} · ${s.finishedDays}'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                );
              }
              final leader = scores.isEmpty ? 0 : scores.first.onBudgetDays;
              // Only crown an outright leader, not a tie.
              final outright = leader > 0 &&
                  (scores.length < 2 || scores[1].onBudgetDays < leader);
              return Column(
                children: [
                  for (var i = 0; i < scores.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text(
                              i == 0 && outright ? '👑' : '#${i + 1}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              widget.nameOf(scores[i].userId),
                              style: TextStyle(
                                fontWeight: scores[i].userId == widget.uid
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            '${scores[i].onBudgetDays} on budget',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
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
  bool _saving = false;

  int get _defaultTarget => (_chosen.length + 1) * 4;

  Future<void> _start() async {
    setState(() => _saving = true);
    try {
      await ChallengeService.create(
        uid: widget.uid,
        type: _type,
        friendIds: _chosen.toList(),
        target: (_target ?? _defaultTarget.toDouble())
            .clamp(1.0, ((_chosen.length + 1) * 7).toDouble())
            .round(),
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

  @override
  Widget build(BuildContext context) {
    final people = _chosen.length + 1;
    final maxTarget = (people * 7).toDouble();
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
              const Text('New challenge',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              SegmentedButton<ChallengeType>(
                segments: const [
                  ButtonSegment(
                    value: ChallengeType.headToHead,
                    label: Text('Head-to-head'),
                    icon: Icon(Icons.sports_mma),
                  ),
                  ButtonSegment(
                    value: ChallengeType.group,
                    label: Text('Team goal'),
                    icon: Icon(Icons.groups),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(height: 8),
              Text(
                _type == ChallengeType.group
                    ? 'Together, finish ${target.round()} days by Sunday.'
                    : 'Most days finished on budget by Sunday wins.',
                style: TextStyle(color: AppColors.muted),
              ),
              if (_type == ChallengeType.group)
                Slider(
                  value: target,
                  min: 1,
                  max: maxTarget,
                  divisions: maxTarget > 1 ? (maxTarget - 1).round() : null,
                  label: '${target.round()} days',
                  onChanged: (v) => setState(() => _target = v),
                ),
              const SizedBox(height: 4),
              const Text('With',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in widget.friends)
                      CheckboxListTile(
                        value: _chosen.contains(f.id),
                        title: Text(f.name),
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
