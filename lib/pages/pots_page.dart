import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
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

  Future<void> _spend() async {
    setState(() => _busy = true);
    try {
      final moved = await BalanceService.spendPot(_uid);
      FoodLog.notifyChanged();
      if (mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${moved.round()} kcal moved onto your card')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't move the pot. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
            return const Center(
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
                        style: TextStyle(color: Colors.white70)),
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
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.emerald600,
                      ),
                      onPressed: (!enabled || pot <= 0 || _busy) ? null : _spend,
                      icon: const Icon(Icons.add_card),
                      label: const Text('Move to today\'s card'),
                    ),
                    if (!enabled) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Turn on saving below to start filling your pot.',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
              const Padding(
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
