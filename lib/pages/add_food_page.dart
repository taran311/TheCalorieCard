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
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                      width: 1.0, color: Colors.grey.withOpacity(0.5)),
                  bottom: BorderSide(
                      width: 1.0, color: Colors.grey.withOpacity(0.5)),
                ),
              ),
              child: ListTile(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        '${_formatFoodString(food.foodName)} \n (per ${_formatAmount(food.foodDescription)})'),
                    Text(
                      _formatCalories(food.foodDescription),
                      textAlign: TextAlign.right,
                    )
                  ],
                ),
                onTap: () async {
                  if (!mounted) return;
                  final newCaloriesToUpdate =
                      int.parse(_formatCalories(food.foodDescription));

                  showDialog(
                    context: context,
                    builder: (context) {
                      return Center(child: CircularProgressIndicator());
                    },
                  );

                  await saveData(food.foodName, newCaloriesToUpdate);
                  await updateCalories(newCaloriesToUpdate);

                  if (!mounted) return;
                  Navigator.pop(context); // Close the dialog

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
                tileColor: Colors.blue,
                textColor: Colors.white,
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
        title: Text('Food Search'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              mainAxisAlignment: _isTextFieldTapped
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                SizedBox(
                    height: _isTextFieldTapped
                        ? 0
                        : 350), // Adjust space when tapped
                Card(
                  margin: EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: foodController,
                            decoration: InputDecoration(
                              hintText: 'Search for food...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(15.0),
                          child: ElevatedButton(
                            onPressed: () async {
                              await _onButtonPress();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: Icon(Icons.search),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                isEmpty
                    ? Container()
                    : Card(
                        color: Colors.blue,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: listOfItems,
                          ),
                        ),
                      ),
              ],
            ),
          ),
          if (_isLoading)
            Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
