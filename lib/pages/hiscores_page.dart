import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/leaderboard_service.dart';
import 'package:namer_app/ui/responsive.dart';

class _Board {
  final String label;
  final String emoji;
  final String description;
  final String unit;
  final num Function(PlayerStats) value;

  const _Board({
    required this.label,
    required this.emoji,
    required this.description,
    required this.unit,
    required this.value,
  });
}

final _boards = <_Board>[
  _Board(
    label: 'Streak',
    emoji: '🔥',
    description: 'Days in a row with a finished log',
    unit: 'days',
    value: (p) => p.streak,
  ),
  _Board(
    label: 'Logged',
    emoji: '📅',
    description: 'Finished days this month',
    unit: 'days',
    value: (p) => p.daysLogged,
  ),
  _Board(
    label: 'On budget',
    emoji: '💳',
    description: 'Days this month the card ended in credit',
    unit: 'days',
    value: (p) => p.daysOnBudget,
  ),
  _Board(
    label: 'Protein',
    emoji: '💪',
    description: 'Protein logged since Monday',
    unit: 'g',
    value: (p) => p.proteinThisWeek.round(),
  ),
];

class HiscoresPage extends StatefulWidget {
  const HiscoresPage({Key? key}) : super(key: key);

  @override
  State<HiscoresPage> createState() => _HiscoresPageState();
}

class _HiscoresPageState extends State<HiscoresPage> {
  int _board = 0;
  Future<List<PlayerStats>>? _future;
  List<String> _loadedFor = const [];

  void _ensureLoaded(String uid, List<String> friendIds) {
    final sorted = [...friendIds]..sort();
    final same = sorted.length == _loadedFor.length &&
        List.generate(sorted.length, (i) => sorted[i] == _loadedFor[i])
            .every((x) => x);
    if (_future != null && same) return;
    _loadedFor = sorted;
    _future = LeaderboardService.load(myUserId: uid, friendIds: friendIds);
  }

  Future<void> _refresh(String uid) async {
    setState(() {
      _future = LeaderboardService.load(myUserId: uid, friendIds: _loadedFor);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view hiscores')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Hiscores',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(user.uid),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final friends = (snapshot.data!.data()?['friends'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              <String>[];

          if (friends.isEmpty) return const _NoFriends();

          _ensureLoaded(user.uid, friends);

          return FutureBuilder<List<PlayerStats>>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "Couldn't load hiscores.\n${snap.error}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final board = _boards[_board];
              final ranked = [...snap.data!]
                ..sort((a, b) {
                  final byValue = board.value(b).compareTo(board.value(a));
                  if (byValue != 0) return byValue;
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });

              return RefreshIndicator(
                onRefresh: () => _refresh(user.uid),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _BoardPicker(
                      selected: _board,
                      onSelected: (i) => setState(() => _board = i),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      board.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    _Podium(ranked: ranked, board: board),
                    const SizedBox(height: 18),
                    for (var i = 0; i < ranked.length; i++)
                      _RankRow(
                        rank: _rankOf(ranked, i, board),
                        player: ranked[i],
                        value: board.value(ranked[i]),
                        unit: board.unit,
                        leaderValue: board.value(ranked.first),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Equal scores share a rank (1, 2, 2, 4...).
  int _rankOf(List<PlayerStats> ranked, int index, _Board board) {
    var i = index;
    while (i > 0 && board.value(ranked[i - 1]) == board.value(ranked[index])) {
      i--;
    }
    return i + 1;
  }
}

class _BoardPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;

  const _BoardPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _boards.length; i++)
          ChoiceChip(
            label: Text('${_boards[i].emoji}  ${_boards[i].label}'),
            selected: i == selected,
            showCheckmark: false,
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: i == selected ? Colors.white : AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) => onSelected(i),
          ),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  final List<PlayerStats> ranked;
  final _Board board;

  const _Podium({required this.ranked, required this.board});

  @override
  Widget build(BuildContext context) {
    // Order on screen: 2nd, 1st, 3rd.
    final slots = <int>[1, 0, 2].where((i) => i < ranked.length).toList();
    const heights = {0: 120.0, 1: 92.0, 2: 72.0};
    const medals = {0: '🥇', 1: '🥈', 2: '🥉'};

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final i in slots)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(medals[i]!, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 4),
                  CircleAvatar(
                    radius: i == 0 ? 26 : 21,
                    backgroundColor: Colors.white,
                    child: Text(
                      ranked[i].name.isEmpty
                          ? '?'
                          : ranked[i].name[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ranked[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: heights[i],
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: i == 0 ? 0.3 : 0.2),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(14)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${board.value(ranked[i])}\n${board.unit}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final int rank;
  final PlayerStats player;
  final num value;
  final String unit;
  final num leaderValue;

  const _RankRow({
    required this.rank,
    required this.player,
    required this.value,
    required this.unit,
    required this.leaderValue,
  });

  @override
  Widget build(BuildContext context) {
    final share = leaderValue <= 0 ? 0.0 : value / leaderValue;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: player.isMe
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: player.isMe ? AppColors.primary : AppColors.border,
          width: player.isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '#$rank',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: share.clamp(0.0, 1.0).toDouble(),
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '$value $unit',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoFriends extends StatelessWidget {
  const _NoFriends();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off, size: 80, color: AppColors.gray400),
            const SizedBox(height: 16),
            Text(
              'No Friends Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.gray600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add friends to see leaderboards!',
              style: TextStyle(fontSize: 14, color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
