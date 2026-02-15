import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/components/mini_game.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AddFoodPage extends StatefulWidget {
  const AddFoodPage({Key? key}) : super(key: key);

  @override
  State<AddFoodPage> createState() => _AddFoodPageState();
}

class _AddFoodPageState extends State<AddFoodPage> {
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
        _ingredients
            .clear(); // Clear ingredients after calculation to prevent duplicates
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

        final currentCalories = (data['calories'] as num?)?.toDouble() ?? 0;
        final currentProtein =
            (data['protein_balance'] as num?)?.toDouble() ?? 0;
        final currentCarbs = (data['carbs_balance'] as num?)?.toDouble() ?? 0;
        final currentFat = (data['fats_balance'] as num?)?.toDouble() ?? 0;

        await docRef.update({
          'calories': currentCalories - totalCaloriesConsumed,
          'protein_balance': currentProtein - totalProteinConsumed,
          'carbs_balance': currentCarbs - totalCarbsConsumed,
          'fats_balance': currentFat - totalFatConsumed,
        });
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving items: $e')),
        );
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Food Items'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add multiple food items at once',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    labelText: 'Enter foods (comma-separated)',
                    hintText: 'e.g. 100g banana, 200g chicken, 1 apple',
                    border: const OutlineInputBorder(),
                    helperText: 'Add each item with a comma',
                  ),
                  onChanged: (value) {
                    if (value.endsWith(',')) {
                      final ingredient =
                          value.substring(0, value.length - 1).trim();
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
                const SizedBox(height: 16),
                if (_ingredients.isNotEmpty) ...[
                  const Text(
                    'Items to calculate:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _ingredients.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final ingredient = entry.value;
                      return Chip(
                        label: Text(ingredient),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () {
                          setState(() {
                            _ingredients.removeAt(idx);
                            _calculated = false;
                          });
                        },
                        backgroundColor: Colors.green.shade100,
                      );
                    }).toList(),
                  ),
                ],
                if (_calculatedItems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Calculated items:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._calculatedItems.map((item) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.indigo.shade600,
                              Colors.blue.shade700,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          title: Text(
                            item['name'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade400,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${item['calories'].round()} kcal',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Text(
                      'Total Calories Consumed: ${_totalCalories.round()} kcal',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.orange.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: (_ingredients.isEmpty || _calculating)
                            ? null
                            : _calculateWithAI,
                        icon: _calculating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.auto_awesome, size: 20),
                        label: Text(
                          _calculating ? 'Calculating...' : 'Calculate with AI',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (!_calculated ||
                                _saving ||
                                _calculatedItems.isEmpty)
                            ? null
                            : _saveItems,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.check_circle, size: 20),
                        label: Text(
                          _saving ? 'Saving...' : 'Save',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: (!_calculated ||
                                  _saving ||
                                  _calculatedItems.isEmpty)
                              ? Colors.grey.shade300
                              : const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: (!_calculated ||
                                  _saving ||
                                  _calculatedItems.isEmpty)
                              ? 0
                              : 2,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_calculating && !_showMiniGame) ...[
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
            ),
          ),
          if (_calculating && _showMiniGame) const PingPongGame(),
        ],
      ),
    );
  }
}
