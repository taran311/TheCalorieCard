import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';
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
import 'package:namer_app/services/food_log.dart';

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

  /// Asks for a new weight, offers a new suggested goal worked out the same
  /// way Goals and profile does, and saves through the same path.
  Future<void> _updateWeight() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);

    DocumentSnapshot<Map<String, dynamic>>? doc;
    try {
      doc = await BalanceService.userDataDoc(uid);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              "Couldn't load your details. Check your connection and try again.")));
      return;
    }
    final data = doc?.data();
    final currentGoals = data == null ? null : BalanceService.goalsFrom(data);
    if (data == null || currentGoals == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Set your goals in Goals and profile first.')));
      return;
    }
    if (!mounted) return;

    final initialKg = asInt(data['weight']);
    final weight = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => _UpdateWeightSheet(initialKg: initialKg),
    );
    if (weight == null || !mounted) return;

    final mode = data['calorie_mode'];
    final base = maintenanceCalories(
      age: asInt(data['age']),
      heightCm: asInt(data['height']),
      weightKg: weight,
      male: data['gender'] == 'male',
      exerciseLevel: asDouble(data['exercise_level']) ?? 0,
    );

    Macros? newGoals;
    if (base != null && base.isFinite && base > 0) {
      final suggested = suggestedCalorieGoal(base, mode is String ? mode : null);
      final was = currentGoals.calories;
      final use = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('New suggested goal'),
          content: Text(
              'Your suggested goal is now ${formatCardKcal(suggested)} kcal '
              '(was ${formatCardKcal(was)}). Use it?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep my goal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use it'),
            ),
          ],
        ),
      );
      if (use == null || !mounted) return;
      if (use && suggested >= 500 && suggested <= 10000) {
        newGoals = defaultMacrosFor(suggested);
      }
    }

    try {
      await BalanceService.applyGoals(
        uid,
        goals: newGoals ?? currentGoals,
        extra: {
          'weight': weight,
          if (newGoals != null) 'goal_source': 'calculated',
        },
      );
      FoodLog.notifyChanged();
      messenger.showSnackBar(SnackBar(
          content: Text(newGoals != null
              ? 'Weight and goal saved. Your card is up to date.'
              : 'Weight saved.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't save your weight. Please try again.")));
    }
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool chevron = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.gray600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (chevron)
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.muted,
                  ),
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

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final topPadding = MediaQuery.of(context).padding.top;
    final email = currentUser?.email ?? '';
    final holder = cardholderFromEmail(email);
    final name = holder.isEmpty ? 'You' : holder;

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
                  Row(
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
                  ),
                  _goalChip(),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
                children: [
                  _sectionHeader('Your card'),
                  _buildMenuCard(
                    icon: Icons.receipt_long,
                    iconColor: AppColors.primary,
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
                  _buildMenuCard(
                    icon: Icons.savings_outlined,
                    iconColor: AppColors.emerald600,
                    title: 'Pots',
                    subtitle: 'Save a little each day for a treat',
                    onTap: () => _open(const PotsPage()),
                  ),
                  _buildMenuCard(
                    icon: Icons.autorenew,
                    iconColor: AppColors.sky,
                    title: 'Direct debits',
                    subtitle: 'Foods you have every day',
                    onTap: () => _open(const DirectDebitsPage()),
                  ),
                  _buildMenuCard(
                    icon: Icons.credit_card,
                    iconColor: AppColors.violet,
                    title: 'Card design',
                    subtitle: 'Unlock new finishes with streaks',
                    onTap: () => _open(const CardDesignPage()),
                  ),
                  _sectionHeader('Progress'),
                  _buildMenuCard(
                    icon: Icons.emoji_events,
                    iconColor: AppColors.amber600,
                    title: 'Achievements',
                    subtitle: 'The badges you have unlocked',
                    onTap: () => _open(const AchievementsPage()),
                  ),
                  _buildMenuCard(
                    icon: Icons.auto_graph,
                    iconColor: AppColors.violet600,
                    title: 'Monthly Wrapped',
                    subtitle: 'Your month in review, ready to share',
                    onTap: () => _open(const WrappedPage()),
                  ),
                  _buildMenuCard(
                    icon: Icons.leaderboard,
                    iconColor: AppColors.rose600,
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
                  _sectionHeader('Account'),
                  _buildMenuCard(
                    icon: Icons.tune,
                    iconColor: AppColors.primary,
                    title: 'Goals and profile',
                    subtitle: 'Calorie goal, macros and your details',
                    onTap: _openSettings,
                  ),
                  _buildMenuCard(
                    icon: Icons.monitor_weight_outlined,
                    iconColor: AppColors.emerald600,
                    title: 'Update my weight',
                    subtitle: 'Keep your suggested goal up to date',
                    onTap: _updateWeight,
                  ),
                  _buildMenuCard(
                    icon: Icons.logout,
                    iconColor: AppColors.red600,
                    title: 'Sign out',
                    subtitle: 'You can sign back in any time',
                    chevron: false,
                    onTap: _confirmSignOut,
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

/// A bottom sheet with one field: your weight in kg.
class _UpdateWeightSheet extends StatefulWidget {
  final int? initialKg;

  const _UpdateWeightSheet({this.initialKg});

  @override
  State<_UpdateWeightSheet> createState() => _UpdateWeightSheetState();
}

class _UpdateWeightSheetState extends State<_UpdateWeightSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.initialKg?.toString() ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final kg = double.tryParse(_controller.text.trim().replaceAll('kg', ''));
    // Same range Goals and profile accepts.
    if (kg == null || !kg.isFinite || kg < 30 || kg > 300) {
      setState(() => _error = 'Enter a weight between 30 and 300 kg.');
      return;
    }
    Navigator.pop(context, kg.round());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Update my weight',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Weight',
                suffixText: 'kg',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
