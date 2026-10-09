import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/pages/hiscores_page.dart';
import 'package:namer_app/pages/statement_page.dart';
import 'package:namer_app/pages/user_settings_page.dart';
import 'package:namer_app/pages/friends_page.dart';
import 'package:namer_app/pages/achievements_page.dart';
import 'package:namer_app/pages/card_design_page.dart';
import 'package:namer_app/pages/direct_debits_page.dart';
import 'package:namer_app/pages/pots_page.dart';
import 'package:namer_app/pages/wrapped_page.dart';

class MenuPage extends StatelessWidget {
  /// Opened from the menu; provided by the app shell.
  final VoidCallback? onOpenStatement;
  final VoidCallback? onOpenHiscores;

  const MenuPage({
    Key? key,
    this.onOpenStatement,
    this.onOpenHiscores,
  }) : super(key: key);

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        // Reset the whole app (not just this tab) back to the sign-in flow.
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthPage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  Widget _buildMenuCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    int? badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.red600,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            badge.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.gray600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppColors.gray400,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Profile Header
            Container(
              padding: EdgeInsets.fromLTRB(20, topPadding + 20, 20, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary,
                    AppColors.violet,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        (currentUser?.email ?? 'U')
                            .initial
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentUser?.email?.split('@')[0] ?? 'User',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentUser?.email ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 8),
                  // Edit Profile
                  _buildMenuCard(
                    icon: Icons.edit,
                    iconColor: AppColors.green,
                    title: 'Edit Profile',
                    subtitle: 'Update your personal settings',
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserSettingsPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Friends
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('friend_requests')
                        .where('to_user_id',
                            isEqualTo:
                                FirebaseAuth.instance.currentUser?.uid ?? '')
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final pendingCount = snapshot.data?.docs.length ?? 0;

                      return _buildMenuCard(
                        icon: Icons.people,
                        iconColor: AppColors.primary,
                        title: 'Friends',
                        subtitle: 'Manage your friend connections',
                        badge: pendingCount > 0 ? pendingCount : null,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const FriendsPage(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Statement
                  _buildMenuCard(
                    icon: Icons.receipt_long,
                    iconColor: AppColors.sky,
                    title: 'Statement',
                    subtitle: 'Your spending, day by day',
                    onTap: () async {
                      if (onOpenStatement != null) {
                        onOpenStatement!();
                        return;
                      }
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const StatementPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Hiscores
                  _buildMenuCard(
                    icon: Icons.leaderboard,
                    iconColor: AppColors.rose600,
                    title: 'Hiscores',
                    subtitle: 'See how you rank against friends',
                    onTap: () async {
                      if (onOpenHiscores != null) {
                        onOpenHiscores!();
                        return;
                      }
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HiscoresPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Achievements
                  _buildMenuCard(
                    icon: Icons.emoji_events,
                    iconColor: AppColors.amber,
                    title: 'Achievements',
                    subtitle: 'View your unlocked achievements',
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AchievementsPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildMenuCard(
                    icon: Icons.auto_graph,
                    iconColor: AppColors.violet600,
                    title: 'Monthly Wrapped',
                    subtitle: 'Your month in review, ready to share',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const WrappedPage()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildMenuCard(
                    icon: Icons.credit_card,
                    iconColor: AppColors.indigo700,
                    title: 'Card design',
                    subtitle: 'Unlock new finishes with streaks',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CardDesignPage()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildMenuCard(
                    icon: Icons.autorenew,
                    iconColor: AppColors.sky,
                    title: 'Direct debits',
                    subtitle: 'Foods you have every day',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const DirectDebitsPage()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildMenuCard(
                    icon: Icons.savings_outlined,
                    iconColor: AppColors.emerald600,
                    title: 'Pots',
                    subtitle: 'Save a little each day for a treat',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PotsPage()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Logout
                  _buildMenuCard(
                    icon: Icons.logout,
                    iconColor: AppColors.red400,
                    title: 'Logout',
                    subtitle: 'Sign out of your account',
                    onTap: () async {
                      await _logout(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
