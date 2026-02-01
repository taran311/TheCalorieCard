import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/achievement_service.dart';

class AchievementsPage extends StatelessWidget {
  final String? userIdOverride;
  final String? titleOverride;

  const AchievementsPage({
    super.key,
    this.userIdOverride,
    this.titleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final userId = userIdOverride ?? FirebaseAuth.instance.currentUser?.uid;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: userId == null
          ? const Center(child: Text('Not logged in'))
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.indigo.shade50,
                    Colors.blue.shade50,
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.fromLTRB(8, topPadding + 8, 8, 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.of(context).maybePop();
                            },
                            icon: const Icon(Icons.arrow_back),
                            color: Colors.white,
                            splashRadius: 20,
                            tooltip: 'Back',
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                titleOverride ?? 'Achievements',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder(
                        stream:
                            AchievementService.streamUserAchievements(userId),
                        builder: (context, snapshot) {
                          final data = snapshot.data?.data() ?? {};

                          final achievements = [
                            _AchievementItem(
                              id: 'first_time_logger',
                              title: 'First Time Logger',
                              description:
                                  'Log your first food item to unlock this achievement.',
                              icon: Icons.book,
                            ),
                            _AchievementItem(
                              id: 'keto_novice',
                              title: 'Keto Novice',
                              description:
                                  'Log 1 day of eating with 0g carbs recorded.',
                              icon: Icons.egg_alt,
                            ),
                            _AchievementItem(
                              id: 'keto_apprentice',
                              title: 'Keto Apprentice',
                              description:
                                  'Log 7 consecutive days of eating 0g carbs recorded.',
                              icon: Icons.egg_alt,
                            ),
                            _AchievementItem(
                              id: 'keto_expert',
                              title: 'Keto Expert',
                              description:
                                  'Log 30 consecutive days of eating 0g carbs recorded.',
                              icon: Icons.egg_alt,
                            ),
                            _AchievementItem(
                              id: 'fast_1',
                              title: '2Fast',
                              description:
                                  'Log 1 day of eating 0 calories.',
                              icon: Icons.bolt,
                            ),
                            _AchievementItem(
                              id: 'fast_2',
                              title: '2Fast2Furious',
                              description:
                                  'Log 2 consecutive days of eating 0 calories.',
                              icon: Icons.bolt,
                            ),
                            _AchievementItem(
                              id: 'fast_4_month',
                              title: 'FasterThenYou',
                              description:
                                  'Log 4 days of eating 0 calories within a month.',
                              icon: Icons.bolt,
                            ),
                            _AchievementItem(
                              id: 'cultivating_mass',
                              title: 'Cultivating Mass',
                              description:
                                  'Log 7 consecutive days consuming more than 150g of protein each day.',
                              icon: Icons.fitness_center,
                            ),
                            _AchievementItem(
                              id: 'streak_starter',
                              title: 'Streak Starter',
                              description:
                                  'Log food for 3 days in a row to unlock.',
                              icon: Icons.local_fire_department,
                            ),
                            _AchievementItem(
                              id: 'macro_master',
                              title: 'Macro Master',
                              description:
                                  'Hit all macro targets in a day to unlock.',
                              icon: Icons.track_changes,
                            ),
                          ];

                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.9,
                              ),
                              itemCount: achievements.length,
                              itemBuilder: (context, index) {
                                final achievement = achievements[index];
                                final unlocked =
                                    (data[achievement.id] as bool?) ?? false;

                                final iconColor = unlocked
                                    ? const Color(0xFF6366F1)
                                    : Colors.grey.shade400;
                                final titleColor = unlocked
                                    ? Colors.grey.shade900
                                    : Colors.grey.shade500;

                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    _showAchievementDialog(
                                      context,
                                      achievement,
                                      unlocked,
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: unlocked
                                            ? const Color(0xFF6366F1)
                                                .withOpacity(0.4)
                                            : Colors.grey.shade300,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.04),
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          achievement.icon,
                                          size: 36,
                                          color: iconColor,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          achievement.title,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: titleColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _showAchievementDialog(
    BuildContext context,
    _AchievementItem achievement,
    bool unlocked,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                unlocked ? Icons.lock_open : Icons.lock,
                color: unlocked ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(achievement.title)),
            ],
          ),
          content: Text(
            achievement.description,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _AchievementItem {
  final String id;
  final String title;
  final String description;
  final IconData icon;

  const _AchievementItem({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
  });
}
