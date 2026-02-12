import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/components/mini_game.dart';
import 'package:namer_app/pages/fat_secret_api.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/pages/main_shell.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AddFoodPage extends StatefulWidget {
  AddFoodPage({
    super.key,
  });

  @override
  State<AddFoodPage> createState() => _AddFoodPageState();
}

class _AddFoodPageState extends State<AddFoodPage> {
  final foodController = TextEditingController();
  final FatSecretApi _api = FatSecretApi();
  Foods? results;

  // Store food data instead of built widgets
  List<Map<String, dynamic>> foodListData = [];

  bool hideCard = true;
  bool _isTextFieldTapped = false;
  bool _isLoading = false;
  bool _isAiLoading = false;
  bool _showMiniGame = false;
  bool isEmpty = true;

  // Portion editing state
  int? _editingFoodIndex;
  late TextEditingController _portionController;
  Map<int, String> _originalPortions =
      {}; // Track original portion for each food
  Map<int, Map<String, double>> _foodMacros = {}; // Track original macros

  final List<String> _categories = ['Brekkie', 'Lunch', 'Dinner', 'Snacks'];

  @override
  void initState() {
    super.initState();
    _portionController = TextEditingController();
  }

  @override
  void dispose() {
    // Ensure the text controllers are properly disposed of
    foodController.dispose();
    _portionController.dispose();
    super.dispose();
  }

  Future<void> saveData(String foodDescription, int foodCalories,
      double foodProtein, double foodCarbs, double foodFat,
      {String foodPortion = ''}) async {
    try {
      final categoryService =
          Provider.of<CategoryService>(context, listen: false);
      final category = categoryService.selectedCategory;

      await FirebaseFirestore.instance.collection('user_food').add({
        'user_id': FirebaseAuth.instance.currentUser!.uid,
        'food_description': foodDescription,
        'food_portion': foodPortion,
        'food_calories': foodCalories,
        'food_protein': foodProtein,
        'food_carbs': foodCarbs,
        'food_fat': foodFat,
        'foodCategory': category,
        'time_added': DateTime.now()
      });

      await AchievementService.markFirstTimeLogger(
        FirebaseAuth.instance.currentUser!.uid,
      );

      // Update category totals
      await _updateCategoryTotals(category);

      // Deduct from user balances
      await updateCalories(foodCalories);
      await updateMacros(foodProtein, foodCarbs, foodFat);
    } catch (e) {
      // Error adding user food
    }
  }

  Future<void> _updateCategoryTotals(String category) async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      // Fetch all foods in this category
      QuerySnapshot foodSnapshot = await FirebaseFirestore.instance
          .collection('user_food')
          .where('user_id', isEqualTo: userId)
          .where('foodCategory', isEqualTo: category)
          .get();

      // Calculate totals
      int totalCalories = 0;
      double totalProtein = 0;
      double totalCarbs = 0;
      double totalFat = 0;

      for (var doc in foodSnapshot.docs) {
        totalCalories += (doc['food_calories'] as num?)?.toInt() ?? 0;
        totalProtein += (doc['food_protein'] as num?)?.toDouble() ?? 0;
        totalCarbs += (doc['food_carbs'] as num?)?.toDouble() ?? 0;
        totalFat += (doc['food_fat'] as num?)?.toDouble() ?? 0;
      }

      // Store totals in a category_totals collection
      final totalsRef = FirebaseFirestore.instance
          .collection('category_totals')
          .doc('${userId}_$category');

      await totalsRef.set({
        'user_id': userId,
        'category': category,
        'total_calories': totalCalories,
        'total_protein': totalProtein,
        'total_carbs': totalCarbs,
        'total_fat': totalFat,
        'last_updated': DateTime.now()
      });
    } catch (e) {
      // Error updating category totals
    }
  }

  Future<void> updateCalories(int foodCalories) async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .get(const GetOptions(source: Source.server));

      if (querySnapshot.docs.isNotEmpty) {
        final docId = querySnapshot.docs.first.id;
        final docRef =
            FirebaseFirestore.instance.collection('user_data').doc(docId);
        final currentCalories = querySnapshot.docs.first['calories'];
        int newCalories;
        if (currentCalories is int) {
          newCalories = currentCalories - foodCalories;
        } else if (currentCalories is String) {
          newCalories = int.parse(currentCalories) - foodCalories;
        } else {
          throw Exception(
              "Unexpected 'calories' type: ${currentCalories.runtimeType}");
        }
        await docRef.update({'calories': newCalories});
      }
    } catch (e) {
      // Error updating user data
    }
  }

  Future<void> updateMacros(
      double foodProtein, double foodCarbs, double foodFat) async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .get(const GetOptions(source: Source.server));

      if (querySnapshot.docs.isNotEmpty) {
        final docId = querySnapshot.docs.first.id;
        final docRef =
            FirebaseFirestore.instance.collection('user_data').doc(docId);
        final data = querySnapshot.docs.first.data() as Map<String, dynamic>;

        double proteinBal = (data['protein_balance'] as num?)?.toDouble() ??
            (data['protein_goal'] as num?)?.toDouble() ??
            0.0;
        double carbsBal = (data['carbs_balance'] as num?)?.toDouble() ??
            (data['carbs_goal'] as num?)?.toDouble() ??
            0.0;
        double fatsBal = (data['fats_balance'] as num?)?.toDouble() ??
            (data['fats_goal'] as num?)?.toDouble() ??
            0.0;

        proteinBal -= foodProtein;
        carbsBal -= foodCarbs;
        fatsBal -= foodFat;

        await docRef.update({
          'protein_balance': proteinBal,
          'carbs_balance': carbsBal,
          'fats_balance': fatsBal,
        });
      }
    } catch (e) {
      // Error updating macros
    }
  }

  Future<void> _onButtonPress() async {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    foodListData.clear();
    _originalPortions.clear();
    _foodMacros.clear();
    _editingFoodIndex = null;

    setState(() {
      _isTextFieldTapped = true;
      _isLoading = true;
    });

    final query = foodController.text;

    if (query.isNotEmpty) {
      results = await _api.foodsSearch(query);
      if (!mounted) return;

      setState(() {
        int foodIndex = 0;
        for (var food in results!.food) {
          final portion = _formatAmount(food.foodDescription);
          final calories = int.parse(_formatCalories(food.foodDescription));
          final protein = double.parse(_formatProtein(food.foodDescription));
          final carbs = double.parse(_formatCarbs(food.foodDescription));
          final fat = double.parse(_formatFat(food.foodDescription));

          // Store original values
          _originalPortions[foodIndex] = portion;
          _foodMacros[foodIndex] = {
            'calories': calories.toDouble(),
            'protein': protein,
            'carbs': carbs,
            'fat': fat,
          };

          // Store food data (not built widgets)
          foodListData.add({
            'foodIndex': foodIndex,
            'foodName': food.foodName,
            'portion': portion,
            'calories': calories,
            'protein': protein,
            'carbs': carbs,
            'fat': fat,
            'isAiEstimate': false,
          });

          foodIndex++;
        }
      });

      if (mounted) {
        setState(() {
          isEmpty = false;
          _isLoading = false;
          _showMiniGame = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showMiniGame = false;
        });
      }
    }
  }

  Future<void> _onAiEstimate() async {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    foodListData.clear();
    _originalPortions.clear();
    _foodMacros.clear();
    _editingFoodIndex = null;

    setState(() {
      _isTextFieldTapped = true;
      _isAiLoading = true;
    });

    final query = foodController.text;

    if (query.isNotEmpty) {
      try {
        final Uri requestUri =
            Uri.parse('https://fatsecret-proxy.onrender.com/estimate');

        final response = await http.post(
          requestUri,
          headers: {
            'Content-Type': 'application/json',
          },
          body: json.encode({'food': query}),
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> jsonResponse = json.decode(response.body);

          if (!mounted) return;

          setState(() {
            final foodIndex = 0;
            final foodName = jsonResponse['name'] ?? query;

            // Get the serving size info
            final mode = jsonResponse['mode'] ?? 'grams';
            final servingGrams = mode == 'serving'
                ? (jsonResponse['estimated_serving_grams'] ?? 100)
                : (jsonResponse['grams'] ?? 100);
            final servingDescription = jsonResponse['serving_description'];

            // Total values for the actual portion
            final totalCalories = (jsonResponse['calories'] ?? 0).toInt();
            final totalProtein = (jsonResponse['protein'] ?? 0).toDouble();
            final totalCarbs = (jsonResponse['carbs'] ?? 0).toDouble();
            final totalFat = (jsonResponse['fat'] ?? 0).toDouble();

            final portion = '${servingGrams}g';

            // Create display name with serving info
            String displayName;
            if (servingDescription != null && servingDescription.isNotEmpty) {
              displayName = servingDescription;
            } else {
              displayName =
                  '$foodName (estimated serving size ${servingGrams}g)';
            }

            _originalPortions[foodIndex] = portion;
            _foodMacros[foodIndex] = {
              'calories': totalCalories.toDouble(),
              'protein': totalProtein,
              'carbs': totalCarbs,
              'fat': totalFat,
            };

            foodListData.add({
              'foodIndex': foodIndex,
              'foodName': displayName,
              'portion': portion,
              'calories': totalCalories,
              'protein': totalProtein,
              'carbs': totalCarbs,
              'fat': totalFat,
              'isAiEstimate': true,
            });
          });

          if (mounted) {
            setState(() {
              isEmpty = false;
              _isAiLoading = false;
              _showMiniGame = false;
            });
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
            SnackBar(content: Text('Failed to get AI estimate')),
          );
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
          _showMiniGame = false;
        });
      }
    }
  }

  /// Start editing a food item
  void _startEditingFood(int foodIndex, String portion) {
    setState(() {
      _editingFoodIndex = foodIndex;
      // Store the original portion unit for later use
      _portionController.text =
          _extractPortionNumber(portion).toStringAsFixed(0);
    });
  }

  /// Cancel editing
  void _cancelEditingFood() {
    setState(() {
      _editingFoodIndex = null;
      _portionController.clear();
    });
  }

  /// Build a food list item with optional edit mode
  Widget _buildFoodListItem({
    required int foodIndex,
    required String foodName,
    required String portion,
    required int calories,
    required double protein,
    required double carbs,
    required double fat,
    bool isAiEstimate = false,
  }) {
    final isEditing = _editingFoodIndex == foodIndex;
    final isOtherItemEditing =
        _editingFoodIndex != null && _editingFoodIndex != foodIndex;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.indigo.shade600,
                Colors.blue.shade700,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Opacity(
            opacity: isOtherItemEditing ? 0.5 : 1.0,
            child: IgnorePointer(
              ignoring: isOtherItemEditing,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatFoodString(foodName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAiEstimate
                          ? '(estimated weight: $portion)'
                          : '(per $portion)',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
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
                    '$calories kcal',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                onTap: () {
                  if (!isOtherItemEditing) {
                    _startEditingFood(foodIndex, portion);
                  }
                },
              ),
            ),
          ),
        ),
        // Edit mode row
        if (isEditing)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.indigo.shade300, width: 1.5),
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
                    controller: _portionController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
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
                // Checkmark button
                GestureDetector(
                  onTap: () async {
                    final newPortion =
                        double.tryParse(_portionController.text) ?? 1.0;
                    final adjustedMacros =
                        _calculateAdjustedMacros(foodIndex, newPortion);
                    final portionUnit = _extractPortionUnit(portion);
                    // Format as "100 g" not "per 100 g"
                    final newPortionDisplay = portionUnit.isNotEmpty
                        ? '$newPortion $portionUnit'
                        : '$newPortion';

                    if (!mounted) return;

                    showDialog(
                      context: context,
                      builder: (context) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      },
                    );

                    await saveData(
                      foodName,
                      adjustedMacros['calories']!.toInt(),
                      adjustedMacros['protein']!,
                      adjustedMacros['carbs']!,
                      adjustedMacros['fat']!,
                      foodPortion: newPortionDisplay,
                    );

                    if (!mounted) return;
                    Navigator.pop(context);

                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MainShell(initialIndex: 1),
                      ),
                      (route) => false,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade500,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // X button
                GestureDetector(
                  onTap: _cancelEditingFood,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade500,
                      shape: BoxShape.circle,
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
  }

  String _formatCalories(String stringToFormat) {
    return stringToFormat.split('Calories: ')[1].split('kcal')[0];
  }

  String _extractMacro(String source, List<String> labels) {
    for (final label in labels) {
      final regex = RegExp('$label\\s*:?\\s*([0-9]+(?:\\.[0-9]+)?)',
          caseSensitive: false);
      final match = regex.firstMatch(source);
      if (match != null) {
        return match.group(1) ?? '0';
      }
    }
    return '0';
  }

  String _formatProtein(String stringToFormat) {
    return _extractMacro(stringToFormat, ['Protein']);
  }

  String _formatCarbs(String stringToFormat) {
    return _extractMacro(stringToFormat, ['Carbs', 'Carbohydrate']);
  }

  String _formatFat(String stringToFormat) {
    return _extractMacro(stringToFormat, ['Fat']);
  }

  String _formatAmount(String stringToFormat) {
    return stringToFormat.split('Per ')[1].split(' -')[0];
  }

  /// Extract the numeric portion from description like "100 g" or "1 banana"
  /// Returns just the number as a string
  double _extractPortionNumber(String portion) {
    final regex = RegExp(r'(\d+(?:\.\d+)?)');
    final match = regex.firstMatch(portion);
    return match != null ? double.parse(match.group(1)!) : 1.0;
  }

  /// Extract the unit from a portion string like "100 g" -> "g" or "1 banana" -> "banana"
  /// Handles both "100 g" and "100g" formats
  String _extractPortionUnit(String portion) {
    // Remove the leading number (including decimals) and any whitespace after it
    return portion
        .trim()
        .replaceFirst(RegExp(r'^\d+(?:\.\d+)?[\s]*'), '')
        .trim();
  }

  /// Calculate adjusted macros based on portion ratio
  /// If original portion was 100g and user changes to 90g, multiply all values by 0.9
  Map<String, double> _calculateAdjustedMacros(
    int foodIndex,
    double newPortion,
  ) {
    final originalPortion =
        _extractPortionNumber(_originalPortions[foodIndex] ?? '1');
    final ratio = newPortion / originalPortion;

    final original = _foodMacros[foodIndex]!;
    return {
      'calories': original['calories']! * ratio,
      'protein': original['protein']! * ratio,
      'carbs': original['carbs']! * ratio,
      'fat': original['fat']! * ratio,
    };
  }

  String _formatFoodString(String input) {
    if (input.length > 35) {
      return '${input.substring(0, 32)}...';
    }
    return input;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Food'),
        elevation: 2,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.indigo.shade50,
              Colors.blue.shade50,
            ],
          ),
        ),
        child: Stack(
          children: [
            ScrollConfiguration(
              behavior:
                  ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: _isTextFieldTapped
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: foodController,
                                  decoration: InputDecoration(
                                    hintText: 'Search for food...',
                                    border: InputBorder.none,
                                    hintStyle: TextStyle(
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () async {
                                  await _onButtonPress();
                                },
                                icon: const Icon(Icons.search),
                                color: const Color(0xFF6366F1),
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
                                  onPressed: () async {
                                    await _onAiEstimate();
                                  },
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
                          ),
                        ),
                      ),
                    ),
                    // Category Selection
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Meal Category',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Consumer<CategoryService>(
                            builder: (context, categoryService, _) {
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _categories.map((category) {
                                    bool isSelected =
                                        categoryService.selectedCategory ==
                                            category;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: GestureDetector(
                                        onTap: () {
                                          categoryService
                                              .setSelectedCategory(category);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF6366F1)
                                                : Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: const Color(0xFF6366F1),
                                              width: isSelected ? 0 : 2,
                                            ),
                                          ),
                                          child: Text(
                                            category,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                  : const Color(0xFF6366F1),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: foodListData.map((foodData) {
                                return _buildFoodListItem(
                                  foodIndex: foodData['foodIndex'],
                                  foodName: foodData['foodName'],
                                  portion: foodData['portion'],
                                  calories: foodData['calories'],
                                  protein: foodData['protein'],
                                  carbs: foodData['carbs'],
                                  fat: foodData['fat'],
                                  isAiEstimate:
                                      foodData['isAiEstimate'] ?? false,
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if ((_isLoading || _isAiLoading) && _showMiniGame)
              const PingPongGame(),
            if ((_isLoading || _isAiLoading) && !_showMiniGame)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _isAiLoading ? Colors.purple.shade400 : Colors.blue,
                      ),
                    ),
                    if (_isAiLoading) ...[
                      const SizedBox(height: 16),
                      Text(
                        'AI is estimating...',
                        style: TextStyle(
                          color: Colors.purple.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showMiniGame = true;
                        });
                      },
                      icon: const Icon(Icons.sports_esports, size: 18),
                      label: const Text('Play Solo Ping Pong'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
