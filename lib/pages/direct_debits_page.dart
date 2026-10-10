import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/direct_debit_service.dart';
import 'package:namer_app/ui/responsive.dart';

/// Your direct debits: foods queued every morning for a one-tap confirm.
class DirectDebitsPage extends StatelessWidget {
  const DirectDebitsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Direct debits')),
      body: StreamBuilder<List<DirectDebit>>(
        stream: DirectDebitService.forUser(uid),
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
          if (debits.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.autorenew, size: 56, color: AppColors.muted),
                    SizedBox(height: 12),
                    Text('No direct debits yet',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6),
                    Text(
                      'On the Card screen, press and hold a food you have '
                      'every day (like a morning coffee) to set one up.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            children: [
              for (final d in debits)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: AppColors.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDecor.radius),
                    side: BorderSide(color: AppColors.border),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.autorenew, color: AppText.sky),
                    title: Text(d.name),
                    subtitle: Text(
                      '${d.macros.calories.round()} kcal · ${d.meal} · '
                      '${d.isDueToday ? 'due today' : 'done for today'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Cancel direct debit',
                      color: AppText.red600,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text('Cancel ${d.name}?'),
                            content: const Text(
                                "Food you've already logged stays logged."),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('Keep')),
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  style: TextButton.styleFrom(
                                      foregroundColor: AppText.red600),
                                  child: const Text('Cancel direct debit')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        try {
                          await DirectDebitService.cancel(d);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      "Couldn't cancel that. Please try again.")),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
