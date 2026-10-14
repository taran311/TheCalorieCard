import 'package:flutter/material.dart';
import 'package:namer_app/services/calorie_game.dart';
import 'package:namer_app/ui/responsive.dart';

/// "Guess what I ate": pick exactly 5 foods you've eaten for a friend to
/// guess. Shows your own foods from the last 30 days, with calories (they're
/// yours, and it helps to pick interesting ones). If you've logged fewer
/// than 5, our list tops it up, so there's never a dead end.
///
/// Pops with the 5 foods, in the order picked, or null if you back out.
class GameFoodPicker extends StatefulWidget {
  final String uid;
  final String friendName;

  const GameFoodPicker({
    super.key,
    required this.uid,
    required this.friendName,
  });

  /// The picker as a full-screen route, for a navigator captured before
  /// an await.
  static Route<List<GameFood>> route({
    required String uid,
    required String friendName,
  }) =>
      MaterialPageRoute<List<GameFood>>(
        fullscreenDialog: true,
        builder: (_) => GameFoodPicker(uid: uid, friendName: friendName),
      );

  @override
  State<GameFoodPicker> createState() => _GameFoodPickerState();
}

/// One row in the list: a section heading or a food.
class _Item {
  final String? heading;
  final String? note;
  final GameFood? food;
  final String key;

  const _Item.heading(String this.heading, {this.note})
      : food = null,
        key = '';

  const _Item.food(GameFood this.food, this.key)
      : heading = null,
        note = null;
}

class _GameFoodPickerState extends State<GameFoodPicker> {
  late Future<List<GameFood>> _mine;

  /// Picked foods by key, in the order they were picked (a map literal
  /// keeps insertion order), which is the order your friend guesses them.
  final Map<String, GameFood> _picked = {};

  static const _rounds = CalorieGameService.rounds;

  @override
  void initState() {
    super.initState();
    _mine = CalorieGameService.loadPickable(widget.uid);
  }

  void _retry() {
    setState(() {
      _mine = CalorieGameService.loadPickable(widget.uid);
    });
  }

  /// Your food and the same food from our list are separate rows.
  static String _keyOf(GameFood f, {required bool fromList}) =>
      '${fromList ? 'list' : 'mine'}|${f.name.toLowerCase()}|'
      '${f.portion.toLowerCase()}';

  void _toggle(String key, GameFood food) {
    if (_picked.containsKey(key)) {
      setState(() => _picked.remove(key));
      return;
    }
    if (_picked.length >= _rounds) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
        content: Text("You've picked 5. Untick one to choose a different "
            'food.'),
      ));
      return;
    }
    setState(() => _picked[key] = food);
  }

  void _done() {
    if (_picked.length != _rounds) return;
    Navigator.of(context).pop(_picked.values.toList());
  }

  List<_Item> _items(List<GameFood> mine, {required bool failed}) {
    final topUp = failed || mine.length < _rounds;
    return [
      if (!failed) ...[
        _Item.heading(
          'Your foods from the last ${CalorieGameService.pickDays} days',
          note: mine.isEmpty
              ? "You haven't logged anything recently, so pick from our "
                  'list below.'
              : null,
        ),
        for (final f in mine) _Item.food(f, _keyOf(f, fromList: false)),
      ],
      if (topUp) ...[
        _Item.heading(
          'From our list',
          // Nothing logged, or a load error, already has its own note.
          note: !failed && mine.isNotEmpty
              ? "You've logged fewer than $_rounds foods recently, so top "
                  'up with some of these.'
              : null,
        ),
        // The hand-picked foods: a list someone can scroll through.
        for (final f in kPickedGameFoods) _Item.food(f, _keyOf(f, fromList: true)),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.friendName;
    final count = _picked.length;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Pick 5 foods')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pick 5 foods for $name to guess',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$name will see the names of the foods you pick, not '
                      'when you ate them.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.gray600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<GameFood>>(
                  future: _mine,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final failed = snap.hasError;
                    final items = _items(snap.data ?? const <GameFood>[],
                        failed: failed);
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: items.length + (failed ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (failed && i == 0) return _loadError();
                        final item = items[failed ? i - 1 : i];
                        final food = item.food;
                        if (food == null) {
                          return _SectionHeading(
                              text: item.heading ?? '', note: item.note);
                        }
                        return _FoodRow(
                          food: food,
                          selected: _picked.containsKey(item.key),
                          onTap: () => _toggle(item.key, food),
                        );
                      },
                    );
                  },
                ),
              ),
              _bottomBar(count),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadError() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Couldn't load your foods. You can pick from our list instead.",
              style: TextStyle(fontSize: 13, color: AppColors.gray700),
            ),
          ),
          TextButton(onPressed: _retry, child: const Text('Try again')),
        ],
      ),
    );
  }

  Widget _bottomBar(int count) {
    final ready = count == _rounds;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  '$count of $_rounds picked',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ready ? AppText.emerald600 : AppColors.gray700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: ready ? _done : null,
                  child: const Text(
                    'Use these 5',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String text;
  final String? note;

  const _SectionHeading({required this.text, this.note});

  @override
  Widget build(BuildContext context) {
    final n = note;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          if (n != null) ...[
            const SizedBox(height: 4),
            Text(
              n,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.gray600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One food: its meal emoji, name, portion and calories, with a tick box.
class _FoodRow extends StatelessWidget {
  final GameFood food;
  final bool selected;
  final VoidCallback onTap;

  const _FoodRow({
    required this.food,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final details = [
      if (food.portion.trim().isNotEmpty) food.portion.trim(),
      '${food.kcal} kcal',
    ].join(' · ');
    return CheckboxListTile(
      value: selected,
      onChanged: (_) => onTap(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      secondary: ExcludeSemantics(
        child: Text(food.emoji, style: const TextStyle(fontSize: 24)),
      ),
      title: Text(
        food.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      subtitle: Text(
        details,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: AppColors.gray600),
      ),
    );
  }
}
