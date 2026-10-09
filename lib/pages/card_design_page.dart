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
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!.data();
          final current = CardDesignService.designOf(data);
          final best =
              (BalanceService.number(data?['best_streak']) ?? 0).round();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Longest streak: $best day${best == 1 ? '' : 's'}',
                style: const TextStyle(color: AppColors.muted),
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
                  onPick: () => CardDesignService.choose(user.uid, design),
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

  const _DesignOption({
    required this.design,
    required this.holder,
    required this.selected,
    required this.unlocked,
    required this.onPick,
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
                            style: const TextStyle(
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
            ],
          ),
        ),
      ),
    );
  }
}
