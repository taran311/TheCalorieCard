import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/ui/responsive.dart';

/// Bottom sheet: pick a meal and servings, then spend a recipe from the card.
Future<void> showLogRecipeSheet(
  BuildContext context, {
  required String recipeId,
  required Map<String, dynamic> recipe,
}) async {
  final logged = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _LogRecipeSheet(recipeId: recipeId, recipe: recipe),
  );
  if (logged == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Logged ${recipe['name'] ?? 'recipe'} to today')),
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
    _meal = FoodLog.meals.contains(current) ? current : FoodLog.meals.first;
    final hour = DateTime.now().hour;
    // Sensible default meal from the time of day.
    if (hour < 11) {
      _meal = 'Brekkie';
    } else if (hour < 15) {
      _meal = 'Lunch';
    } else if (hour >= 17 && hour < 22) {
      _meal = 'Dinner';
    }
  }

  double _n(String key) {
    final v = widget.recipe[key];
    return v is num ? v.toDouble() : 0;
  }

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
        multiplier: _servings,
      );
      if (mounted) Navigator.pop(context, true);
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
    final kcal = _n('total_calories') * _servings;
    final serving =
        (widget.recipe['serving_size'] as String?) ?? 'Per 1 Serving';

    return SafeArea(
      child: Padding(
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
              'One serving = $serving',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            const Text('Meal',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
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
                const Text('Servings',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton.outlined(
                  onPressed: _servings > 0.5
                      ? () => setState(() => _servings -= 0.5)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    _servings == _servings.roundToDouble()
                        ? _servings.toStringAsFixed(0)
                        : _servings.toStringAsFixed(1),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.outlined(
                  onPressed: _servings < 10
                      ? () => setState(() => _servings += 0.5)
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
                    value: '${(_n('total_protein') * _servings).round()}g',
                    color: AppColors.protein,
                  ),
                  _Figure(
                    label: 'Carbs',
                    value: '${(_n('total_carbs') * _servings).round()}g',
                    color: AppColors.carbs,
                  ),
                  _Figure(
                    label: 'Fat',
                    value: '${(_n('total_fat') * _servings).round()}g',
                    color: AppColors.fat,
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.red)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _log,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
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
