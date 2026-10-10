import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/meal_time.dart';
import 'package:namer_app/ui/responsive.dart';

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
    messenger.showSnackBar(
      SnackBar(
        content: Text(
            'Logged ${recipe['name'] ?? 'recipe'} to ${logged.meal}'),
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
  double _servings = 1;
  bool _saving = false;
  String? _error;

  /// Gram recipes: grams actually eaten, typed in (overrides the stepper).
  final TextEditingController _gramsController = TextEditingController();
  double? _gramsEaten;

  @override
  void dispose() {
    _gramsController.dispose();
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

  /// Share of the whole recipe being logged. For gram recipes the stepper
  /// counts whole recipes ("portions") unless grams eaten are typed in;
  /// otherwise it counts servings.
  double get _multiplier {
    final g = _gramsEaten;
    if (_grams && g != null) return g / _base;
    return _grams ? _servings : _servings / _base;
  }

  double get _step => _grams ? 0.25 : 0.5;

  double get _maxServings => _grams ? 10.0 : (_base > 10 ? _base : 10.0);

  void _setServings(double value) {
    setState(() {
      _servings = value;
      // Using the stepper again replaces any grams typed in.
      _gramsEaten = null;
      _gramsController.clear();
    });
  }

  void _onGramsChanged(String text) {
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    setState(() {
      _gramsEaten = v != null && v.isFinite && v > 0 ? v : null;
    });
  }

  Future<void> _log() async {
    // Set before the first await, so a double tap can't log it twice.
    if (_saving) return;
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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(grams ? 'Portions' : 'Servings',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (grams)
                        Text(
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
                      ? () => _setServings(_servings - _step)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    // With grams typed in, show the share of the recipe.
                    FoodLog.formatAmount(
                        _gramsEaten != null && grams ? multiplier : _servings),
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
                      ? () => _setServings(_servings + _step)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (grams) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _gramsController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Or grams eaten',
                  hintText: 'e.g. 300',
                  suffixText: 'g',
                  helperText: 'Weighed your plate? Type it in.',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _onGramsChanged,
              ),
            ],
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
                  'Add ${kcal.round()} kcal to $_meal',
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
