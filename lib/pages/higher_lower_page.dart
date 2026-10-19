import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/games_service.dart';
import 'package:namer_app/ui/game_level.dart';
import 'package:namer_app/ui/responsive.dart';

/// Higher or Lower: two foods, tap the one with more calories. Quick to
/// play, and the gaps it shows are the lesson.
class HigherLowerPage extends StatefulWidget {
  const HigherLowerPage({super.key});

  @override
  State<HigherLowerPage> createState() => _HigherLowerPageState();
}

class _HigherLowerPageState extends State<HigherLowerPage> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  List<HlPair> _pairs = const [];
  int _index = 0;
  int _correct = 0;

  /// The food you picked for the current pair, once you've picked.
  HlFood? _picked;

  bool _loading = true;
  bool _earnsXp = false;
  bool _finished = false;
  bool _saving = false;
  XpResult _result = XpResult.none;
  GamesProgress _progress = const GamesProgress();
  int _bestBefore = 0;

  @override
  void initState() {
    super.initState();
    _deal(first: true);
  }

  void _reset() {
    _loading = true;
    _pairs = GamesService.dealHigherLower();
    _index = 0;
    _correct = 0;
    _picked = null;
    _finished = false;
    _result = XpResult.none;
  }

  Future<void> _deal({bool first = false}) async {
    if (first) {
      _reset();
    } else {
      setState(_reset);
    }
    var earns = false;
    try {
      earns = await GamesService.startHigherLowerRound(_uid);
      _progress = await GamesService.watch(_uid).first;
    } catch (_) {
      // Offline: still playable, just no XP.
    }
    GamesService.countPlay('higher_lower');
    if (!mounted) return;
    setState(() {
      _earnsXp = earns;
      _bestBefore = _progress.hlBest;
      _loading = false;
    });
  }

  void _pick(HlFood food) {
    if (_picked != null) return;
    final right = identical(food, _pairs[_index].higher);
    HapticFeedback.selectionClick();
    setState(() {
      _picked = food;
      if (right) _correct++;
    });
  }

  Future<void> _next() async {
    if (_index + 1 < _pairs.length) {
      setState(() {
        _index++;
        _picked = null;
      });
      return;
    }
    setState(() => _saving = true);
    var result = XpResult.none;
    try {
      result = await GamesService.finishHigherLower(_uid,
          correct: _correct, earns: _earnsXp);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _saving = false;
      _finished = true;
      _result = result;
      if (result.after > 0) {
        _progress = _progress.withXp(result.after, result.gained);
      }
    });
    await celebrateLevelUp(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Higher or Lower')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                  children: _finished ? _summary() : _round(),
                ),
              ),
            ),
    );
  }

  List<Widget> _round() {
    final pair = _pairs[_index];
    final picked = _picked;
    final n = _pairs.length;
    final right = picked != null && identical(picked, pair.higher);
    return [
      Row(
        children: [
          Text(
            '${_index + 1} of $n',
            style: TextStyle(
                fontWeight: FontWeight.w800, color: AppColors.gray700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (_index + (picked != null ? 1 : 0)) / n,
                minHeight: 6,
                color: AppColors.primary,
                backgroundColor: AppColors.gray100,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '✓ $_correct',
            style: TextStyle(
                fontWeight: FontWeight.w800, color: AppText.emerald600),
          ),
        ],
      ),
      if (!_earnsXp) ...[
        const SizedBox(height: 8),
        Text(
          "Practice round: you've had today's XP rounds.",
          style: TextStyle(fontSize: 12.5, color: AppColors.muted),
        ),
      ],
      const SizedBox(height: 18),
      Text(
        'Which has more calories?',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 14),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: HlChoice(
                food: pair.a,
                revealed: picked != null,
                isHigher: identical(pair.a, pair.higher),
                isPicked: identical(picked, pair.a),
                onTap: () => _pick(pair.a),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HlChoice(
                food: pair.b,
                revealed: picked != null,
                isHigher: identical(pair.b, pair.higher),
                isPicked: identical(picked, pair.b),
                onTap: () => _pick(pair.b),
              ),
            ),
          ],
        ),
      ),
      if (picked != null) ...[
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            '${right ? 'Right! ' : 'Not this time. '}'
            '${pair.higher.name} has ${pair.difference} kcal more.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: right ? AppText.emerald600 : AppText.rose600,
            ),
          ),
        ),
        if (pair.why != null) ...[
          const SizedBox(height: 12),
          SurpriseNote(pair.why!),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _saving ? null : _next,
            autofocus: true,
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.primaryDark),
            child: Text(
              _index + 1 < n ? 'Next' : 'See results',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _summary() {
    final n = _pairs.length;
    final newBest = _correct > _bestBefore && _bestBefore > 0;
    final emoji = _correct == n
        ? '🏆'
        : _correct >= n * 0.8
            ? '🎯'
            : _correct >= n * 0.6
                ? '👍'
                : '🧐';
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: AppDecor.card,
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 6),
            Text(
              '$_correct / $n',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              newBest
                  ? 'New best!'
                  : _bestBefore > 0
                      ? 'Your best: ${_bestBefore > _correct ? _bestBefore : _correct}'
                      : 'Right answers',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: newBest ? AppText.emerald600 : AppColors.gray700,
              ),
            ),
            if (_earnsXp) ...[
              const SizedBox(height: 10),
              XpPill(_result.gained),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      LevelCard(progress: _progress, compact: true),
      const SizedBox(height: 18),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: () => _deal(),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryDark),
          icon: const Icon(Icons.replay),
          label: const Text('Another round',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
    ];
  }
}

/// One side of a pair: tap it if you think it has more. Shared with Higher
/// or Lower against a friend.
class HlChoice extends StatelessWidget {
  final HlFood food;
  final bool revealed;
  final bool isHigher;
  final bool isPicked;
  final VoidCallback onTap;

  const HlChoice({
    super.key,
    required this.food,
    required this.revealed,
    required this.isHigher,
    required this.isPicked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color border = !revealed
        ? AppColors.border
        : isHigher
            ? AppText.emerald600
            : isPicked
                ? AppText.rose600
                : AppColors.border;
    return Semantics(
      button: !revealed,
      label: revealed
          ? '${food.name}, ${food.kcal} calories'
          : '${food.name}${food.detail.isEmpty ? '' : ', ${food.detail}'}',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          side: BorderSide(color: border, width: revealed ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: revealed ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(food.emoji, style: const TextStyle(fontSize: 44)),
                const SizedBox(height: 8),
                Text(
                  food.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                if (food.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    food.detail,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AppColors.gray600),
                  ),
                ],
                const SizedBox(height: 10),
                AnimatedOpacity(
                  opacity: revealed ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    '${food.kcal} kcal',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: isHigher ? AppText.emerald600 : AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "😮 Surprise!": why a surprise pair's answer isn't the obvious one.
/// Shared with Higher or Lower against a friend.
class SurpriseNote extends StatelessWidget {
  final String why;
  const SurpriseNote(this.why, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.amber300.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppDecor.radius),
        border: Border.all(color: AppColors.amber300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(
            child: Text('😮', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Surprise!',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppText.amber700)),
                const SizedBox(height: 2),
                Text(why,
                    style: TextStyle(
                        fontSize: 14, height: 1.35, color: AppColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
