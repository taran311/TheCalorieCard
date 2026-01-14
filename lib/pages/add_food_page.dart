import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/pages/fat_secret_api.dart';
import 'package:namer_app/pages/home_page.dart';

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

  @override
  void dispose() {
    // Ensure the text controller is properly disposed of
    foodController.dispose();
    super.dispose();
  }

  Future<void> saveData(String foodDescription, int foodCalories) async {
    try {
      await FirebaseFirestore.instance.collection('user_food').add({
        'user_id': FirebaseAuth.instance.currentUser!.uid,
        'food_description': foodDescription,
        'food_calories': foodCalories,
        'time_added': DateTime.now()
      });
    } catch (e) {
      print('Error adding user food: $e');
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

                  showDialog(
                    context: context,
                    builder: (context) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    },
                  );

                  await saveData(food.foodName, newCaloriesToUpdate);
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
                    SizedBox(
                      height: _isTextFieldTapped ? 0 : 200,
                    ),
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
