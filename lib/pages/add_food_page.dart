import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/pages/fat_secret_api.dart';
import 'package:namer_app/pages/home_page.dart';
import 'package:namer_app/services/category_service.dart';

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
  List<Container> listOfItems = [];

  bool hideCard = true;
  bool _isTextFieldTapped = false;
  bool _isLoading = false;
  bool isEmpty = true;

  final List<String> _categories = ['Brekkie', 'Lunch', 'Dinner', 'Snacks'];

  @override
  void dispose() {
    // Ensure the text controller is properly disposed of
    foodController.dispose();
    super.dispose();
  }

  Future<void> saveData(
    String foodDescription,
    int foodCalories,
    double foodProtein,
    double foodCarbs,
    double foodFat,
  ) async {
    try {
      final categoryService =
          Provider.of<CategoryService>(context, listen: false);
      final category = categoryService.selectedCategory;

      await FirebaseFirestore.instance.collection('user_food').add({
        'user_id': FirebaseAuth.instance.currentUser!.uid,
        'food_description': foodDescription,
        'food_calories': foodCalories,
        'food_protein': foodProtein,
        'food_carbs': foodCarbs,
        'food_fat': foodFat,
        'foodCategory': category,
        'time_added': DateTime.now()
      });

      // Update category totals
      await _updateCategoryTotals(category);

      // Deduct from user balances
      await updateCalories(foodCalories);
      await updateMacros(foodProtein, foodCarbs, foodFat);
    } catch (e) {
      print('Error adding user food: $e');
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
      print('Error updating category totals: $e');
    }
  }

  Future<void> updateCalories(int foodCalories) async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .get();

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
        print('User data updated successfully!');
      } else {
        print('No document found with the provided user_id.');
      }
    } catch (e) {
      print('Error updating user data: $e');
    }
  }

  Future<void> updateMacros(
      double foodProtein, double foodCarbs, double foodFat) async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .get();

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
      print('Error updating macros: $e');
    }
  }

  Future<void> _onButtonPress() async {
    if (!mounted) return; // Ensure the widget is still in the tree
    FocusScope.of(context).unfocus();
    listOfItems = [];

    setState(() {
      _isTextFieldTapped = true;
      _isLoading = true;
    });

    final query = foodController.text;

    if (query.isNotEmpty) {
      results = await _api.foodsSearch(query);
      if (!mounted) return; // Ensure the widget is still in the tree

      setState(() {
        for (var food in results!.food) {
          listOfItems.add(
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
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatFoodString(food.foodName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '(per ${_formatAmount(food.foodDescription)})',
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
                    '${_formatCalories(food.foodDescription)} kcal',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                onTap: () async {
                  if (!mounted) return;
                  final newCaloriesToUpdate =
                      int.parse(_formatCalories(food.foodDescription));
                  final protein =
                      double.parse(_formatProtein(food.foodDescription));
                  final carbs =
                      double.parse(_formatCarbs(food.foodDescription));
                  final fat = double.parse(_formatFat(food.foodDescription));

                  showDialog(
                    context: context,
                    builder: (context) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    },
                  );

                  await saveData(
                      food.foodName, newCaloriesToUpdate, protein, carbs, fat);
                  await updateCalories(newCaloriesToUpdate);

                  if (!mounted) return;
                  Navigator.pop(context);

                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HomePage(
                        addFoodAnimation: true,
                      ),
                    ),
                    (route) => false,
                  );
                },
              ),
            ),
          );
        }
      });

      if (mounted) {
        setState(() {
          isEmpty = false;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
                              children: listOfItems,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
