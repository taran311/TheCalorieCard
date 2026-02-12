import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/pages/fat_secret_api.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:namer_app/components/mini_game.dart';

class AddRecipePage extends StatefulWidget {
  final bool addToHome;
  final String? homeCategory;
  final String? recipeId; // if provided, page works in edit mode

  const AddRecipePage({
    super.key,
    this.addToHome = false,
    this.homeCategory,
    this.recipeId,
  });

  @override
  State<AddRecipePage> createState() => _AddRecipePageState();
}

class _AddRecipePageState extends State<AddRecipePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _servingSizeController =
      TextEditingController(text: '1');
  final FatSecretApi _api = FatSecretApi();

  final List<_IngredientEntry> _ingredients = [];
  Foods? _results;
  bool _searching = false;
  bool _saving = false;
  String _servingUnit = 'Serving';
  int? _editingIngredientIndex;
  int? _editingSearchIndex; // Track which search result is being edited
  late TextEditingController _ingredientPortionController;
  late TextEditingController _searchPortionController;

  // Mode selection
  String _inputMode = 'Free Text'; // 'Manual Input' or 'Free Text'

  // Free text mode
  final TextEditingController _freeTextController = TextEditingController();
  final List<String> _freeTextIngredients = [];
  bool _calculatingAi = false;
  bool _isAiLoading = false;
  bool _showMiniGame = false;

  @override
  void initState() {
    super.initState();
    _ingredientPortionController = TextEditingController();
    _searchPortionController = TextEditingController();
    if (widget.recipeId != null) {
      _loadRecipeForEdit(widget.recipeId!);
    }
  }

  @override
  void dispose() {
    _ingredientPortionController.dispose();
    _searchPortionController.dispose();
    _freeTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipeId != null ? 'Edit Recipe' : 'Add Recipe'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Recipe Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a recipe name'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Serving Size',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _servingSizeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Per',
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
                            if (double.tryParse(v) == null) {
                              return 'Enter a valid number';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          value: _servingUnit,
                          items: const [
                            DropdownMenuItem(
                              value: 'Serving',
                              child: Text('Serving'),
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
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Ingredients',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'Free Text',
                            label: Text('Free Text'),
                          ),
                          ButtonSegment<String>(
                            value: 'Manual Input',
                            label: Text('Manual Input'),
                          ),
                        ],
                        selected: {_inputMode},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() {
                            _inputMode = newSelection.first;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildSelectedIngredients(),
                  const SizedBox(height: 8),
                  if (_inputMode == 'Manual Input')
                    _buildSearch()
                  else
                    _buildFreeTextInput(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving
                          ? null
                          : (widget.recipeId != null
                              ? _updateRecipe
                              : _saveRecipe),
                      icon: const Icon(Icons.check),
                      label: Text(widget.recipeId != null
                          ? 'Save Changes'
                          : 'Save Recipe'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_saving)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator()),
            ),
          if ((_isAiLoading || _calculatingAi) && _showMiniGame)
            const PingPongGame(),
        ],
      ),
    );
  }

  Widget _buildSelectedIngredients() {
    if (_ingredients.isEmpty) {
      return const Text('No ingredients yet. Add from search below.');
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
                          color: Colors.grey.shade600,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                      onPressed: () {
                        _startEditingIngredient(idx, ing.portion);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _ingredients.removeAt(idx);
                        });
                      },
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
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade300, width: 1.5),
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
                      width: 55,
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
                    GestureDetector(
                      onTap: () async {
                        final newPortion = double.tryParse(
                                _ingredientPortionController.text) ??
                            1.0;
                        final portionUnit = _extractPortionUnit(ing.portion);
                        final newPortionDisplay = portionUnit.isNotEmpty
                            ? '$newPortion $portionUnit'
                            : '$newPortion';

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
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.shade400,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _editingIngredientIndex = null;
                        });
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red.shade400,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
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

  Widget _buildSearch() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Search ingredient (FatSecret)',
            border: const OutlineInputBorder(),
            suffixIcon: _searchController.text.isEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _searching ? null : _performSearch,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF6366F1),
                              Color(0xFF4F46E5),
                            ],
                          ),
                        ),
                        child: IconButton(
                          onPressed: _isAiLoading ? null : _performAiSearch,
                          icon: const Text(
                            'AI',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          tooltip: 'AI Estimate',
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _searching ? null : _performSearch,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF6366F1),
                              Color(0xFF4F46E5),
                            ],
                          ),
                        ),
                        child: IconButton(
                          onPressed: _isAiLoading ? null : _performAiSearch,
                          icon: const Text(
                            'AI',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          tooltip: 'AI Estimate',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _results = null;
                          });
                        },
                      ),
                    ],
                  ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _performSearch(),
        ),
        const SizedBox(height: 8),
        if (_searching) const LinearProgressIndicator(minHeight: 2),
        if (_isAiLoading)
          Column(
            children: [
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 8),
              Text(
                'AI is estimating...',
                style: TextStyle(
                  color: Colors.purple.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              if (!_showMiniGame) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showMiniGame = true;
                    });
                  },
                  icon: const Icon(Icons.sports_esports),
                  label: const Text('Play Ping Pong While You Wait'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        if (_results != null)
          Column(
            children: _results!.food.asMap().entries.map((entry) {
              final idx = entry.key;
              final food = entry.value;
              final isEditing = _editingSearchIndex == idx;
              final calories = _formatCalories(food.foodDescription);
              final protein = _formatProtein(food.foodDescription);
              final carbs = _formatCarbs(food.foodDescription);
              final fat = _formatFat(food.foodDescription);
              final portion = _formatAmount(food.foodDescription);

              return Column(
                children: [
                  Card(
                    child: ListTile(
                      title: Text(food.foodName),
                      subtitle: Text(food.foodDescription,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.add_circle_outline,
                          color: Color(0xFF6366F1)),
                      onTap: () {
                        setState(() {
                          _editingSearchIndex = idx;
                          _searchPortionController.text =
                              _extractNumericPortion(portion);
                        });
                      },
                    ),
                  ),
                  if (isEditing)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.purple.shade300, width: 1.5),
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
                            width: 55,
                            child: TextField(
                              controller: _searchPortionController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                              _extractPortionUnit(portion),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              final newPortion = double.tryParse(
                                      _searchPortionController.text) ??
                                  1.0;
                              final portionUnit = _extractPortionUnit(portion);
                              final newPortionDisplay = portionUnit.isNotEmpty
                                  ? '$newPortion $portionUnit'
                                  : '$newPortion';

                              // Calculate adjusted macros for search result
                              final originalPortion =
                                  _extractPortionNumber(portion);
                              final ratio = newPortion / originalPortion;

                              setState(() {
                                _ingredients.add(_IngredientEntry(
                                  name: food.foodName,
                                  calories: calories * ratio,
                                  protein: protein * ratio,
                                  carbs: carbs * ratio,
                                  fat: fat * ratio,
                                  portion: newPortionDisplay,
                                ));
                                _searchController.clear();
                                _results = null;
                                _editingSearchIndex = null;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        '${food.foodName} added with ${(calories * ratio).toStringAsFixed(0)} kcal')),
                              );
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.green.shade400,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _editingSearchIndex = null;
                              });
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.red.shade400,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            }).toList(),
          ),
      ],
    );
  }

  Future<void> _performSearch() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
    });
    try {
      final res = await _api.foodsSearch(q);
      if (mounted) {
        setState(() {
          _results = res;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  double _formatCalories(String stringToFormat) {
    return double.parse(stringToFormat.split('Calories: ')[1].split('kcal')[0]);
  }

  double _extractMacro(String source, List<String> labels) {
    for (final label in labels) {
      final regex = RegExp('$label\\s*:?\\s*([0-9]+(?:\\.[0-9]+)?)',
          caseSensitive: false);
      final match = regex.firstMatch(source);
      if (match != null) {
        return double.parse(match.group(1) ?? '0');
      }
    }
    return 0;
  }

  double _formatProtein(String stringToFormat) {
    return _extractMacro(stringToFormat, ['Protein']);
  }

  double _formatCarbs(String stringToFormat) {
    return _extractMacro(stringToFormat, ['Carbs', 'Carbohydrate']);
  }

  double _formatFat(String stringToFormat) {
    return _extractMacro(stringToFormat, ['Fat']);
  }

  // Edit mode: load existing recipe and its ingredients
  Future<void> _loadRecipeForEdit(String recipeId) async {
    setState(() => _saving = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final recipeSnap =
          await firestore.collection('recipes').doc(recipeId).get();
      if (!recipeSnap.exists) return;
      final data = recipeSnap.data()!;

      // Name
      _nameController.text = (data['name'] as String?)?.trim() ?? '';

      // Serving size
      final serving = (data['serving_size'] as String?) ?? 'Per 1 Serving';
      _applyServingSizeToFields(serving);

      // Ingredients (authoritative list from user_food with foodCategory 'Recipe')
      final ingSnap = await firestore
          .collection('user_food')
          .where('recipe_id', isEqualTo: recipeId)
          .where('foodCategory', isEqualTo: 'Recipe')
          .get();

      final loaded = <_IngredientEntry>[];
      for (final doc in ingSnap.docs) {
        final d = doc.data();
        loaded.add(_IngredientEntry(
          name: (d['food_description'] as String?) ?? 'Item',
          calories: ((d['food_calories'] as num?)?.toDouble() ?? 0),
          protein: ((d['food_protein'] as num?)?.toDouble() ?? 0),
          carbs: ((d['food_carbs'] as num?)?.toDouble() ?? 0),
          fat: ((d['food_fat'] as num?)?.toDouble() ?? 0),
          portion: (d['food_portion'] as String?) ?? '',
        ));
      }
      setState(() {
        _ingredients
          ..clear()
          ..addAll(loaded);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load recipe: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

  Future<void> _updateRecipe() async {
    if (!_formKey.currentState!.validate()) return;
    if (_ingredients.isEmpty) return;
    if (widget.recipeId == null) return;

    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final firestore = FirebaseFirestore.instance;

    // Recompute totals
    num totalCalories = 0;
    double totalProtein = 0;
    double totalCarbs = 0;
    double totalFat = 0;
    for (final ing in _ingredients) {
      totalCalories += ing.calories;
      totalProtein += ing.protein;
      totalCarbs += ing.carbs;
      totalFat += ing.fat;
    }

    final servingSizeValue = double.tryParse(_servingSizeController.text) ?? 1;
    final servingSizeDisplay = _servingUnit == 'g'
        ? '$servingSizeValue g'
        : 'Per $servingSizeValue ${_servingUnit}${servingSizeValue != 1 ? 's' : ''}';

    final batch = firestore.batch();

    // Delete old ingredient docs (authoritative list) for this recipe
    final existing = await firestore
        .collection('user_food')
        .where('recipe_id', isEqualTo: widget.recipeId)
        .where('foodCategory', isEqualTo: 'Recipe')
        .get();
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }

    // Create new ingredient docs
    final ingredientIds = <String>[];
    for (final ing in _ingredients) {
      final docRef = firestore.collection('user_food').doc();
      ingredientIds.add(docRef.id);
      batch.set(docRef, {
        'user_id': uid,
        'food_description': ing.name,
        'food_calories': ing.calories,
        'food_protein': ing.protein,
        'food_carbs': ing.carbs,
        'food_fat': ing.fat,
        'food_portion': ing.portion,
        'foodCategory': 'Recipe',
        'created_at': FieldValue.serverTimestamp(),
        'recipe_id': widget.recipeId,
      });
    }

    // Update the recipe document
    batch.update(firestore.collection('recipes').doc(widget.recipeId), {
      'user_id': uid,
      'name': _nameController.text.trim(),
      'serving_size': servingSizeDisplay,
      'food_item_ids': ingredientIds,
      'total_calories': totalCalories,
      'total_protein': totalProtein,
      'total_carbs': totalCarbs,
      'total_fat': totalFat,
    });

    try {
      await batch.commit();
      if (!mounted) return;
      Navigator.pop(context, widget.recipeId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update recipe: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatAmount(String stringToFormat) {
    final regex = RegExp(r'Per\s+(.+?)\s*-');
    final match = regex.firstMatch(stringToFormat);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return '';
  }

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) return;
    if (_ingredients.isEmpty) return;

    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    final ingredientIds = <String>[];
    num totalCalories = 0;
    double totalProtein = 0;
    double totalCarbs = 0;
    double totalFat = 0;

    for (final ing in _ingredients) {
      final docRef = firestore.collection('user_food').doc();
      final calories = ing.calories;
      final protein = ing.protein;
      final carbs = ing.carbs;
      final fat = ing.fat;

      totalCalories += calories;
      totalProtein += protein;
      totalCarbs += carbs;
      totalFat += fat;

      batch.set(docRef, {
        'user_id': uid,
        'food_description': ing.name,
        'food_calories': calories,
        'food_protein': protein,
        'food_carbs': carbs,
        'food_fat': fat,
        'foodCategory': 'Recipe',
        'created_at': FieldValue.serverTimestamp(),
        'recipe_id': 'pending',
      });

      ingredientIds.add(docRef.id);
    }

    final recipeRef = firestore.collection('recipes').doc();
    final servingSizeValue = double.tryParse(_servingSizeController.text) ?? 1;
    final servingSizeDisplay = _servingUnit == 'g'
        ? '$servingSizeValue g'
        : 'Per $servingSizeValue ${_servingUnit}${servingSizeValue != 1 ? 's' : ''}';
    batch.set(recipeRef, {
      'user_id': uid,
      'name': _nameController.text.trim(),
      'serving_size': servingSizeDisplay,
      'created_at': FieldValue.serverTimestamp(),
      'food_item_ids': ingredientIds,
      'total_calories': totalCalories,
      'total_protein': totalProtein,
      'total_carbs': totalCarbs,
      'total_fat': totalFat,
    });

    // Optionally add a rolled-up recipe entry to home
    if (widget.addToHome) {
      final category = widget.homeCategory ??
          Provider.of<CategoryService>(context, listen: false).selectedCategory;
      final rolledRef = firestore.collection('user_food').doc();
      batch.set(rolledRef, {
        'user_id': uid,
        'food_description': 'Recipe: ${_nameController.text.trim()}',
        'food_calories': totalCalories,
        'food_protein': totalProtein,
        'food_carbs': totalCarbs,
        'food_fat': totalFat,
        'food_portion': servingSizeDisplay,
        'foodCategory': category,
        'recipe_id': recipeRef.id,
        'created_at': FieldValue.serverTimestamp(),
        'is_recipe': true,
      });
    }

    // Update ingredient docs with the recipe_id now that we have it
    for (final id in ingredientIds) {
      batch.update(firestore.collection('user_food').doc(id), {
        'recipe_id': recipeRef.id,
      });
    }

    await batch.commit();

    if (!mounted) return;
    Navigator.pop(context, recipeRef.id);
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
    return match != null ? double.parse(match.group(1)!) : 1.0;
  }

  // AI Search for standard mode
  Future<void> _performAiSearch() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _isAiLoading = true;
      _results = null;
    });

    try {
      final Uri requestUri =
          Uri.parse('https://fatsecret-proxy.onrender.com/estimate');

      final response = await http.post(
        requestUri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({'food': q}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);

        if (!mounted) return;

        final foodName = jsonResponse['name'] ?? q;
        final mode = jsonResponse['mode'] ?? 'grams';
        final servingGrams = mode == 'serving'
            ? (jsonResponse['estimated_serving_grams'] ?? 100)
            : (jsonResponse['grams'] ?? 100);
        final servingDescription = jsonResponse['serving_description'];

        final totalCalories = (jsonResponse['calories'] ?? 0).toDouble();
        final totalProtein = (jsonResponse['protein'] ?? 0).toDouble();
        final totalCarbs = (jsonResponse['carbs'] ?? 0).toDouble();
        final totalFat = (jsonResponse['fat'] ?? 0).toDouble();

        final portion = '${servingGrams}g';

        String displayName;
        if (servingDescription != null && servingDescription.isNotEmpty) {
          displayName = servingDescription;
        } else {
          displayName = '$foodName (estimated serving size ${servingGrams}g)';
        }

        setState(() {
          _ingredients.add(_IngredientEntry(
            name: displayName,
            calories: totalCalories,
            protein: totalProtein,
            carbs: totalCarbs,
            fat: totalFat,
            portion: portion,
          ));
          _searchController.clear();
          _isAiLoading = false;
          _showMiniGame = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '$displayName added with ${totalCalories.toStringAsFixed(0)} kcal')),
          );
        }
      } else {
        throw Exception('Failed to get AI estimate: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
          _showMiniGame = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get AI estimate: $e')),
        );
      }
    }
  }

  // Free text input widget
  Widget _buildFreeTextInput() {
    return Column(
      children: [
        TextField(
          controller: _freeTextController,
          decoration: InputDecoration(
            labelText: 'Enter ingredients (comma-separated)',
            hintText: 'e.g. 100g banana, 200g cinnamon, 1 apple',
            border: const OutlineInputBorder(),
            helperText: 'Type ingredients and press comma to add',
          ),
          onChanged: (value) {
            if (value.endsWith(',')) {
              final ingredient = value.substring(0, value.length - 1).trim();
              if (ingredient.isNotEmpty) {
                setState(() {
                  _freeTextIngredients.add(ingredient);
                  _freeTextController.clear();
                });
              }
            }
          },
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
                backgroundColor: Colors.blue.shade100,
              );
            }).toList(),
          ),
        if (_freeTextIngredients.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _calculatingAi ? null : _calculateAllWithAi,
              icon: _calculatingAi
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label:
                  Text(_calculatingAi ? 'Calculating...' : 'Calculate with AI'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (_calculatingAi && !_showMiniGame) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _showMiniGame = true;
                });
              },
              icon: const Icon(Icons.sports_esports),
              label: const Text('Play Ping Pong While You Wait'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade600,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ],
    );
  }

  // Calculate all free text ingredients with AI
  Future<void> _calculateAllWithAi() async {
    if (_freeTextIngredients.isEmpty) return;

    setState(() {
      _calculatingAi = true;
    });

    final results = <_IngredientEntry>[];
    int successCount = 0;
    int failCount = 0;

    for (final ingredient in _freeTextIngredients) {
      try {
        final Uri requestUri =
            Uri.parse('https://fatsecret-proxy.onrender.com/estimate');

        final response = await http.post(
          requestUri,
          headers: {
            'Content-Type': 'application/json',
          },
          body: json.encode({'food': ingredient}),
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> jsonResponse = json.decode(response.body);

          final foodName = jsonResponse['name'] ?? ingredient;
          final mode = jsonResponse['mode'] ?? 'grams';
          final servingGrams = mode == 'serving'
              ? (jsonResponse['estimated_serving_grams'] ?? 100)
              : (jsonResponse['grams'] ?? 100);
          final servingDescription = jsonResponse['serving_description'];

          final totalCalories = (jsonResponse['calories'] ?? 0).toDouble();
          final totalProtein = (jsonResponse['protein'] ?? 0).toDouble();
          final totalCarbs = (jsonResponse['carbs'] ?? 0).toDouble();
          final totalFat = (jsonResponse['fat'] ?? 0).toDouble();

          final portion = '${servingGrams}g';

          String displayName;
          if (servingDescription != null && servingDescription.isNotEmpty) {
            displayName = servingDescription;
          } else {
            displayName = '$foodName (estimated serving size ${servingGrams}g)';
          }

          results.add(_IngredientEntry(
            name: displayName,
            calories: totalCalories,
            protein: totalProtein,
            carbs: totalCarbs,
            fat: totalFat,
            portion: portion,
          ));
          successCount++;
        } else {
          failCount++;
        }
      } catch (e) {
        failCount++;
      }

      // Small delay between requests to avoid overwhelming the API
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (mounted) {
      setState(() {
        _ingredients.addAll(results);
        _freeTextIngredients.clear();
        _calculatingAi = false;
        _showMiniGame = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Added $successCount ingredients${failCount > 0 ? ', $failCount failed' : ''}'),
        ),
      );
    }
  }
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
