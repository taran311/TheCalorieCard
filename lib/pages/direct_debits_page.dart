import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/direct_debit_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/ui/responsive.dart';

/// Your direct debits: foods queued every morning for a one-tap confirm.
class DirectDebitsPage extends StatefulWidget {
  const DirectDebitsPage({super.key});

  @override
  State<DirectDebitsPage> createState() => _DirectDebitsPageState();
}

class _DirectDebitsPageState extends State<DirectDebitsPage> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  /// Created once: building it in build() would re-subscribe every rebuild
  /// (and flash a spinner).
  late final Stream<List<DirectDebit>> _debits =
      DirectDebitService.forUser(_uid);

  /// Debits being paid or skipped, so a double tap does nothing.
  final Set<String> _busy = {};

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(DirectDebit d, Future<Object?> Function() action,
      {String? done}) async {
    if (_busy.contains(d.id)) return;
    setState(() => _busy.add(d.id));
    try {
      final result = await action();
      final message = result == false ? 'Already done on another device' : done;
      if (message != null) _snack(message);
    } catch (_) {
      _snack('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy.remove(d.id));
    }
  }

  void _pay(DirectDebit d) => _run(
        d,
        () => DirectDebitService.pay(_uid, d),
        done: 'Logged ${d.name}',
      );

  void _skip(DirectDebit d) => _run(
        d,
        () async {
          await DirectDebitService.skipToday(d);
          return true;
        },
        done: 'Skipped ${d.name} today',
      );

  Future<void> _cancel(DirectDebit d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cancel ${d.name}?'),
        content: const Text("Food you've already logged stays logged."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: AppText.red600),
              child: const Text('Cancel direct debit')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DirectDebitService.cancel(d);
    } catch (_) {
      _snack("Couldn't cancel that. Please try again.");
    }
  }

  Future<void> _add() async {
    final created = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _NewDebitSheet(uid: _uid),
    );
    if (created != null) _snack('Direct debit set up for $created');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Direct debits')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'direct-debit-add',
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add a direct debit'),
      ),
      body: StreamBuilder<List<DirectDebit>>(
        stream: _debits,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  "Couldn't load your direct debits. Check your connection and try again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final debits = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                'Foods you have regularly — like your morning coffee — that '
                'come off your card each day after you confirm.',
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              if (debits.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(Icons.autorenew, size: 56, color: AppColors.muted),
                      const SizedBox(height: 12),
                      Text('No direct debits yet',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(height: 6),
                      Text(
                        'Tap "Add a direct debit" to pick something you '
                        'logged recently, or press and hold a food on the '
                        'Card screen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              for (final d in debits) _debitCard(d),
            ],
          );
        },
      ),
    );
  }

  Widget _debitCard(DirectDebit d) {
    final busy = _busy.contains(d.id);
    final String status;
    if (d.isDueToday) {
      status = 'Due today';
    } else if (d.handledToday) {
      status = 'Done for today';
    } else {
      status = 'Not today';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppDecor.card,
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.autorenew, color: AppText.sky),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d.macros.calories.round()} kcal · ${d.meal} · '
                      '${d.scheduleLabel} · $status',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cancel direct debit',
                color: AppText.red600,
                icon: const Icon(Icons.delete_outline),
                onPressed: busy ? null : () => _cancel(d),
              ),
            ],
          ),
          if (d.isDueToday)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  TextButton(
                    onPressed: busy ? null : () => _skip(d),
                    child: const Text('Skip today'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: busy ? null : () => _pay(d),
                    child: const Text('Pay'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Picks a recently logged food, its meal and days. Pops the food's name
/// once the direct debit is saved.
class _NewDebitSheet extends StatefulWidget {
  final String uid;

  const _NewDebitSheet({required this.uid});

  @override
  State<_NewDebitSheet> createState() => _NewDebitSheetState();
}

class _NewDebitSheetState extends State<_NewDebitSheet> {
  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday'
  ];

  late Future<List<Map<String, dynamic>>> _foods =
      DirectDebitService.recentFoods(widget.uid);
  Map<String, dynamic>? _food;
  String _meal = FoodLog.meals.first;
  final Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  bool _saving = false;
  String? _error;

  void _pick(Map<String, dynamic> food) {
    setState(() {
      _food = food;
      _meal = FoodLog.mealOf(food['foodCategory']);
      if (!FoodLog.meals.contains(_meal)) _meal = FoodLog.meals.first;
    });
  }

  Future<void> _save() async {
    final food = _food;
    if (food == null || _weekdays.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DirectDebitService.createFromEntry(widget.uid, food,
          meal: _meal, weekdays: _weekdays);
      if (mounted) {
        Navigator.pop(context, '${food['food_description'] ?? 'that'}');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't set that up. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final food = _food;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                food == null ? 'Add a direct debit' : 'When do you have it?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                food == null
                    ? 'Pick something you logged in the last 2 weeks.'
                    : "We'll ask you each of those mornings before it comes "
                        'off your card.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: food == null ? _foodList() : _details(food),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: AppText.red600)),
              ],
              if (food != null) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _weekdays.isEmpty || _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Set up direct debit'),
                ),
                TextButton(
                  onPressed: _saving ? null : () => setState(() => _food = null),
                  child: const Text('Pick a different food'),
                ),
              ] else
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _foodList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _foods,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text("Couldn't load your recent foods.",
                      style: TextStyle(color: AppColors.muted)),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _foods = DirectDebitService.recentFoods(widget.uid);
                  }),
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final foods = snap.data!;
        if (foods.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Nothing logged in the last 2 weeks yet. Log your regular '
              'foods as usual, then come back here.',
              style: TextStyle(color: AppColors.muted),
            ),
          );
        }
        return ListView(
          shrinkWrap: true,
          children: [
            for (final f in foods)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.restaurant_outlined,
                    color: AppText.primary),
                title: Text(
                  '${f['food_description'] ?? 'Food'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${(num.tryParse('${f['food_calories']}') ?? 0).round()} kcal'
                  ' · ${FoodLog.mealOf(f['foodCategory'])}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pick(f),
              ),
          ],
        );
      },
    );
  }

  Widget _details(Map<String, dynamic> food) {
    return ListView(
      shrinkWrap: true,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: AppDecor.inset,
          child: Text(
            '${food['food_description'] ?? 'Food'} · '
            '${(num.tryParse('${food['food_calories']}') ?? 0).round()} kcal',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
        ),
        const SizedBox(height: 16),
        Text('Meal',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in FoodLog.meals)
              ChoiceChip(
                label: Text(m),
                selected: _meal == m,
                onSelected: (_) => setState(() => _meal = m),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text('Days',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.ink)),
            ),
            Text(DirectDebitService.scheduleLabel(_weekdays),
                style: TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < 7; i++)
              Tooltip(
                message: _dayNames[i],
                child: FilterChip(
                  label: Text(_days[i], semanticsLabel: _dayNames[i]),
                  showCheckmark: false,
                  selected: _weekdays.contains(i + 1),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _weekdays.add(i + 1);
                    } else {
                      _weekdays.remove(i + 1);
                    }
                  }),
                ),
              ),
          ],
        ),
        if (_weekdays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Pick at least one day.',
                style: TextStyle(fontSize: 12, color: AppText.red600)),
          ),
      ],
    );
  }
}
