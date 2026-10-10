import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/card_design_service.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/responsive.dart';

/// Pick your card's finish. Locked designs show how to earn them; friends
/// see your design when they look at your card.
class CardDesignPage extends StatelessWidget {
  const CardDesignPage({super.key});

  Future<void> _choose(
      BuildContext context, String uid, CardDesign design) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await CardDesignService.choose(uid, design);
      messenger.showSnackBar(
        const SnackBar(content: Text('Card design updated')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't change your design. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final holder = cardholderFromEmail(user.email ?? '');
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Card design')),
      body: StreamBuilder(
        stream:
            BalanceService.db.collection('users').doc(user.uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  "Couldn't load your card designs. Check your connection and try again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!.data();
          final current = CardDesignService.designOf(data);
          final best =
              (BalanceService.number(data?['best_streak']) ?? 0).round();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            children: [
              Text(
                'Longest streak: $best day${best == 1 ? '' : 's'}',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              for (final design in CardDesign.all)
                _DesignOption(
                  design: design,
                  holder: holder.isEmpty
                      ? FriendsService.displayName(user.email)
                      : holder,
                  selected: design.id == current.id,
                  unlocked: CardDesignService.isUnlocked(design, data),
                  daysToUnlock: CardDesignService.daysToUnlock(design, data),
                  progress: CardDesignService.unlockProgress(design, data),
                  onPick: () => _choose(context, user.uid, design),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DesignOption extends StatelessWidget {
  final CardDesign design;
  final String holder;
  final bool selected;
  final bool unlocked;
  final VoidCallback onPick;

  /// For designs unlocked by a streak: days still to go, and progress 0-1.
  final int? daysToUnlock;
  final double? progress;

  const _DesignOption({
    required this.design,
    required this.holder,
    required this.selected,
    required this.unlocked,
    required this.onPick,
    this.daysToUnlock,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: unlocked ? onPick : null,
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 1.7,
                      child: CalorieCardFront(
                        amount: 1840,
                        holder: holder,
                        validThru: '12/31',
                        design: design,
                        macros: const [
                          CardMacro(
                              name: 'Protein',
                              remaining: 112,
                              color: CalorieCardColors.protein),
                          CardMacro(
                              name: 'Carbs',
                              remaining: 180,
                              color: CalorieCardColors.carbs),
                          CardMacro(
                              name: 'Fat',
                              remaining: 54,
                              color: CalorieCardColors.fat),
                        ],
                      ),
                    ),
                    if (!unlocked)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: Icon(Icons.lock_outline,
                                color: Colors.white, size: 40),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(design.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(design.requirement,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  if (selected)
                    const Chip(
                      avatar: Icon(Icons.check, size: 16),
                      label: Text('In use'),
                    )
                  else if (unlocked)
                    FilledButton(onPressed: onPick, child: const Text('Use'))
                  else
                    const Chip(label: Text('Locked')),
                ],
              ),
              if (!unlocked &&
                  daysToUnlock != null &&
                  daysToUnlock! > 0 &&
                  progress != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress!,
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        AppText.primary),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  daysToUnlock == 1
                      ? '1 more day to unlock'
                      : '$daysToUnlock more days to unlock',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.gray700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
