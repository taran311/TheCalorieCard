import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/budget_service.dart';
import 'package:namer_app/services/spend_category.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/statement_widgets.dart';

/// Optional limits for a meal (per day) or a type of food (per week), like
/// a banking app's category budgets. They never change the card: they're a
/// guide, with a gentle heads-up on the Card at 80% and 100%.
class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  BudgetSettings _settings = BudgetSettings.empty;
  bool _loaded = false;
  bool _noProfile = false;
  bool _failed = false;
  bool _saving = false;

  /// By `kind|key`, for the "240 of 300 kcal today" lines.
  Map<String, BudgetProgress> _progress = const {};
  int _token = 0;

  /// What counts in each category, in plain words.
  static const _examples = {
    SpendCategory.homeCooked: 'Recipes you log from Recipes',
    SpendCategory.takeaway: "McDonald's, Greggs, kebabs, Domino's and the like",
    SpendCategory.drinks: 'Coffees, fizzy drinks, juice and alcohol',
    SpendCategory.snacks: 'Crisps, chocolate, biscuits, cake and sweets',
    SpendCategory.fruitVeg: 'Fruit, salad and veg',
    SpendCategory.meals: 'Everything else',
  };

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    if (uid == null) return;
    // Live, so changes made elsewhere (and food logged) show straight away.
    _sub = BalanceService.db
        .collection('user_data')
        .where('user_id', isEqualTo: uid)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.docs.isEmpty ? null : snap.docs.first.data();
      setState(() {
        _settings = BudgetSettings.fromProfile(data);
        _loaded = true;
        _noProfile = data == null;
        _failed = false;
      });
      _loadProgress();
    }, onError: (_) {
      if (mounted && !_loaded) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  static String _id(Budget b) => '${b.kind.name}|${b.key}';

  Future<void> _loadProgress() async {
    final uid = _uid;
    if (uid == null) return;
    final token = ++_token;
    try {
      final list = await BudgetService.loadProgress(uid, _settings);
      if (!mounted || token != _token) return;
      setState(() => _progress = {for (final p in list) _id(p.budget): p});
    } catch (_) {
      // The limits still show; only the "used" figures are missing.
    }
  }

  Future<void> _save(BudgetSettings next, String done) async {
    final uid = _uid;
    if (uid == null || _saving) return;
    setState(() => _saving = true);
    try {
      await BudgetService.save(uid, next);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't save that budget. Try again.")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editMeal(String meal) async {
    final current = _settings.mealLimit(meal);
    final result = await showDialog<_LimitResult>(
      context: context,
      builder: (_) => _LimitDialog(
        title: '$meal budget',
        explanation: 'Everything you log to $meal counts. It starts again '
            'each day.',
        unit: 'kcal a day',
        current: current,
        max: 10000,
      ),
    );
    if (result == null || !mounted) return;
    final limit = result.limit;
    await _save(
      _settings.withMeal(meal, limit),
      limit == null
          ? '$meal budget removed'
          : '$meal budget set to ${BudgetService.kcal(limit)} kcal a day',
    );
  }

  Future<void> _editCategory(SpendCategory c) async {
    final current = _settings.categoryLimit(c);
    final result = await showDialog<_LimitResult>(
      context: context,
      builder: (_) => _LimitDialog(
        title: '${c.label} budget',
        explanation: '${_examples[c] ?? c.label}. Weeks run Monday to '
            'Sunday.',
        unit: 'kcal a week',
        current: current,
        max: 50000,
      ),
    );
    if (result == null || !mounted) return;
    final limit = result.limit;
    await _save(
      _settings.withCategory(c, limit),
      limit == null
          ? '${c.label} budget removed'
          : '${c.label} budget set to ${BudgetService.kcal(limit)} kcal a week',
    );
  }

  Widget _row({
    required IconData icon,
    required Color color,
    required String title,
    required String explanation,
    required double? limit,
    required BudgetProgress? progress,
    required String unit,
    required VoidCallback onTap,
  }) {
    final String subtitle;
    if (limit == null) {
      subtitle = explanation;
    } else if (progress == null) {
      subtitle = '${BudgetService.kcal(limit)} $unit';
    } else {
      subtitle = '${BudgetService.kcal(limit)} $unit · '
          '${BudgetService.kcal(progress.used)} used ${progress.budget.period} '
          '· ${progress.leftLabel}';
    }
    return Semantics(
      button: true,
      label: '$title. $subtitle. ${limit == null ? 'Add' : 'Edit'} budget',
      excludeSemantics: true,
      child: InkWell(
        onTap: _saving ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: color),
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
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                      ),
                      if (limit != null && progress != null) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress.fraction.isNaN
                                ? 0
                                : progress.fraction.clamp(0.0, 1.0).toDouble(),
                            minHeight: 6,
                            backgroundColor: AppColors.border,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                progress.fraction >= 0.8
                                    ? AppColors.amber
                                    : AppColors.primary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  limit == null ? 'Add' : 'Edit',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppText.primary,
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: AppColors.gray400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_uid == null) return const Center(child: Text('Please sign in'));
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Couldn't load your budgets. Check your connection and try "
            'again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_noProfile) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Set up your calorie goal first, then you can add budgets.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: Breakpoints.contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set an optional limit for a meal or a type of food, like '
                  "a bank's spending budgets. They're just a guide: your "
                  'daily calorie budget stays the same.',
                  style: TextStyle(
                      fontSize: 14, height: 1.4, color: AppColors.gray700),
                ),
                const SizedBox(height: 16),
                PanelCard(
                  title: 'Meals',
                  trailing: Text('per day',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  padding: const EdgeInsets.fromLTRB(14, 16, 10, 10),
                  child: Column(
                    children: [
                      for (final m in BudgetService.mealNames)
                        _row(
                          icon: Icons.restaurant_menu,
                          color: AppColors.primary,
                          title: m,
                          explanation: 'No budget',
                          limit: _settings.mealLimit(m),
                          progress: _progress['${BudgetKind.meal.name}|$m'],
                          unit: 'kcal a day',
                          onTap: () => _editMeal(m),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PanelCard(
                  title: 'Types of food',
                  trailing: Text('per week',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  padding: const EdgeInsets.fromLTRB(14, 16, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Sorted from each food's name, the same as "
                        '"Where it went" on your Statement. Weeks run Monday '
                        'to Sunday.',
                        style:
                            TextStyle(fontSize: 12.5, color: AppColors.muted),
                      ),
                      const SizedBox(height: 6),
                      for (final c in SpendCategory.values)
                        _row(
                          icon: c.icon,
                          color: c.color,
                          title: c.label,
                          explanation: _examples[c] ?? '',
                          limit: _settings.categoryLimit(c),
                          progress:
                              _progress['${BudgetKind.category.name}|${c.name}'],
                          unit: 'kcal a week',
                          onTap: () => _editCategory(c),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notifications_none,
                        size: 18, color: AppColors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "You'll get a heads-up on your Card when a budget "
                        'reaches 80%, and again at 100%. Each one shows once '
                        'and you can dismiss it.',
                        style: TextStyle(
                            fontSize: 12.5, height: 1.4, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Budgets'),
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _body(),
    );
  }
}

/// What the limit dialog decided: a new limit, or null to remove it.
/// (The dialog itself returns null when cancelled.)
class _LimitResult {
  final double? limit;
  const _LimitResult(this.limit);
}

class _LimitDialog extends StatefulWidget {
  final String title;
  final String explanation;
  final String unit;
  final double? current;
  final double max;

  const _LimitDialog({
    required this.title,
    required this.explanation,
    required this.unit,
    required this.current,
    required this.max,
  });

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  late final TextEditingController _text = TextEditingController(
      text: widget.current == null ? '' : '${widget.current!.round()}');
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_text.text.trim().replaceAll(',', ''));
    if (v == null || v < 10) {
      setState(() => _error = 'Enter at least 10 kcal');
      return;
    }
    if (v > widget.max) {
      setState(() => _error =
          'That looks too high (most is ${BudgetService.kcal(widget.max)})');
      return;
    }
    Navigator.of(context).pop(_LimitResult(v.roundToDouble()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.explanation,
              style: TextStyle(fontSize: 14, color: AppColors.gray700)),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Limit',
              suffixText: widget.unit,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(const _LimitResult(null)),
            style: TextButton.styleFrom(foregroundColor: AppText.red600),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
