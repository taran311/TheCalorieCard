import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/pages/add_food_page.dart';
import 'package:namer_app/pages/login_or_register_page.dart';
import 'package:namer_app/pages/user_settings_page.dart';
import 'package:namer_app/services/category_service.dart';

class HomePage extends StatefulWidget {
  final bool addFoodAnimation;

  const HomePage({Key? key, this.addFoodAnimation = false}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<QueryDocumentSnapshot> _foodDocs = [];
  final List<String> _tabs = ['Brekkie', 'Lunch', 'Dinner', 'Snacks'];
  int _creditCardRefreshKey = 0;

  // Category totals tracking
  bool _showMacrosTotal = false;
  int _totalCalories = 0;
  double _totalProtein = 0.0;
  double _totalCarbs = 0.0;
  double _totalFat = 0.0;

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
    populateFoodItems();
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
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _foodDocs = [];
          });
        }
      }
    } catch (e) {
      print('Error populating food items: $e');
      if (mounted) {
        setState(() {
          _foodDocs = [];
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

      for (var doc in userFoodSnapshot.docs) {
        caloriesToReAdd += doc['food_calories'];
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
        });
      } else if (mounted) {
        setState(() {
          _totalCalories = 0;
          _totalProtein = 0.0;
          _totalCarbs = 0.0;
          _totalFat = 0.0;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TheCalorieCard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        elevation: 2,
        actions: [
          IconButton(
            onPressed: () async {
              await navigateToProfilePage();
            },
            icon: const Icon(Icons.person),
          ),
          IconButton(
            onPressed: () async {
              await signOut(context);
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
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
                              Consumer<CategoryService>(
                                builder: (context, categoryService, _) {
                                  // Fetch totals when category changes
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    _fetchCategoryTotals(
                                        categoryService.selectedCategory);
                                  });

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _showMacrosTotal = !_showMacrosTotal;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.3),
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
                                    ),
                                  );
                                },
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
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        title: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                doc["food_description"],
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                                                    BorderRadius.circular(20),
                                              ),
                                              child: _showMacrosTotal
                                                  ? Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          '${_roundMacro(doc["food_protein"])}g Protein',
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                        Text(
                                                          '${_roundMacro(doc["food_carbs"])}g Carbs',
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                        Text(
                                                          '${_roundMacro(doc["food_fat"])}g Fat',
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  : Text(
                                                      '${doc["food_calories"]} kcal',
                                                      style: const TextStyle(
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
                                    onPressed: () async {
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (BuildContext context) {
                                          return const Center(
                                            child: CircularProgressIndicator(),
                                          );
                                        },
                                      );

                                      try {
                                        await deleteFood();
                                      } finally {
                                        if (mounted) Navigator.pop(context);
                                      }
                                    },
                                    heroTag: 'delete',
                                    backgroundColor: Colors.red.shade400,
                                    child: const Icon(Icons.delete_forever),
                                  ),
                                  FloatingActionButton(
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                AddFoodPage()),
                                      );
                                    },
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
    );
  }
}
