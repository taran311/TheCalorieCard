import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/ui/responsive.dart';

/// Bottom sheet: pick a meal and servings, then spend a recipe from the card.
Future<void> showLogRecipeSheet(
  BuildContext context, {
  required String recipeId,
  required Map<String, dynamic> recipe,
}) async {
  // The sheet returns the meal it logged to, or null if closed.
  final meal = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _LogRecipeSheet(recipeId: recipeId, recipe: recipe),
  );
  if (meal != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Logged ${recipe['name'] ?? 'recipe'} to $meal')),
    );
  }
}

class _LogRecipeSheet extends StatefulWidget {
  final String recipeId;
  final Map<String, dynamic> recipe;

  const _LogRecipeSheet({required this.recipeId, required this.recipe});

  @override
  State<_LogRecipeSheet> createState() => _LogRecipeSheetState();
}

class _LogRecipeSheetState extends State<_LogRecipeSheet> {
  late String _meal;
  double _servings = 1;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current =
        Provider.of<CategoryService>(context, listen: false).selectedCategory;
    if (FoodLog.meals.contains(current)) {
      // Honour the meal already picked elsewhere in the app.
      _meal = current;
    } else {
      // Otherwise a sensible default from the time of day.
      final hour = DateTime.now().hour;
      if (hour < 11) {
        _meal = 'Brekkie';
      } else if (hour < 15) {
        _meal = 'Lunch';
      } else if (hour >= 17 && hour < 22) {
        _meal = 'Dinner';
      } else {
        _meal = 'Snacks';
      }
    }
  }

  double _n(String key) => BalanceService.number(widget.recipe[key]) ?? 0;

  String get _serving {
    final s = widget.recipe['serving_size'];
    return s is String && s.trim().isNotEmpty ? s : 'Per 1 Serving';
  }

  /// How many servings the whole recipe makes (or its weight in grams).
  double get _base => FoodLog.servingAmount(_serving);

  bool get _grams => FoodLog.isGrams(_serving);

  /// Share of the whole recipe being logged. For gram recipes the stepper
  /// counts whole recipes ("portions"); otherwise it counts servings.
  double get _multiplier => _grams ? _servings : _servings / _base;

  double get _step => _grams ? 0.25 : 0.5;

  double get _maxServings => _grams ? 10.0 : (_base > 10 ? _base : 10.0);

  Future<void> _log() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FoodLog.logRecipe(
        recipeId: widget.recipeId,
        recipe: widget.recipe,
        meal: _meal,
        multiplier: _multiplier,
      );
      if (mounted) Navigator.pop(context, _meal);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't log this recipe. Please try again.";
        });
      }
    }
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
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.muted),
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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(grams ? 'Portions' : 'Servings',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (grams)
                        const Text(
                          '1 = whole recipe',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Less',
                  onPressed: _servings > _step
                      ? () => setState(() => _servings -= _step)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    FoodLog.formatAmount(_servings),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'More',
                  onPressed: _servings < _maxServings
                      ? () => setState(() => _servings += _step)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
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
              Text(_error!, style: const TextStyle(color: AppColors.red600)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _log,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryDark,
                        ),
                      )
                    : const Icon(Icons.credit_card),
                label: Text(
                  'Spend ${kcal.round()} kcal',
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
  final Color color;

  const _Figure({
    required this.label,
    required this.value,
    this.color = AppColors.ink,
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
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ],
    );
  }
}
