import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/pages/add_food_page.dart';
import 'package:namer_app/pages/add_recipe_page.dart';
import 'package:namer_app/pages/login_or_register_page.dart';
import 'package:namer_app/pages/menu_page.dart';
import 'package:namer_app/pages/recipes_page.dart';
import 'package:namer_app/pages/user_settings_page.dart';
import 'package:namer_app/services/category_service.dart';

class HomePage extends StatefulWidget {
  final bool addFoodAnimation;
  final bool hideNav;

  const HomePage(
      {Key? key, this.addFoodAnimation = false, this.hideNav = false})
      : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _SelectExistingRecipePage extends StatelessWidget {
  const _SelectExistingRecipePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Recipe')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('recipes')
            .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No recipes yet.'));
          }

          final recipes = snapshot.data!.docs;
          // Sort by created_at descending (client-side)
          recipes.sort((a, b) {
            final timeA = a['created_at'] as Timestamp?;
            final timeB = b['created_at'] as Timestamp?;
            if (timeA == null || timeB == null) return 0;
            return timeB.compareTo(timeA);
          });

          return ListView.builder(
            itemCount: recipes.length,
            itemBuilder: (context, index) {
              final recipe = recipes[index];
              final calories = recipe['total_calories'] as num? ?? 0;
              return ListTile(
                title: Text(recipe['name'] ?? 'Recipe'),
                subtitle: Text('${calories.toStringAsFixed(0)} kcal'),
                trailing: const Icon(Icons.add_circle_outline,
                    color: Color(0xFF6366F1)),
                onTap: () {
                  Navigator.pop(context, recipe.id);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _HomePageState extends State<HomePage> {
  List<QueryDocumentSnapshot> _foodDocs = [];
  final List<String> _tabs = ['Brekkie', 'Lunch', 'Dinner', 'Snacks'];
  int _creditCardRefreshKey = 0;
  bool _isLoading = true;
  bool _deleteMode = false;

  // Category totals tracking
  bool _showMacrosTotal = false;
  int _totalCalories = 0;
  double _totalProtein = 0.0;
  double _totalCarbs = 0.0;
  double _totalFat = 0.0;
  String? _lastFetchedCategory;

  // Individual food item macro visibility tracking
  Map<String, bool> _foodMacrosVisibility = {};

  String _roundMacro(dynamic value) {
    final numVal =
        (value is num) ? value.toDouble() : double.tryParse('$value') ?? 0.0;
    return numVal.toStringAsFixed(1).endsWith('.5')
        ? numVal.ceil().toString()
        : numVal.round().toString();
  }

  @override
  void initState() {
    super.initState();
    _initializeHome();
  }

  Future<void> _initializeHome() async {
    await populateFoodItems();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> populateFoodItems() async {
    try {
      final categoryService =
          Provider.of<CategoryService>(context, listen: false);
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_food')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final filteredDocs = querySnapshot.docs
            .where((doc) =>
                (doc['foodCategory'] ?? 'Brekkie') ==
                categoryService.selectedCategory)
            .toList();

        if (mounted) {
          setState(() {
            _foodDocs = filteredDocs;
            // Reset individual food macro visibility when category changes
            _foodMacrosVisibility.clear();
            for (var doc in filteredDocs) {
              _foodMacrosVisibility[doc.id] = false;
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _foodDocs = [];
            _foodMacrosVisibility.clear();
          });
        }
      }
    } catch (e) {
      print('Error populating food items: $e');
      if (mounted) {
        setState(() {
          _foodDocs = [];
          _foodMacrosVisibility.clear();
        });
      }
    }
  }

  Future<void> deleteFood() async {
    try {
      QuerySnapshot userFoodSnapshot = await FirebaseFirestore.instance
          .collection('user_food')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();

      num caloriesToReAdd = 0;
      double proteinToReAdd = 0;
      double carbsToReAdd = 0;
      double fatsToReAdd = 0;

      for (var doc in userFoodSnapshot.docs) {
        caloriesToReAdd += doc['food_calories'];
        proteinToReAdd += (doc['food_protein'] as num?)?.toDouble() ?? 0.0;
        carbsToReAdd += (doc['food_carbs'] as num?)?.toDouble() ?? 0.0;
        fatsToReAdd += (doc['food_fat'] as num?)?.toDouble() ?? 0.0;
        batch.delete(doc.reference);
      }

      await batch.commit();

      QuerySnapshot userDataSnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();

      final docRef = FirebaseFirestore.instance
          .collection('user_data')
          .doc(userDataSnapshot.docs.first.id);

      final updatedCalories =
          userDataSnapshot.docs.first['calories'] + caloriesToReAdd;

      await docRef.update({
        'calories': updatedCalories,
        'protein_balance':
            ((userDataSnapshot.docs.first['protein_balance'] as num?)
                        ?.toDouble() ??
                    (userDataSnapshot.docs.first['protein_goal'] as num?)
                        ?.toDouble() ??
                    0.0) +
                proteinToReAdd,
        'carbs_balance': ((userDataSnapshot.docs.first['carbs_balance'] as num?)
                    ?.toDouble() ??
                (userDataSnapshot.docs.first['carbs_goal'] as num?)
                    ?.toDouble() ??
                0.0) +
            carbsToReAdd,
        'fats_balance': ((userDataSnapshot.docs.first['fats_balance'] as num?)
                    ?.toDouble() ??
                (userDataSnapshot.docs.first['fats_goal'] as num?)
                    ?.toDouble() ??
                0.0) +
            fatsToReAdd,
      });

      // Reset category totals
      final categoryService =
          Provider.of<CategoryService>(context, listen: false);
      await _resetCategoryTotals(categoryService.selectedCategory);

      // Refresh the list of food items
      await populateFoodItems();

      // Trigger CreditCard refresh
      setState(() {
        _creditCardRefreshKey++;
      });
    } catch (e) {
      print('Error deleting food items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting food: $e')),
        );
      }
    }
  }

  Future<void> signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginOrRegisterPage()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  Future<void> navigateToProfilePage() async {
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => UserSettingsPage()),
      );
    }
  }

  Future<void> _deleteFoodItem(String docId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final categoryService =
          Provider.of<CategoryService>(context, listen: false);
      final currentCategory = categoryService.selectedCategory;

      // Get the food item data before deleting it
      final foodDocSnapshot =
          await firestore.collection('user_food').doc(docId).get();

      if (!foodDocSnapshot.exists) {
        throw Exception('Food item not found');
      }

      final foodData = foodDocSnapshot.data() as Map<String, dynamic>;
      final calories = (foodData['food_calories'] as num?)?.toDouble() ?? 0;
      final protein = (foodData['food_protein'] as num?)?.toDouble() ?? 0;
      final carbs = (foodData['food_carbs'] as num?)?.toDouble() ?? 0;
      final fat = (foodData['food_fat'] as num?)?.toDouble() ?? 0;

      // Delete the food item
      await firestore.collection('user_food').doc(docId).delete();

      // Update user balances (add back the calories/macros since we're removing consumption)
      final userDataSnapshot = await firestore
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();

      if (userDataSnapshot.docs.isNotEmpty) {
        final doc = userDataSnapshot.docs.first;
        final docRef = doc.reference;
        final data = doc.data() as Map<String, dynamic>;

        final currentCalories = data['calories'];
        double newCalories;
        if (currentCalories is int) {
          newCalories = currentCalories.toDouble() + calories;
        } else if (currentCalories is double) {
          newCalories = currentCalories + calories;
        } else if (currentCalories is String) {
          newCalories = (double.tryParse(currentCalories) ?? 0) + calories;
        } else {
          newCalories = 0 + calories;
        }

        double proteinBal = (data['protein_balance'] as num?)?.toDouble() ??
            (data['protein_goal'] as num?)?.toDouble() ??
            0.0;
        double carbsBal = (data['carbs_balance'] as num?)?.toDouble() ??
            (data['carbs_goal'] as num?)?.toDouble() ??
            0.0;
        double fatsBal = (data['fats_balance'] as num?)?.toDouble() ??
            (data['fats_goal'] as num?)?.toDouble() ??
            0.0;

        proteinBal += protein;
        carbsBal += carbs;
        fatsBal += fat;

        await docRef.update({
          'calories': newCalories,
          'protein_balance': proteinBal,
          'carbs_balance': carbsBal,
          'fats_balance': fatsBal,
        });
      }

      // Update category totals
      final categoryTotalDocRef = firestore
          .collection('category_totals')
          .doc('${userId}_$currentCategory');
      final categoryTotalSnapshot = await categoryTotalDocRef.get();

      if (categoryTotalSnapshot.exists) {
        await categoryTotalDocRef.update({
          'total_calories':
              (categoryTotalSnapshot['total_calories'] as num? ?? 0) - calories,
          'total_protein':
              (categoryTotalSnapshot['total_protein'] as num? ?? 0) - protein,
          'total_carbs':
              (categoryTotalSnapshot['total_carbs'] as num? ?? 0) - carbs,
          'total_fat': (categoryTotalSnapshot['total_fat'] as num? ?? 0) - fat,
        });
      }

      // Refresh the UI
      await populateFoodItems();
      await _fetchCategoryTotals(currentCategory);

      if (mounted) {
        setState(() {
          _creditCardRefreshKey++;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Food item removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting food item: $e')),
        );
      }
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final categoryService =
            Provider.of<CategoryService>(context, listen: false);
        final currentCategory = categoryService.selectedCategory;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.local_dining),
                title: const Text('Add Food Item'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AddFoodPage()),
                  );
                  await populateFoodItems();
                  setState(() => _creditCardRefreshKey++);
                },
              ),
              ListTile(
                leading: const Icon(Icons.restaurant_menu),
                title: const Text('Add New Recipe'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddRecipePage(
                        addToHome: true,
                        homeCategory: currentCategory,
                      ),
                    ),
                  );
                  await populateFoodItems();
                  setState(() => _creditCardRefreshKey++);
                },
              ),
              ListTile(
                leading: const Icon(Icons.library_books),
                title: const Text('Add Existing Recipe'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final recipeId = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _SelectExistingRecipePage(),
                    ),
                  );
                  if (recipeId != null) {
                    await _addRecipeToHome(recipeId, currentCategory);
                    await populateFoodItems();
                    setState(() => _creditCardRefreshKey++);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addRecipeToHome(String recipeId, String category) async {
    final firestore = FirebaseFirestore.instance;
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final recipeDoc = await firestore.collection('recipes').doc(recipeId).get();
    if (!recipeDoc.exists) return;
    final data = recipeDoc.data()!;

    // Get serving size from recipe, default to "1 Serving" if not present
    final servingSize = data['serving_size'] as String? ?? 'Per 1 Serving';

    await firestore.collection('user_food').add({
      'user_id': userId,
      'food_description': 'Recipe: ${data['name'] ?? ''}',
      'food_calories': data['total_calories'] ?? 0,
      'food_protein': (data['total_protein'] as num?)?.toDouble() ?? 0,
      'food_carbs': (data['total_carbs'] as num?)?.toDouble() ?? 0,
      'food_fat': (data['total_fat'] as num?)?.toDouble() ?? 0,
      'food_portion': servingSize,
      'foodCategory': category,
      'recipe_id': recipeId,
      'is_recipe': true,
      'created_at': FieldValue.serverTimestamp(),
    });

    final recipeCalories = (data['total_calories'] as num?)?.toDouble() ?? 0;
    final recipeProtein = (data['total_protein'] as num?)?.toDouble() ?? 0;
    final recipeCarbs = (data['total_carbs'] as num?)?.toDouble() ?? 0;
    final recipeFat = (data['total_fat'] as num?)?.toDouble() ?? 0;

    // Apply to user balances (subtract when adding)
    await _applyRecipeToUserBalances(
      calories: recipeCalories,
      protein: recipeProtein,
      carbs: recipeCarbs,
      fat: recipeFat,
    );

    // Update category totals
    final docRef =
        firestore.collection('category_totals').doc('${userId}_$category');
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      await docRef.update({
        'total_calories':
            (docSnapshot['total_calories'] as num? ?? 0) + recipeCalories,
        'total_protein':
            (docSnapshot['total_protein'] as num? ?? 0) + recipeProtein,
        'total_carbs': (docSnapshot['total_carbs'] as num? ?? 0) + recipeCarbs,
        'total_fat': (docSnapshot['total_fat'] as num? ?? 0) + recipeFat,
      });
    } else {
      await docRef.set({
        'total_calories': recipeCalories,
        'total_protein': recipeProtein,
        'total_carbs': recipeCarbs,
        'total_fat': recipeFat,
      });
    }

    // Refresh displayed totals
    await _fetchCategoryTotals(category);
    setState(() {
      _creditCardRefreshKey++;
    });
  }

  Future<void> _applyRecipeToUserBalances({
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
  }) async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final userDataSnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();

      if (userDataSnapshot.docs.isEmpty) return;

      final doc = userDataSnapshot.docs.first;
      final docRef = doc.reference;
      final data = doc.data() as Map<String, dynamic>;

      final currentCalories = data['calories'];
      double newCalories;
      if (currentCalories is int) {
        newCalories = currentCalories.toDouble() - calories;
      } else if (currentCalories is double) {
        newCalories = currentCalories - calories;
      } else if (currentCalories is String) {
        newCalories = (double.tryParse(currentCalories) ?? 0) - calories;
      } else {
        newCalories = 0 - calories;
      }

      double proteinBal = (data['protein_balance'] as num?)?.toDouble() ??
          (data['protein_goal'] as num?)?.toDouble() ??
          0.0;
      double carbsBal = (data['carbs_balance'] as num?)?.toDouble() ??
          (data['carbs_goal'] as num?)?.toDouble() ??
          0.0;
      double fatsBal = (data['fats_balance'] as num?)?.toDouble() ??
          (data['fats_goal'] as num?)?.toDouble() ??
          0.0;

      proteinBal -= protein;
      carbsBal -= carbs;
      fatsBal -= fat;

      await docRef.update({
        'calories': newCalories,
        'protein_balance': proteinBal,
        'carbs_balance': carbsBal,
        'fats_balance': fatsBal,
      });
    } catch (e) {
      print('Error applying recipe balances: $e');
    }
  }

  Future<void> _fetchCategoryTotals(String category) async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final docRef = FirebaseFirestore.instance
          .collection('category_totals')
          .doc('${userId}_$category');

      final docSnapshot = await docRef.get();

      if (docSnapshot.exists && mounted) {
        setState(() {
          _totalCalories =
              (docSnapshot['total_calories'] as num?)?.toInt() ?? 0;
          _totalProtein =
              (docSnapshot['total_protein'] as num?)?.toDouble() ?? 0.0;
          _totalCarbs = (docSnapshot['total_carbs'] as num?)?.toDouble() ?? 0.0;
          _totalFat = (docSnapshot['total_fat'] as num?)?.toDouble() ?? 0.0;
          _lastFetchedCategory = category;
        });
      } else if (mounted) {
        setState(() {
          _totalCalories = 0;
          _totalProtein = 0.0;
          _totalCarbs = 0.0;
          _totalFat = 0.0;
          _lastFetchedCategory = category;
        });
      }
    } catch (e) {
      print('Error fetching category totals: $e');
    }
  }

  Future<void> _resetCategoryTotals(String category) async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final docRef = FirebaseFirestore.instance
          .collection('category_totals')
          .doc('${userId}_$category');

      await docRef.set({
        'total_calories': 0,
        'total_protein': 0.0,
        'total_carbs': 0.0,
        'total_fat': 0.0,
      });

      if (mounted) {
        setState(() {
          _totalCalories = 0;
          _totalProtein = 0.0;
          _totalCarbs = 0.0;
          _totalFat = 0.0;
          _showMacrosTotal = false;
        });
      }
    } catch (e) {
      print('Error resetting category totals: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          color: Colors.white,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
        bottomNavigationBar: widget.hideNav
            ? null
            : Container(
                color: Colors.white,
                height: 56,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MenuPage(),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                  color: Colors.grey.shade200, width: 1),
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.person, size: 24),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                                color: Colors.grey.shade200, width: 1),
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.credit_card,
                              size: 24, color: Color(0xFF6366F1)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RecipesPage()),
                          );
                        },
                        child: Container(
                          child: const Center(
                            child: Icon(Icons.restaurant, size: 24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Container(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                Center(
                  child: CreditCard(
                    key: ValueKey(_creditCardRefreshKey),
                    onToggleMacros: (showMacros) {
                      setState(() {
                        _showMacrosTotal = showMacros;
                        for (var doc in _foodDocs) {
                          _foodMacrosVisibility[doc.id] = showMacros;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Tabs
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Consumer<CategoryService>(
                      builder: (context, categoryService, _) {
                        return Row(
                          children: _tabs.map((tab) {
                            bool isSelected =
                                categoryService.selectedCategory == tab;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () {
                                  categoryService.setSelectedCategory(tab);
                                  populateFoodItems();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF6366F1)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFF6366F1),
                                      width: isSelected ? 0 : 2,
                                    ),
                                  ),
                                  child: Text(
                                    tab,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFF6366F1),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.indigo.shade600,
                              Colors.blue.shade700,
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Category Totals Header
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _showMacrosTotal = !_showMacrosTotal;
                                    // When card is tapped, flip all food items to match card state
                                    for (var doc in _foodDocs) {
                                      _foodMacrosVisibility[doc.id] =
                                          _showMacrosTotal;
                                    }
                                  });
                                },
                                child: Consumer<CategoryService>(
                                  builder: (context, categoryService, _) {
                                    // Fetch totals when category changes
                                    if (_lastFetchedCategory !=
                                        categoryService.selectedCategory) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        _fetchCategoryTotals(
                                            categoryService.selectedCategory);
                                      });
                                    }

                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color:
                                                Colors.white.withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Total',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                if (!_showMacrosTotal)
                                                  Text(
                                                    '$_totalCalories kcal',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                    ),
                                                  )
                                                else
                                                  Text(
                                                    'Protein: ${_roundMacro(_totalProtein)}g | Carbs: ${_roundMacro(_totalCarbs)}g | Fat: ${_roundMacro(_totalFat)}g',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  _showMacrosTotal
                                                      ? Icons.fastfood
                                                      : Icons.show_chart,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _foodDocs.length,
                                  itemBuilder: (context, index) {
                                    final doc = _foodDocs[index];
                                    return Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.white.withOpacity(0.95),
                                            Colors.blue.shade50
                                                .withOpacity(0.9),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            // Toggle only this food item's macro visibility
                                            _foodMacrosVisibility[doc.id] =
                                                !(_foodMacrosVisibility[
                                                        doc.id] ??
                                                    false);
                                          });
                                        },
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          title: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                doc["food_description"],
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              if (doc["food_portion"] != null &&
                                                  (doc["food_portion"]
                                                          as String)
                                                      .isNotEmpty)
                                                Text(
                                                  '(${doc["food_portion"]})',
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
                                              if (_deleteMode)
                                                GestureDetector(
                                                  onTap: () async {
                                                    await _deleteFoodItem(
                                                        doc.id);
                                                  },
                                                  child: Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.red.shade400,
                                                    size: 24,
                                                  ),
                                                )
                                              else
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 12,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        Colors.orange.shade400,
                                                        Colors.orange.shade600,
                                                      ],
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            20),
                                                  ),
                                                  child: (_foodMacrosVisibility[
                                                              doc.id] ??
                                                          false)
                                                      ? Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Text(
                                                              '${_roundMacro(doc["food_protein"])}g Protein',
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 10,
                                                              ),
                                                            ),
                                                            Text(
                                                              '${_roundMacro(doc["food_carbs"])}g Carbs',
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 10,
                                                              ),
                                                            ),
                                                            Text(
                                                              '${_roundMacro(doc["food_fat"])}g Fat',
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 10,
                                                              ),
                                                            ),
                                                          ],
                                                        )
                                                      : Text(
                                                          '${doc["food_calories"]} kcal',
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: <Widget>[
                                  FloatingActionButton(
                                    onPressed: () {
                                      setState(() {
                                        _deleteMode = !_deleteMode;
                                      });
                                    },
                                    heroTag: 'delete',
                                    backgroundColor: _deleteMode
                                        ? Colors.red.shade600
                                        : Colors.red.shade400,
                                    child: Icon(_deleteMode
                                        ? Icons.close
                                        : Icons.delete_outline),
                                  ),
                                  FloatingActionButton(
                                    onPressed: _showAddOptions,
                                    heroTag: 'add',
                                    backgroundColor: Colors.green.shade400,
                                    child: const Icon(Icons.add),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.hideNav
          ? null
          : Container(
              color: Colors.white,
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MenuPage(),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                                color: Colors.grey.shade200, width: 1),
                          ),
                        ),
                        child: Center(
                          child: Icon(Icons.person, size: 24),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right:
                              BorderSide(color: Colors.grey.shade200, width: 1),
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.credit_card,
                            size: 24, color: Color(0xFF6366F1)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RecipesPage()),
                        );
                      },
                      child: Container(
                        child: const Center(
                          child: Icon(Icons.restaurant, size: 24),
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
