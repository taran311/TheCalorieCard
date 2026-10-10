import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/responsive.dart';

/// Plans, what's included, and managing your subscription.
class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  String _plan = 'yearly';
  int _foundersLeft = 0;
  bool _busy = false;
  String? _error;

  /// Billing can be slow to load (or unreadable). After a while we show
  /// the plans anyway, so a free account is never stuck on a skeleton.
  bool _waitedLong = false;
  Timer? _waitTimer;

  @override
  void initState() {
    super.initState();
    _waitTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _waitedLong = true);
    });
    Premium.foundersLeft().then((n) {
      if (!mounted) return;
      setState(() {
        _foundersLeft = n;
        if (n > 0) _plan = 'founder';
      });
    });
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is PremiumException
            ? e.message
            : 'Something went wrong. Try again?');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final holder = cardholderFromEmail(email);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Premium')),
      body: ValueListenableBuilder<Entitlement>(
        valueListenable: Premium.notifier,
        builder: (context, e, _) {
          final subscribed = e.loaded && e.subscribed;
          // Until we know what they have, no plan picker: someone who has
          // already paid shouldn't see a checkout flash past.
          final checking = !e.loaded && !_waitedLong;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                children: [
                  _Header(entitlement: e, date: _date),
                  const SizedBox(height: 16),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: AspectRatio(
                        aspectRatio: 1.7,
                        child: CalorieCardFront(
                          amount: 1840,
                          holder: holder.isEmpty ? 'You' : holder,
                          validThru: '12/31',
                          design: CardDesign.aurora,
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
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Aurora: the Premium-only card design',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _Comparison(),
                  const SizedBox(height: 20),
                  if (checking)
                    const _PlansSkeleton()
                  else if (subscribed) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _run(Premium.manage),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Manage subscription'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Change plan, update your card or cancel. It takes '
                      'one tap and you keep Premium until the end of the '
                      'period you\'ve paid for.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ] else ...[
                    Text(
                      'Choose a plan',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_foundersLeft > 0)
                      _PlanTile(
                        selected: _plan == 'founder',
                        title: 'Early supporter',
                        price: '${PremiumPrices.founder} a year',
                        detail: 'Locked in for as long as you stay '
                            'subscribed. $_foundersLeft '
                            'place${_foundersLeft == 1 ? '' : 's'} left.',
                        badge: 'Best deal',
                        onTap: () => setState(() => _plan = 'founder'),
                      ),
                    _PlanTile(
                      selected: _plan == 'yearly',
                      title: 'Yearly',
                      price: '${PremiumPrices.yearly} a year',
                      detail: 'Just ${PremiumPrices.yearlyPerMonth} a month.',
                      badge: _foundersLeft > 0
                          ? null
                          : 'Save ${PremiumPrices.yearlySaving}',
                      onTap: () => setState(() => _plan = 'yearly'),
                    ),
                    _PlanTile(
                      selected: _plan == 'monthly',
                      title: 'Monthly',
                      price: '${PremiumPrices.monthly} a month',
                      detail: 'Flexible. Cancel any time.',
                      onTap: () => setState(() => _plan = 'monthly'),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            _busy ? null : () => _run(() => Premium.checkout(_plan)),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Continue to payment'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Cancel any time in one tap. Payments are handled '
                      'securely by Stripe. If you don\'t choose a plan, '
                      'you simply stay on the free plan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppText.red600),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Entitlement entitlement;
  final String Function(DateTime) date;

  const _Header({required this.entitlement, required this.date});

  @override
  Widget build(BuildContext context) {
    final e = entitlement;
    String title;
    String body;
    if (e.loaded && e.subscribed) {
      final end = e.periodEnd!;
      title = "You're Premium";
      body = '${e.planLabel} plan · '
          '${e.cancelAtPeriodEnd ? 'ends' : 'renews'} ${date(end)}';
      if (e.cancelAtPeriodEnd) {
        body += '. After that you\'ll move to the free plan.';
      }
    } else if (e.loaded && e.inTrial) {
      final days = e.trialDaysLeft;
      title = 'Your free trial: $days day${days == 1 ? '' : 's'} left';
      body = 'You have everything in Premium until '
          '${date(e.trialEndsAt!)}. No card needed, and nothing is charged '
          'unless you choose a plan.';
    } else if (e.loaded) {
      title = "You're on the free plan";
      body = 'Logging, streaks and friends are free for good. Premium adds '
          'the unlimited Coach, photo logging and more.';
    } else {
      title = 'Calorie Card Premium';
      body = 'More help from the Coach, faster logging and a card that '
          'stands out.';
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppDecor.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text(
                'PREMIUM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(color: Colors.white, height: 1.4),
          ),
          if (e.loaded && e.subscribed && e.plan == 'founder') ...[
            const SizedBox(height: 8),
            const Text(
              '💜 Early supporter. Thank you for backing The Calorie Card.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison();

  static const _rows = [
    ('Food logging, barcodes and recipes', '✓', '✓'),
    ('Streaks, Streak Freeze, friends and chat', '✓', '✓'),
    ('Calorie Coach', '${PremiumPrices.freeCoachPerDay} a day', 'Unlimited'),
    ('Coach adds and removes food for you', '–', '✓'),
    ('Photo logging', '–', '✓'),
    ('"Even it out" plans when you go over', '–', '✓'),
    ('Aurora card design', '–', '✓'),
    ('Wrapped for every past month', 'Last month', 'All'),
  ];

  @override
  Widget build(BuildContext context) {
    TextStyle head() => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.muted,
        );
    return Container(
      decoration: AppDecor.card,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text("WHAT'S INCLUDED", style: head())),
              SizedBox(
                  width: 74,
                  child: Text('FREE',
                      textAlign: TextAlign.center, style: head())),
              SizedBox(
                width: 74,
                child: Text(
                  'PREMIUM',
                  textAlign: TextAlign.center,
                  style: head().copyWith(color: AppText.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final r in _rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.$1,
                      style: TextStyle(fontSize: 13.5, color: AppColors.ink),
                    ),
                  ),
                  SizedBox(
                    width: 74,
                    child: Text(
                      r.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ),
                  SizedBox(
                    width: 74,
                    child: Text(
                      r.$3,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppText.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String price;
  final String detail;
  final String? badge;
  final VoidCallback onTap;

  const _PlanTile({
    required this.selected,
    required this.title,
    required this.price,
    required this.detail,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? AppColors.indigo50 : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDecor.radius),
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDecor.radius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected ? AppText.primary : AppColors.gray400,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            if (badge != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.emerald100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  badge!,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppText.emerald700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style:
                              TextStyle(fontSize: 12.5, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    price,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grey placeholders where the plans (or "Manage subscription") will be.
class _PlansSkeleton extends StatelessWidget {
  const _PlansSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double height, {double? width}) => Container(
          height: height,
          width: width,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.gray100,
            borderRadius: BorderRadius.circular(AppDecor.radius),
          ),
        );
    return Semantics(
      label: 'Checking your plan',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: bar(18, width: 140),
            ),
            bar(64),
            bar(64),
            bar(48),
          ],
        ),
      ),
    );
  }
}
