import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/pot_service.dart';
import 'package:namer_app/ui/responsive.dart';

/// Pots: save a little of what you don't spend each day for a treat later
/// in the week. Capped on purpose so it can't become "skip meals now,
/// binge later".
class PotsPage extends StatefulWidget {
  const PotsPage({super.key});

  @override
  State<PotsPage> createState() => _PotsPageState();
}

class _PotsPageState extends State<PotsPage> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _busy = false;

  /// Created once so rebuilds (e.g. the busy spinner) don't re-subscribe.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _profile =
      BalanceService.db
          .collection('user_data')
          .where('user_id', isEqualTo: _uid)
          .limit(1)
          .snapshots();

  @override
  void initState() {
    super.initState();
    // Close yesterday so its savings show in the pot straight away.
    BalanceService.ensureDailyReset(_uid).catchError((_) => false);
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      await BalanceService.setPotsEnabled(_uid, on);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't change that. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks how much to move, then moves it (with an Undo).
  Future<void> _spend(double pot) async {
    final amount = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _MoveSheet(pot: pot),
    );
    if (amount == null || amount <= 0 || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final moved = await PotService.move(_uid, amount);
      FoodLog.notifyChanged();
      if (moved > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${moved.round()} kcal moved onto your card'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _undo(moved, messenger),
            ),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't move the pot. Try again.")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(double amount, ScaffoldMessengerState messenger) async {
    try {
      final ok = await PotService.undoMove(_uid, amount);
      FoodLog.notifyChanged();
      if (!ok) {
        messenger.showSnackBar(const SnackBar(
            content: Text("That can't be undone now: the day has moved on.")));
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't undo that. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Pots')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _profile,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  "Couldn't load your pot. Check your connection and try again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          final data =
              docs.isEmpty ? const <String, dynamic>{} : docs.first.data();
          final enabled = data['pots_enabled'] == true;
          final pot = BalanceService.potFrom(data);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            children: [
              // The switch comes first: until it's on, nothing below works.
              Container(
                decoration: AppDecor.card,
                clipBehavior: Clip.antiAlias,
                child: Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    value: enabled,
                    onChanged: _busy ? null : _toggle,
                    title: const Text('Save into a pot'),
                    subtitle: Text(
                      'On days you log food, up to '
                      '${BalanceService.potDailyCap.round()} kcal you didn\'t '
                      'spend goes into this week\'s pot.',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.emerald600, AppColors.emerald800],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Weekly pot',
                        style: TextStyle(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      '${pot.round()} kcal',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Up to ${BalanceService.potWeeklyCap.round()} kcal · '
                      'empties every Monday',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.emerald800,
                      ),
                      onPressed: (!enabled || pot <= 0 || _busy)
                          ? null
                          : () => _spend(pot),
                      icon: const Icon(Icons.add_card),
                      label: const Text('Move to today\'s card'),
                    ),
                    if (!enabled) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Turn on saving above to start filling your pot.',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'The caps are deliberate: a pot is for a small treat, not '
                  'for skipping meals to save up. Days you don\'t log don\'t '
                  'add anything.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Picks how much of the pot to move onto today's card. Pops the amount.
class _MoveSheet extends StatefulWidget {
  final double pot;

  const _MoveSheet({required this.pot});

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  /// Below this there's nothing to choose: it's the whole pot.
  static const _minChoice = 10.0;
  late double _amount = PotService.suggestedAmount(widget.pot);

  /// Steps of 10 kcal along the slider.
  static int _divisions(double pot) {
    final steps = ((pot - _minChoice) / 10).round();
    return steps < 1 ? 1 : steps;
  }

  /// Whole kcal, never more than the pot holds.
  double _chosen(double amount) {
    final pot = widget.pot;
    if (amount >= pot) return pot;
    final rounded = amount.roundToDouble();
    return rounded > pot ? pot : rounded;
  }

  @override
  Widget build(BuildContext context) {
    final pot = widget.pot;
    final canChoose = pot > _minChoice;
    final amount = _amount.clamp(0.0, pot).toDouble();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Move to today\'s card',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your pot has ${pot.round()} kcal. Whatever you leave stays '
              'in it until Monday.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                '${amount.round()} kcal',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
            if (canChoose)
              Slider(
                value: amount < _minChoice ? _minChoice : amount,
                min: _minChoice,
                max: pot,
                divisions: _divisions(pot),
                label: '${amount.round()} kcal',
                semanticFormatterCallback: (v) => '${v.round()} kcal',
                onChanged: (v) => setState(() => _amount = v),
              ),
            if (canChoose)
              Row(
                children: [
                  Text('${_minChoice.round()}',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _amount = pot),
                    child: Text('All ${pot.round()}'),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  amount <= 0 ? null : () => Navigator.pop(context, _chosen(amount)),
              icon: const Icon(Icons.add_card),
              label: Text('Move ${amount.round()} kcal'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
