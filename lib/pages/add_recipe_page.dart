import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/services/food_resolver.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/recipe_service.dart';

class AddRecipePage extends StatefulWidget {
  final String? recipeId; // if provided, page works in edit mode

  const AddRecipePage({
    super.key,
    this.recipeId,
  });

  @override
  State<AddRecipePage> createState() => _AddRecipePageState();
}

class _AddRecipePageState extends State<AddRecipePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _servingSizeController =
      TextEditingController(text: '1');
  final List<_IngredientEntry> _ingredients = [];
  bool _saving = false;
  bool _loading = false; // loading an existing recipe to edit
  String _servingUnit = 'Serving';
  int? _editingIngredientIndex;
  late TextEditingController _ingredientPortionController;

  // Free text mode
  final TextEditingController _freeTextController = TextEditingController();
  final List<String> _freeTextIngredients = [];
  bool _calculatingAi = false;
  bool _isAiLoading = false;
  bool _tutorialMode = false;

  // Cached tutorial data for instant demo
  static const List<Map<String, dynamic>> _tutorialCachedResults = [
    {
      'name': '100g oats',
      'calories': 389.0,
      'protein': 16.9,
      'carbs': 66.3,
      'fat': 6.9,
      'portion': '100g',
    },
    {
      'name': '200ml almond milk',
      'calories': 30.0,
      'protein': 1.0,
      'carbs': 1.0,
      'fat': 2.5,
      'portion': '200ml',
    },
    {
      'name': '1 banana',
      'calories': 105.0,
      'protein': 1.3,
      'carbs': 27.0,
      'fat': 0.4,
      'portion': '1 banana',
    },
    {
      'name': '20g honey',
      'calories': 64.0,
      'protein': 0.1,
      'carbs': 17.3,
      'fat': 0.0,
      'portion': '20g',
    },
  ];

  @override
  void initState() {
    super.initState();
    // Wake the lookup server early (it sleeps when idle).
    ProxyClient.warmUp();
    _ingredientPortionController = TextEditingController();
    if (widget.recipeId != null) {
      _loading = true;
      _loadRecipeForEdit(widget.recipeId!);
    }
  }

  @override
  void dispose() {
    _ingredientPortionController.dispose();
    _freeTextController.dispose();
    _nameController.dispose();
    _servingSizeController.dispose();
    super.dispose();
  }

  Future<void> _runTutorial() async {
    setState(() {
      _tutorialMode = true;
      _ingredients.clear();
      _freeTextIngredients.clear();
      _nameController.clear();
      _servingSizeController.text = '1';
      _servingUnit = 'Serving';
    });

    await Future.delayed(const Duration(milliseconds: 300));

    // Step 1: Type recipe name with typing effect
    const recipeName = 'Healthy Breakfast Bowl';
    for (int i = 0; i <= recipeName.length; i++) {
      await Future.delayed(const Duration(milliseconds: 40));
      if (mounted) {
        setState(() {
          _nameController.text = recipeName.substring(0, i);
        });
      }
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // Step 2: Change serving size to grams
    if (mounted) {
      setState(() {
        _servingUnit = 'g';
      });
    }

    await Future.delayed(const Duration(milliseconds: 300));

    // Type serving size
    _servingSizeController.clear();
    const servingSize = '250';
    for (int i = 0; i <= servingSize.length; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (mounted) {
        setState(() {
          _servingSizeController.text = servingSize.substring(0, i);
        });
      }
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // Step 3: Add tutorial ingredients with typing effect
    final tutorialIngredients = [
      '100g oats',
      '200ml almond milk',
      '1 banana',
      '20g honey'
    ];
    _freeTextController.text = '';

    for (int i = 0; i < tutorialIngredients.length; i++) {
      final ingredient = tutorialIngredients[i];

      // Typing effect
      for (int j = 0; j <= ingredient.length; j++) {
        await Future.delayed(const Duration(milliseconds: 30));
        if (mounted) {
          setState(() {
            _freeTextController.text = ingredient.substring(0, j);
          });
        }
      }

      await Future.delayed(const Duration(milliseconds: 300));

      // Add ingredient
      if (mounted) {
        setState(() {
          _freeTextIngredients.add(ingredient);
          _freeTextController.clear();
        });
      }

      await Future.delayed(const Duration(milliseconds: 400));
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // Step 4: Show calculating state with cached results
    if (mounted) {
      setState(() {
        _calculatingAi = true;
      });
    }

    await Future.delayed(const Duration(milliseconds: 800));

    // Step 5: Display cached calculated items
    if (mounted) {
      final cachedIngredients = _tutorialCachedResults.map((data) {
        return _IngredientEntry(
          name: data['name'] as String,
          calories: data['calories'] as double,
          protein: data['protein'] as double,
          carbs: data['carbs'] as double,
          fat: data['fat'] as double,
          portion: data['portion'] as String,
        );
      }).toList();

      setState(() {
        _ingredients.addAll(cachedIngredients);
        _freeTextIngredients.clear();
        _calculatingAi = false;
      });
    }

    await Future.delayed(const Duration(milliseconds: 1500));

    // Step 6: Clear all fields
    if (mounted) {
      setState(() {
        _ingredients.clear();
        _nameController.clear();
        _servingSizeController.text = '1';
        _servingUnit = 'Serving';
      });
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // Step 7: End tutorial
    if (mounted) {
      setState(() {
        _tutorialMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your turn! Add your own recipe.'),
          backgroundColor: AppColors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(widget.recipeId != null ? 'Edit recipe' : 'New recipe'),
        actions: [
          if (widget.recipeId == null)
            IconButton(
              onPressed: _tutorialMode ? null : _runTutorial,
              icon: const Icon(Icons.help_outline),
              tooltip: 'Show me how',
            ),
        ],
      ),
      // Save stays in reach however long the ingredient list gets.
      bottomNavigationBar: _loading
          ? null
          : AbsorbPointer(
              absorbing: _tutorialMode,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : (widget.recipeId != null
                              ? _updateRecipe
                              : _saveRecipe),
                      icon: const Icon(Icons.check),
                      label: Text(widget.recipeId != null
                          ? 'Save changes'
                          : 'Save recipe'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          AbsorbPointer(
            absorbing: _tutorialMode,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: AppDecor.card,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Recipe name',
                        hintText: 'e.g. Chicken curry',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter a recipe name'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'This recipe makes',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _servingSizeController,
                            onChanged: (_) => setState(() {}),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Enter a number';
                              }
                              final n = double.tryParse(v.trim());
                              if (n == null || !n.isFinite) {
                                return 'Enter a valid number';
                              }
                              if (n <= 0) return 'Must be more than 0';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String>(
                            // `value` (not initialValue) so the unit updates
                            // when an existing recipe finishes loading.
                            // ignore: deprecated_member_use
                            value: _servingUnit,
                            items: const [
                              DropdownMenuItem(
                                value: 'Serving',
                                child: Text('Servings'),
                              ),
                              DropdownMenuItem(
                                value: 'g',
                                child: Text('Grams'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _servingUnit = value ?? 'Serving';
                              });
                            },
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: AppDecor.card,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ingredients',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildSelectedIngredients(),
                          const SizedBox(height: 8),
                          _buildFreeTextInput(),
                          if (_ingredients.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildTotalsBar(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
          if (_saving)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator()),
            ),
          if (_tutorialMode)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.school,
                        color: Colors.white,
                        size: 32,
                      ),
                      SizedBox(width: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick demo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Watch how a recipe comes together',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Live totals for the ingredients so far, whole recipe and per serving.
  Widget _buildTotalsBar() {
    if (_ingredients.isEmpty) return const SizedBox.shrink();
    final totals = RecipeService.totalsOf(_recipeIngredients);
    double t(String key) => BalanceService.number(totals[key]) ?? 0;
    final kcal = t('total_calories');
    final makes = double.tryParse(_servingSizeController.text.trim());
    final amount = makes != null && makes.isFinite && makes > 0 ? makes : 1.0;
    final grams = _servingUnit == 'g';
    final perLabel = grams ? 'per 100 g' : 'per serving';
    final perKcal = grams ? kcal * 100 / amount : kcal / amount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.indigo50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.indigo100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Whole recipe: ${kcal.round()} kcal · $perLabel: ${perKcal.round()} kcal',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppText.primaryDark,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                'Protein ${t('total_protein').round()}g',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.proteinText),
              ),
              Text(
                'Carbs ${t('total_carbs').round()}g',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.carbsText),
              ),
              Text(
                'Fat ${t('total_fat').round()}g',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.fatText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Removes an ingredient, with Undo to put it back where it was.
  void _removeIngredient(int idx) {
    final removed = _ingredients[idx];
    setState(() {
      _ingredients.removeAt(idx);
      _editingIngredientIndex = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed ${removed.name}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              final at = idx <= _ingredients.length ? idx : _ingredients.length;
              _ingredients.insert(at, removed);
              _editingIngredientIndex = null;
            });
          },
        ),
      ),
    );
  }

  Widget _buildSelectedIngredients() {
    if (_ingredients.isEmpty) {
      return Text(
        'No ingredients yet. Type them below, e.g. "200g chicken, 1 onion".',
        style: TextStyle(color: AppColors.muted),
      );
    }

    return Column(
      children: _ingredients.asMap().entries.map((entry) {
        final idx = entry.key;
        final ing = entry.value;
        final isEditing = _editingIngredientIndex == idx;

        return Column(
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ing.name),
                    if (ing.portion.isNotEmpty)
                      Text(
                        '(${ing.portion})',
                        style: TextStyle(
                          color: AppColors.gray600,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${ing.calories.toStringAsFixed(0)} kcal',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppText.primary,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Change amount',
                      icon: Icon(Icons.edit_outlined, color: AppText.primary),
                      onPressed: () {
                        _startEditingIngredient(idx, ing.portion);
                      },
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: Icon(Icons.delete_outline, color: AppText.red600),
                      onPressed: () => _removeIngredient(idx),
                    ),
                  ],
                ),
              ),
            ),
            if (isEditing)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.indigo50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.indigo300, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Text(
                      'per ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(
                      width: 72,
                      child: TextField(
                        controller: _ingredientPortionController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          hintText: 'Amount',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _extractPortionUnit(ing.portion),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Save amount',
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.emerald600,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.check),
                      onPressed: () {
                        final newPortion = double.tryParse(
                            _ingredientPortionController.text.trim());
                        if (newPortion == null ||
                            !newPortion.isFinite ||
                            newPortion <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Enter an amount more than 0.')),
                          );
                          return;
                        }
                        final portionUnit = _extractPortionUnit(ing.portion);
                        final amount = FoodLog.formatAmount(newPortion);
                        final newPortionDisplay = portionUnit.isNotEmpty
                            ? '$amount $portionUnit'
                            : amount;

                        // Calculate adjusted macros based on portion ratio
                        final adjustedMacros =
                            _calculateAdjustedIngredientMacros(ing, newPortion);

                        setState(() {
                          _ingredients[idx] = _IngredientEntry(
                            name: ing.name,
                            calories: adjustedMacros['calories']!,
                            protein: adjustedMacros['protein']!,
                            carbs: adjustedMacros['carbs']!,
                            fat: adjustedMacros['fat']!,
                            portion: newPortionDisplay,
                          );
                          _editingIngredientIndex = null;
                        });
                      },
                    ),
                    IconButton(
                      tooltip: 'Cancel',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _editingIngredientIndex = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
          ],
        );
      }).toList(),
    );
  }

  void _startEditingIngredient(int idx, String currentPortion) {
    setState(() {
      _editingIngredientIndex = idx;
      _ingredientPortionController.text =
          _extractNumericPortion(currentPortion);
    });
  }

  String _extractNumericPortion(String portion) {
    if (portion.isEmpty) return '1';
    final regex = RegExp(r'^(\d+(?:\.\d+)?)');
    final match = regex.firstMatch(portion);
    return match != null ? match.group(1)! : '1';
  }

  String _extractPortionUnit(String portion) {
    if (portion.isEmpty) return '';
    final regex = RegExp(r'^\d+\.?\d*\s*(.*)');
    final match = regex.firstMatch(portion);
    return match != null && match.group(1)!.isNotEmpty
        ? match.group(1)!.trim()
        : '';
  }
  // Edit mode: load existing recipe and its ingredients
  Future<void> _loadRecipeForEdit(String recipeId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final recipeSnap =
          await firestore.collection('recipes').doc(recipeId).get();
      if (!mounted) return;
      final data = recipeSnap.data();
      if (!recipeSnap.exists || data == null) {
        _leaveWithMessage('That recipe no longer exists.');
        return;
      }

      // Name
      _nameController.text = (data['name'] ?? '').toString().trim();

      // Serving size
      final servingValue = data['serving_size'];
      final serving = servingValue is String && servingValue.isNotEmpty
          ? servingValue
          : 'Per 1 Serving';
      _applyServingSizeToFields(serving);

      // Ingredients (authoritative list from user_food with foodCategory 'Recipe')
      final ingSnap = await firestore
          .collection('user_food')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .where('recipe_id', isEqualTo: recipeId)
          .where('foodCategory', isEqualTo: 'Recipe')
          .get();

      final loaded = <_IngredientEntry>[];
      for (final doc in ingSnap.docs) {
        final d = doc.data();
        loaded.add(_IngredientEntry(
          name: (d['food_description'] ?? 'Ingredient').toString(),
          calories: BalanceService.number(d['food_calories']) ?? 0,
          protein: BalanceService.number(d['food_protein']) ?? 0,
          carbs: BalanceService.number(d['food_carbs']) ?? 0,
          fat: BalanceService.number(d['food_fat']) ?? 0,
          portion: (d['food_portion'] ?? '').toString(),
        ));
      }
      if (!mounted) return;
      setState(() {
        _ingredients
          ..clear()
          ..addAll(loaded);
      });
    } catch (e) {
      if (mounted) {
        _leaveWithMessage("Couldn't open that recipe. Please try again.");
      }
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Closes the editor and explains why.
  void _leaveWithMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _applyServingSizeToFields(String serving) {
    // Formats we save: "Per X Serving(s)" or "X g"
    final grams = RegExp(r'^(\d+(?:\.\d+)?)\s*g$');
    final serv = RegExp(r'^Per\s+(\d+(?:\.\d+)?)\s+Serving');
    final gMatch = grams.firstMatch(serving);
    final sMatch = serv.firstMatch(serving);
    if (gMatch != null) {
      _servingUnit = 'g';
      _servingSizeController.text = gMatch.group(1) ?? '1';
    } else if (sMatch != null) {
      _servingUnit = 'Serving';
      _servingSizeController.text = sMatch.group(1) ?? '1';
    } else {
      _servingUnit = 'Serving';
      _servingSizeController.text = '1';
    }
  }

  /// Serving size as saved on the recipe, e.g. "Per 2 Servings" or "450 g".
  String _servingSizeDisplay() {
    final value = double.tryParse(_servingSizeController.text.trim());
    final amount = value != null && value.isFinite && value > 0 ? value : 1.0;
    return FoodLog.servingLabel(amount, grams: _servingUnit == 'g');
  }

  /// Checks the form; explains what's missing instead of doing nothing.
  bool _readyToSave() {
    if (!_formKey.currentState!.validate()) return false;
    if (_ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one ingredient first.')),
      );
      return false;
    }
    return true;
  }

  List<RecipeIngredient> get _recipeIngredients => [
        for (final ing in _ingredients)
          RecipeIngredient(
            name: ing.name,
            macros: Macros(
              calories: ing.calories,
              protein: ing.protein,
              carbs: ing.carbs,
              fat: ing.fat,
            ),
            portion: ing.portion,
          ),
      ];

  Future<void> _updateRecipe() async {
    if (_saving || widget.recipeId == null) return;
    if (!_readyToSave()) return;

    setState(() => _saving = true);
    try {
      // Food already logged from this recipe keeps its own numbers, so
      // past days and today's balance don't change when a recipe is edited.
      await RecipeService.update(
        FirebaseAuth.instance.currentUser!.uid,
        widget.recipeId!,
        name: _nameController.text,
        servingSize: _servingSizeDisplay(),
        ingredients: _recipeIngredients,
      );
      if (!mounted) return;
      Navigator.pop(context, widget.recipeId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is StateError
                ? e.message
                : "Couldn't save that recipe. Please try again."),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveRecipe() async {
    if (_saving) return;
    if (!_readyToSave()) return;

    setState(() => _saving = true);
    try {
      final recipeId = await RecipeService.create(
        FirebaseAuth.instance.currentUser!.uid,
        name: _nameController.text,
        servingSize: _servingSizeDisplay(),
        ingredients: _recipeIngredients,
      );
      if (!mounted) return;
      Navigator.pop(context, recipeId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't save that recipe. Please try again.")),
        );
        setState(() => _saving = false);
      }
    }
  }

  Map<String, double> _calculateAdjustedIngredientMacros(
    _IngredientEntry ingredient,
    double newPortion,
  ) {
    final originalPortion = _extractPortionNumber(ingredient.portion);
    final ratio = newPortion / originalPortion;

    return {
      'calories': ingredient.calories * ratio,
      'protein': ingredient.protein * ratio,
      'carbs': ingredient.carbs * ratio,
      'fat': ingredient.fat * ratio,
    };
  }

  double _extractPortionNumber(String portion) {
    if (portion.isEmpty) return 1.0;
    final regex = RegExp(r'^(\d+(?:\.\d+)?)');
    final match = regex.firstMatch(portion);
    final value = match != null ? double.tryParse(match.group(1)!) : null;
    // Never 0: it's divided by when scaling an ingredient.
    return value != null && value > 0 ? value : 1.0;
  }

  /// Moves finished items from the text box into the list. With [all],
  /// the unfinished last item is taken too.
  void _takeFreeText({bool all = false}) {
    final value = _freeTextController.text;
    final parts = FoodResolver.splitItems(value);
    final endsWithSeparator = RegExp(r'[,\n;]\s*$').hasMatch(value);
    var remainder = '';
    if (!all && !endsWithSeparator && parts.isNotEmpty) {
      remainder = parts.removeLast();
    }
    if (parts.isEmpty) return;
    setState(() {
      _freeTextIngredients.addAll(parts);
      _freeTextController.value = TextEditingValue(
        text: remainder,
        selection: TextSelection.collapsed(offset: remainder.length),
      );
    });
  }

  // Free text input widget
  Widget _buildFreeTextInput() {
    return Column(
      children: [
        TextField(
          controller: _freeTextController,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Add ingredients',
            hintText: 'e.g. 200g chicken breast, 1 onion, 100g rice',
            border: const OutlineInputBorder(),
            helperText:
                'Separate with commas or press Enter. Pasting a list works too.',
            helperMaxLines: 2,
            suffixIcon: IconButton(
              tooltip: 'Add to list',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _takeFreeText(all: true),
            ),
          ),
          onChanged: (_) => _takeFreeText(),
          onSubmitted: (_) => _takeFreeText(all: true),
        ),
        const SizedBox(height: 12),
        if (_freeTextIngredients.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _freeTextIngredients.asMap().entries.map((entry) {
              final idx = entry.key;
              final ingredient = entry.value;
              return Chip(
                label: Text(ingredient),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () {
                  setState(() {
                    _freeTextIngredients.removeAt(idx);
                  });
                },
                backgroundColor: AppColors.indigo100,
              );
            }).toList(),
          ),
        if (_freeTextIngredients.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _calculatingAi ? null : _calculateAllWithAi,
              icon: _calculatingAi
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppText.primaryDark),
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                  _calculatingAi ? 'Working it out…' : 'Work out calories'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // Calculate all free text ingredients with AI
  Future<void> _calculateAllWithAi() async {
    _takeFreeText(all: true); // include anything still in the text box
    if (_freeTextIngredients.isEmpty) return;
    final queries = List<String>.from(_freeTextIngredients);

    setState(() {
      _calculatingAi = true;
    });

    // Several lookups at once instead of one after another.
    final resolved = await FoodResolver.resolveAll(queries);

    final results = <_IngredientEntry>[];
    final failed = <String>[];
    for (var i = 0; i < queries.length; i++) {
      final r = resolved[i];
      if (r == null) {
        failed.add(queries[i]);
        continue;
      }
      results.add(_IngredientEntry(
        name: queries[i], // keep the user's own wording
        calories: r.calories,
        protein: r.protein,
        carbs: r.carbs,
        fat: r.fat,
        portion: r.portion.isEmpty ? '1 serving' : r.portion,
      ));
    }

    if (mounted) {
      setState(() {
        _ingredients.addAll(results);
        // Failed items stay so they can be retried.
        _freeTextIngredients
          ..clear()
          ..addAll(failed);
        _calculatingAi = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lookupMessage(results.length, failed.length)),
        ),
      );
    }
  }
}

/// Snackbar text after working out calories.
String _lookupMessage(int added, int failed) {
  final addedText = 'Added $added ingredient${added == 1 ? '' : 's'}';
  if (failed == 0) return addedText;
  final missed = "we couldn't find $failed. Check the spelling and tap "
      'Work out calories again.';
  return added == 0 ? 'Sorry, $missed' : '$addedText, but $missed';
}

class _IngredientEntry {
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final String portion; // e.g., "100 g" or "1 banana"

  _IngredientEntry({
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.portion = '',
  });
}
