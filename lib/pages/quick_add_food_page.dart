import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/components/mini_game.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class QuickAddFoodPage extends StatefulWidget {
  const QuickAddFoodPage({Key? key}) : super(key: key);

  @override
  State<QuickAddFoodPage> createState() => _QuickAddFoodPageState();
}

class _QuickAddFoodPageState extends State<QuickAddFoodPage> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _ingredients = [];
  final List<Map<String, dynamic>> _calculatedItems = [];
  bool _calculating = false;
  bool _calculated = false;
  bool _saving = false;
  bool _showMiniGame = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _totalCalories {
    return _calculatedItems.fold(
        0.0, (sum, item) => sum + (item['calories'] as num).toDouble());
  }

  double get _totalProtein {
    return _calculatedItems.fold(
        0.0, (sum, item) => sum + (item['protein'] as num).toDouble());
  }

  double get _totalCarbs {
    return _calculatedItems.fold(
        0.0, (sum, item) => sum + (item['carbs'] as num).toDouble());
  }

  double get _totalFat {
    return _calculatedItems.fold(
        0.0, (sum, item) => sum + (item['fat'] as num).toDouble());
  }

  Future<void> _calculateWithAI() async {
    if (_ingredients.isEmpty) return;

    setState(() {
      _calculating = true;
      _showMiniGame = false;
    });

    final results = <Map<String, dynamic>>[];
    int successCount = 0;
    int failCount = 0;

    for (final ingredient in _ingredients) {
      try {
        final Uri requestUri =
            Uri.parse('https://fatsecret-proxy.onrender.com/food/resolve');

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

          final totalCalories =
              ((jsonResponse['calories'] ?? 0) as num).toDouble();
          final totalProtein =
              ((jsonResponse['protein'] ?? 0) as num).toDouble();
          final totalCarbs = ((jsonResponse['carbs'] ?? 0) as num).toDouble();
          final totalFat = ((jsonResponse['fat'] ?? 0) as num).toDouble();

          final portion = '${servingGrams}g';

          // Use the user's original input string
          final displayName = ingredient;

          results.add({
            'name': displayName,
            'calories': totalCalories,
            'protein': totalProtein,
            'carbs': totalCarbs,
            'fat': totalFat,
            'portion': portion,
          });
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
        _calculatedItems.addAll(results);
        _calculating = false;
        _calculated = true;
        _showMiniGame = false;
      });

      if (failCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Calculated $successCount items${failCount > 0 ? ', $failCount failed' : ''}'),
          ),
        );
      }
    }
  }

  Future<void> _saveItems() async {
    if (_calculatedItems.isEmpty) return;

    setState(() {
      _saving = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final categoryService =
          Provider.of<CategoryService>(context, listen: false);
      final category = categoryService.selectedCategory;

      // Create a batch to add all items
      final batch = firestore.batch();

      double totalCaloriesConsumed = 0;
      double totalProteinConsumed = 0;
      double totalCarbsConsumed = 0;
      double totalFatConsumed = 0;

      for (final item in _calculatedItems) {
        final docRef = firestore.collection('user_food').doc();

        batch.set(docRef, {
          'user_id': userId,
          'food_description': item['name'],
          'food_portion': item['portion'],
          'food_calories': item['calories'].round(),
          'food_protein': item['protein'],
          'food_carbs': item['carbs'],
          'food_fat': item['fat'],
          'foodCategory': category,
          'time_added': DateTime.now(),
        });

        totalCaloriesConsumed += item['calories'];
        totalProteinConsumed += item['protein'];
        totalCarbsConsumed += item['carbs'];
        totalFatConsumed += item['fat'];
      }

      await batch.commit();

      // Mark first time logger achievement
      await AchievementService.markFirstTimeLogger(userId);

      // Update user balances
      final userDataSnapshot = await firestore
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .get(const GetOptions(source: Source.server));

      if (userDataSnapshot.docs.isNotEmpty) {
        final docId = userDataSnapshot.docs.first.id;
        final docRef = firestore.collection('user_data').doc(docId);
        final data = userDataSnapshot.docs.first.data();

        final currentCalories = (data['calories'] as num?)?.toDouble() ?? 0.0;
        final newCalories = currentCalories - totalCaloriesConsumed;

        await docRef.update({
          'calories': newCalories,
          'protein_balance': ((data['protein_balance'] as num?)?.toDouble() ??
                  (data['protein_goal'] as num?)?.toDouble() ??
                  0.0) -
              totalProteinConsumed,
          'carbs_balance': ((data['carbs_balance'] as num?)?.toDouble() ??
                  (data['carbs_goal'] as num?)?.toDouble() ??
                  0.0) -
              totalCarbsConsumed,
          'fats_balance': ((data['fats_balance'] as num?)?.toDouble() ??
                  (data['fats_goal'] as num?)?.toDouble() ??
                  0.0) -
              totalFatConsumed,
        });
      }

      if (mounted) {
        // Navigate back to homepage with success
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving items: $e')),
        );
      }
    }
  }

  Widget _buildMacroStat(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${value.round()}g',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.grey.shade50,
                  Colors.blue.shade50,
                ],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.fromLTRB(16, topPadding + 12, 16, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF6366F1),
                          const Color(0xFF8B5CF6),
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          color: Colors.white,
                          tooltip: 'Back',
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                'Quick Add Food',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add multiple foods at once',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Input Card
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.restaurant_menu,
                                          color: Color(0xFF6366F1),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Enter Your Foods',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _controller,
                                    decoration: InputDecoration(
                                      labelText: 'Type food and press comma',
                                      hintText:
                                          'e.g. 100g banana, 200g chicken',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      prefixIcon:
                                          const Icon(Icons.add_circle_outline),
                                      helperText:
                                          'Separate each food with a comma (,)',
                                      helperStyle: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      if (value.endsWith(',')) {
                                        final ingredient = value
                                            .substring(0, value.length - 1)
                                            .trim();
                                        if (ingredient.isNotEmpty) {
                                          setState(() {
                                            _ingredients.add(ingredient);
                                            _controller.clear();
                                            _calculated = false;
                                          });
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_ingredients.isNotEmpty) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.shopping_basket,
                                    size: 18,
                                    color: Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Items to Calculate (${_ingredients.length})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children:
                                    _ingredients.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final ingredient = entry.value;
                                  return Chip(
                                    label: Text(
                                      ingredient,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    deleteIcon:
                                        const Icon(Icons.close, size: 16),
                                    onDeleted: () {
                                      setState(() {
                                        _ingredients.removeAt(idx);
                                        _calculated = false;
                                      });
                                    },
                                    backgroundColor: const Color(0xFF6366F1)
                                        .withOpacity(0.15),
                                    side: BorderSide(
                                      color: const Color(0xFF6366F1)
                                          .withOpacity(0.3),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                            if (_calculatedItems.isEmpty &&
                                _ingredients.isEmpty) ...[
                              // Empty State
                              Container(
                                margin: const EdgeInsets.only(top: 32),
                                padding: const EdgeInsets.all(32),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.add_shopping_cart,
                                      size: 64,
                                      color: Colors.grey.shade300,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No items yet',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Start typing your foods above and\nseparate them with commas',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade600,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (_calculatedItems.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 20,
                                    color: const Color(0xFF10B981),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Calculated Results',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ..._calculatedItems.map((item) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        const Color(0xFF6366F1),
                                        const Color(0xFF8B5CF6),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF6366F1)
                                            .withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    leading: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.restaurant,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      item['name'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'P: ${item['protein'].round()}g • C: ${item['carbs'].round()}g • F: ${item['fat'].round()}g',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 12,
                                      ),
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '${item['calories'].round()} kcal',
                                        style: TextStyle(
                                          color: const Color(0xFF6366F1),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                              const SizedBox(height: 16),
                              // Total Summary
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFFF59E0B),
                                      const Color(0xFFEF4444),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFF59E0B)
                                          .withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.white.withOpacity(0.2),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.local_fire_department,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Expanded(
                                          child: Text(
                                            'Total Nutrition',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${_totalCalories.round()} kcal',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      height: 1,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        _buildMacroStat(
                                            'Protein',
                                            _totalProtein,
                                            Colors.blue.shade300),
                                        _buildMacroStat('Carbs', _totalCarbs,
                                            Colors.green.shade300),
                                        _buildMacroStat('Fats', _totalFat,
                                            Colors.purple.shade300),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ]),
                    ),
                  ),
                  // Bottom Action Bar
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: ElevatedButton.icon(
                                onPressed: (_ingredients.isEmpty ||
                                        _calculating ||
                                        (_calculated &&
                                            _calculatedItems.length ==
                                                _ingredients.length))
                                    ? null
                                    : _calculateWithAI,
                                icon: _calculating
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : const Icon(Icons.auto_awesome, size: 20),
                                label: Text(
                                  _calculating
                                      ? 'Calculating...'
                                      : 'Calculate Via AI',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              height: 52,
                              width: 52,
                              decoration: BoxDecoration(
                                color: (!_calculated ||
                                        _saving ||
                                        _calculatedItems.isEmpty)
                                    ? Colors.grey.shade300
                                    : const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: (!_calculated ||
                                        _saving ||
                                        _calculatedItems.isEmpty)
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: const Color(0xFF10B981)
                                              .withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                              ),
                              child: ElevatedButton(
                                onPressed: (!_calculated ||
                                        _saving ||
                                        _calculatedItems.isEmpty)
                                    ? null
                                    : _saveItems,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.all(12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _saving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : const Icon(Icons.check, size: 24),
                              ),
                            ),
                          ],
                        ),
                        if (_calculating && !_showMiniGame) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _showMiniGame = true;
                                });
                              },
                              icon: const Icon(Icons.sports_esports, size: 18),
                              label: const Text(
                                'Play Ping Pong While You Wait',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple.shade600,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_calculating && _showMiniGame) const PingPongGame(),
        ],
      ),
    );
  }
}
