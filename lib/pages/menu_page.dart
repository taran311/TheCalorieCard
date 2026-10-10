import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/pages/account_page.dart';
import 'package:namer_app/pages/premium_page.dart';
import 'package:namer_app/pages/weight_page.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/appearance_sheet.dart';
import 'package:namer_app/ui/reminder_sheet.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';
import 'package:namer_app/ui/tutorials/tutorial_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/pages/hiscores_page.dart';
import 'package:namer_app/pages/statement_page.dart';
import 'package:namer_app/pages/user_settings_page.dart';
import 'package:namer_app/pages/achievements_page.dart';
import 'package:namer_app/pages/card_design_page.dart';
import 'package:namer_app/pages/direct_debits_page.dart';
import 'package:namer_app/pages/pots_page.dart';
import 'package:namer_app/pages/wrapped_page.dart';
import 'package:namer_app/services/balance_service.dart';

/// The Profile tab: your card's extras, progress and account.
class MenuPage extends StatefulWidget {
  /// Opened from the menu; provided by the app shell.
  final VoidCallback? onOpenStatement;
  final VoidCallback? onOpenHiscores;

  const MenuPage({
    Key? key,
    this.onOpenStatement,
    this.onOpenHiscores,
  }) : super(key: key);

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _profile;

  /// `users/{uid}`, for the display name chosen in Account.
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _user;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _profile = FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: uid)
          .limit(1)
          .snapshots();
      _user =
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    }
  }

  Future<void> _confirmSignOut() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (yes == true) await _logout();
  }

  Future<void> _logout() async {
    try {
      Premium.stop();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        // Reset the whole app (not just this tab) back to the sign-in flow.
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthPage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't sign you out. Please try again.")),
        );
      }
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => UserSettingsPage()),
    );
  }

  void _open(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  /// The weight log: today's weigh-in (which also updates your profile
  /// and offers a new suggested goal), your trend and a check-in.
  void _updateWeight() => _open(const WeightPage());

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  /// A titled group of rows in one card, like a phone's settings.
  Widget _group(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(title),
        Material(
          color: AppColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDecor.radius),
            side: BorderSide(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, indent: 62, color: AppColors.border),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _menuRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.gray400),
          ],
        ),
      ),
    );
  }

  /// Premium at the top: what you have, or what you'd get.
  Widget _premiumBanner(Entitlement e) {
    final String title;
    final String subtitle;
    if (e.loaded && e.subscribed) {
      title = "You're Premium";
      subtitle = e.cancelAtPeriodEnd
          ? 'Ends at the end of this period'
          : 'Thanks for your support · ${e.planLabel}';
    } else if (e.loaded && e.inTrial) {
      final d = e.trialDaysLeft;
      title = 'Premium trial: $d day${d == 1 ? '' : 's'} left';
      subtitle = 'Choose a plan any time to keep it';
    } else if (!e.loaded) {
      // Still checking: no prices yet, so someone who has already paid
      // never sees an upsell flash past.
      title = 'Premium';
      subtitle = 'Unlimited Coach, photo logging and more';
    } else {
      title = 'Go Premium';
      subtitle = 'Unlimited Coach, photo logging and more, from '
          '${PremiumPrices.yearlyPerMonth} a month';
    }
    return Material(
      borderRadius: BorderRadius.circular(AppDecor.radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: InkWell(
          onTap: () => _open(const PremiumPage()),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "2,050 kcal a day · 150P 200C 70F", from the saved goals.
  Widget _goalChip() {
    final stream = _profile;
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs;
        final goals = (docs == null || docs.isEmpty)
            ? null
            : BalanceService.goalsFrom(docs.first.data());
        if (goals == null) return const SizedBox.shrink();
        final text = '${formatCardKcal(goals.calories)} kcal a day · '
            '${goals.protein.round()}P ${goals.carbs.round()}C '
            '${goals.fat.round()}F';
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Material(
            color: Colors.white.withValues(alpha: 0.18),
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _openSettings,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tune, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        text,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Avatar initial, name and email at the top of the page.
  Widget _profileHeader(String name, String email) {
    return Row(
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
              name.initial.toUpperCase(),
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
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final topPadding = MediaQuery.of(context).padding.top;
    final email = currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Profile header
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, topPadding + 20, 20, 24),
              decoration: const BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _user,
                    builder: (context, snap) {
                      // The name they chose in Account, else one made from
                      // their email.
                      final chosen =
                          '${snap.data?.data()?['display_name'] ?? ''}'.trim();
                      final holder = cardholderFromEmail(email);
                      final name = chosen.isNotEmpty
                          ? chosen
                          : (holder.isEmpty ? 'You' : holder);
                      return _profileHeader(name, email);
                    },
                  ),
                  _goalChip(),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
                children: [
                  const SizedBox(height: 16),
                  ValueListenableBuilder<Entitlement>(
                    valueListenable: Premium.notifier,
                    builder: (context, e, _) => _premiumBanner(e),
                  ),
                  _group('Your card', [
                    _menuRow(
                      icon: Icons.receipt_long,
                      iconColor: AppText.primary,
                      title: 'Statement',
                      subtitle: 'Your spending, day by day',
                      onTap: () {
                        final open = widget.onOpenStatement;
                        if (open != null) {
                          open();
                          return;
                        }
                        _open(const StatementPage());
                      },
                    ),
                    _menuRow(
                      icon: Icons.savings_outlined,
                      iconColor: AppText.emerald600,
                      title: 'Pots',
                      subtitle: 'Save a little each day for a treat',
                      onTap: () => _open(const PotsPage()),
                    ),
                    _menuRow(
                      icon: Icons.autorenew,
                      iconColor: AppText.sky,
                      title: 'Direct debits',
                      subtitle: 'Foods you have every day',
                      onTap: () => _open(const DirectDebitsPage()),
                    ),
                    _menuRow(
                      icon: Icons.credit_card,
                      iconColor: AppText.violet,
                      title: 'Card design',
                      subtitle: 'Unlock new finishes with streaks',
                      onTap: () => _open(const CardDesignPage()),
                    ),
                  ]),
                  _group('Progress', [
                    _menuRow(
                      icon: Icons.emoji_events,
                      iconColor: AppText.amber600,
                      title: 'Achievements',
                      subtitle: 'The badges you have unlocked',
                      onTap: () => _open(const AchievementsPage()),
                    ),
                    _menuRow(
                      icon: Icons.auto_graph,
                      iconColor: AppText.violet600,
                      title: 'Monthly Wrapped',
                      subtitle: 'Your month in review, ready to share',
                      onTap: () => _open(const WrappedPage()),
                    ),
                    _menuRow(
                      icon: Icons.leaderboard,
                      iconColor: AppText.rose600,
                      title: 'Hiscores',
                      subtitle: 'See how you rank against friends',
                      onTap: () {
                        final open = widget.onOpenHiscores;
                        if (open != null) {
                          open();
                          return;
                        }
                        _open(const HiscoresPage());
                      },
                    ),
                  ]),
                  _group('Settings', [
                    _menuRow(
                      icon: Icons.tune,
                      iconColor: AppText.primary,
                      title: 'Goals and profile',
                      subtitle: 'Calorie goal, macros and your details',
                      onTap: _openSettings,
                    ),
                    _menuRow(
                      icon: Icons.monitor_weight_outlined,
                      iconColor: AppText.emerald600,
                      title: 'Update my weight',
                      subtitle: 'Log a weigh-in and see your trend',
                      onTap: _updateWeight,
                    ),
                    _menuRow(
                      icon: Icons.notifications_active_outlined,
                      iconColor: AppText.amber700,
                      title: 'Evening reminder',
                      subtitle: "A friendly nudge if you haven't logged",
                      onTap: () => showReminderSheet(context),
                    ),
                    _menuRow(
                      icon: Icons.dark_mode_outlined,
                      iconColor: AppText.violet600,
                      title: 'Appearance',
                      subtitle: 'Light, dark or match your device',
                      onTap: () => showAppearanceSheet(context),
                    ),
                  ]),
                  _group('Account', [
                    _menuRow(
                      icon: Icons.manage_accounts_outlined,
                      iconColor: AppText.sky,
                      title: 'Account and privacy',
                      subtitle: 'Your name, password, data and account',
                      onTap: () => _open(const AccountPage()),
                    ),
                    _menuRow(
                      icon: Icons.school_outlined,
                      iconColor: AppText.primary,
                      title: 'Tutorials',
                      subtitle: 'Short walk-throughs of each feature',
                      onTap: () => showTutorialsSheet(context),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton.icon(
                      onPressed: _confirmSignOut,
                      style: TextButton.styleFrom(
                        foregroundColor: AppText.red600,
                      ),
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text('Sign out'),
                    ),
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
