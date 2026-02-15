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
                              description: 'Log 1 day of eating 0 calories.',
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

                          final unlockedCount = achievements
                              .where((a) => (data[a.id] as bool?) ?? false)
                              .length;

                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                // Stats Card
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFF6366F1),
                                        const Color(0xFF8B5CF6),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF6366F1)
                                            .withOpacity(0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      Column(
                                        children: [
                                          Text(
                                            unlockedCount.toString(),
                                            style: const TextStyle(
                                              fontSize: 32,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const Text(
                                            'Unlocked',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        width: 1,
                                        height: 50,
                                        color: Colors.white.withOpacity(0.3),
                                      ),
                                      Column(
                                        children: [
                                          Text(
                                            achievements.length.toString(),
                                            style: const TextStyle(
                                              fontSize: 32,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const Text(
                                            'Total',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Achievements Grid
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 16,
                                    crossAxisSpacing: 16,
                                    childAspectRatio: 0.85,
                                  ),
                                  itemCount: achievements.length,
                                  itemBuilder: (context, index) {
                                    final achievement = achievements[index];
                                    final unlocked =
                                        (data[achievement.id] as bool?) ??
                                            false;

                                    return InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        _showAchievementDialog(
                                          context,
                                          achievement,
                                          unlocked,
                                        );
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: unlocked
                                              ? LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Colors.white,
                                                    const Color(0xFF6366F1)
                                                        .withOpacity(0.05),
                                                  ],
                                                )
                                              : null,
                                          color: unlocked
                                              ? null
                                              : Colors.white.withOpacity(0.6),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color: unlocked
                                                ? const Color(0xFF6366F1)
                                                    .withOpacity(0.5)
                                                : Colors.grey.shade300,
                                            width: unlocked ? 2 : 1,
                                          ),
                                          boxShadow: unlocked
                                              ? [
                                                  BoxShadow(
                                                    color:
                                                        const Color(0xFF6366F1)
                                                            .withOpacity(0.2),
                                                    blurRadius: 12,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                  BoxShadow(
                                                    color:
                                                        const Color(0xFF6366F1)
                                                            .withOpacity(0.1),
                                                    blurRadius: 20,
                                                    spreadRadius: 2,
                                                  ),
                                                ]
                                              : [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.04),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 3),
                                                  ),
                                                ],
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: unlocked
                                                    ? const Color(0xFF6366F1)
                                                        .withOpacity(0.15)
                                                    : Colors.grey.shade200,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                achievement.icon,
                                                size: 32,
                                                color: unlocked
                                                    ? const Color(0xFF6366F1)
                                                    : Colors.grey.shade400,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              achievement.title,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: unlocked
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: unlocked
                                                    ? Colors.grey.shade900
                                                    : Colors.grey.shade500,
                                                height: 1.2,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (unlocked) ...[
                                              const SizedBox(height: 4),
                                              Icon(
                                                Icons.check_circle,
                                                size: 14,
                                                color: const Color(0xFF10B981),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
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
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: unlocked
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        const Color(0xFF6366F1).withOpacity(0.05),
                      ],
                    )
                  : null,
              color: unlocked ? null : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: unlocked
                        ? const Color(0xFF6366F1).withOpacity(0.15)
                        : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    achievement.icon,
                    size: 48,
                    color: unlocked ? const Color(0xFF6366F1) : Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      unlocked ? Icons.lock_open : Icons.lock,
                      color: unlocked ? const Color(0xFF10B981) : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        achievement.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: unlocked
                              ? Colors.grey.shade900
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  achievement.description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                ),
                if (unlocked) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.check_circle,
                          color: Color(0xFF10B981),
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Unlocked',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: unlocked
                          ? const Color(0xFF6366F1)
                          : Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
