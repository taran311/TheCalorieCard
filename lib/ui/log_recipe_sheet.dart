import 'package:flutter/material.dart';
import 'package:namer_app/ui/snack.dart';
import 'package:namer_app/services/portion_amount.dart';
import 'package:namer_app/ui/amount_field.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/meal_time.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/calorie_symbol.dart';

/// Bottom sheet: pick a meal and servings, then add a recipe to the card.
///
/// Returns what was logged (null if closed), and shows "Logged … · Undo"
/// itself.
Future<LoggedFoods?> showLogRecipeSheet(
  BuildContext context, {
  required String recipeId,
  required Map<String, dynamic> recipe,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final logged = await showModalBottomSheet<LoggedFoods>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _LogRecipeSheet(recipeId: recipeId, recipe: recipe),
  );
  if (logged != null && logged.count > 0) {
    messenger.hideCurrentSnackBar();
    messenger.showTimedSnackBar(
      SnackBar(
        content: Text(
            'Logged ${recipe['name'] ?? 'recipe'} to ${logged.meal}'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await FoodLog.undo(logged);
            } catch (_) {
              messenger.showSnackBar(const SnackBar(
                  content: Text("Couldn't undo that. Remove it from your "
                      'diary instead.')));
            }
          },
        ),
      ),
    );
  }
  return logged;
}

class _LogRecipeSheet extends StatefulWidget {
  final String recipeId;
  final Map<String, dynamic> recipe;

  const _LogRecipeSheet({required this.recipeId, required this.recipe});

  @override
  State<_LogRecipeSheet> createState() => _LogRecipeSheetState();
}

class _LogRecipeSheetState extends State<_LogRecipeSheet> {
  // The Card screen shows every meal now, so there's no "current" meal:
  // default from the time of day (they can change it with the chips).
  String _meal = MealTime.forHour(BalanceService.now().hour);
  bool _saving = false;
  String? _error;

  /// How much: one tap on a quick amount, or any exact number typed in
  /// (0.6 of it, say). Gram recipes count whole recipes and can be typed
  /// in grams or ounces too; others count servings.
  late final AmountInput _input = AmountInput(
    basePortion: _grams ? '${FoodLog.formatAmount(_base)}g' : '',
    multiplier: 1,
  );

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  double _n(String key) => BalanceService.number(widget.recipe[key]) ?? 0;

  String get _serving {
    final s = widget.recipe['serving_size'];
    return s is String && s.trim().isNotEmpty ? s : 'Per 1 Serving';
  }

  /// How many servings the whole recipe makes (or its weight in grams).
  double get _base => FoodLog.servingAmount(_serving);

  bool get _grams => FoodLog.isGrams(_serving);

  /// What the amount box says: whole recipes (gram recipes) or servings.
  /// Null while it's empty or not a number.
  double? get _amount => _input.multiplier;

  /// Share of the whole recipe being logged (0 while the box is empty).
  double get _multiplier {
    final a = _amount ?? 0;
    return _grams ? a : (_base > 0 ? a / _base : a);
  }

  /// One tap: quarters of the recipe for gram recipes, servings otherwise.
  List<double> get _quick => _grams
      ? const [0.25, 0.5, 0.75, 1.0, 2.0]
      : const [0.5, 1.0, 1.5, 2.0, 3.0];

  void _pick(double amount) {
    setState(() {
      _input.show(amount);
      _error = null;
    });
  }

  Future<void> _log() async {
    // Set before the first await, so a double tap can't log it twice.
    if (_saving) return;
    final amount = _amount;
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter how much you had, e.g. 0.6');
      return;
    }
    if (_multiplier > 100) {
      setState(() => _error = "That's a lot. Check the amount?");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final logged = await FoodLog.logRecipe(
        recipeId: widget.recipeId,
        recipe: widget.recipe,
        meal: _meal,
        multiplier: _multiplier,
      );
      if (mounted) Navigator.pop(context, logged);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't log this recipe. Please try again.";
        });
      }
    }
  }

  /// Under the amount box: what it is the other way round ("= 480 g", or
  /// "0.6 × 800g recipe"), or what 1 means.
  String _amountHelper(bool grams) {
    final a = _amount;
    if (!grams) return a == null ? '1 = one serving' : 'Any amount, e.g. 0.6';
    if (a == null) return '1 = the whole recipe';
    final other = _input.equivalent(a, '${FoodLog.formatAmount(_base)}g recipe');
    return other == null ? '1 = the whole recipe' : '= $other';
  }

  @override
  Widget build(BuildContext context) {
    final multiplier = _multiplier;
    final kcal = _n('total_calories') * multiplier;
    final grams = _grams;
    final base = FoodLog.formatAmount(_base);
    final subtitle = grams
        ? 'Whole recipe is $base g'
        : 'Makes $base serving${_base == 1 ? '' : 's'}';

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (widget.recipe['name'] ?? 'Recipe').toString(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            const Text('Meal',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in FoodLog.meals)
                  ChoiceChip(
                    label: Text(m),
                    selected: _meal == m,
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: _meal == m ? Colors.white : AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _meal = m),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(grams ? 'How much of the recipe?' : 'How many servings?',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in _quick)
                  ChoiceChip(
                    label: Text('${FoodLog.formatAmount(q)}×'),
                    selected: _amount != null && (_amount! - q).abs() < 1e-9,
                    onSelected: (_) => _pick(q),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_input.units.length > 1) ...[
              AmountUnitPicker(
                units: _input.units,
                selected: _input.unit,
                onChanged: (u) => setState(() => _input.setUnit(u)),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _input.controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: AmountInput.inputFormatters,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: _input.unit != AmountUnit.portions
                    ? 'Exact amount'
                    : grams
                        ? 'How many recipes'
                        : 'How many servings',
                suffixText: _input.unit == AmountUnit.portions
                    ? '×'
                    : PortionAmount.label(_input.unit),
                helperText: _amountHelper(grams),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _log(),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Figure(label: 'kcal', value: kcal.round().toString()),
                  _Figure(
                    label: 'Protein',
                    value: '${(_n('total_protein') * multiplier).round()}g',
                    color: AppColors.proteinText,
                  ),
                  _Figure(
                    label: 'Carbs',
                    value: '${(_n('total_carbs') * multiplier).round()}g',
                    color: AppColors.carbsText,
                  ),
                  _Figure(
                    label: 'Fat',
                    value: '${(_n('total_fat') * multiplier).round()}g',
                    color: AppColors.fatText,
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppText.red600)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _log,
                icon: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppText.primaryDark,
                        ),
                      )
                    : const Icon(Icons.credit_card),
                label: Text(
                  'Spend $calSym${kcal.round()} on $_meal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Figure({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color ?? AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 12, color: AppColors.muted)),
      ],
    );
  }
}
