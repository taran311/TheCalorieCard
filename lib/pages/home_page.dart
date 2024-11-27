import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/pages/add_food_page.dart';
import 'package:namer_app/pages/login_or_register_page.dart';
import 'package:namer_app/pages/user_settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final date = DateTime.now().add(const Duration(days: 31));
  List<Container> listOfFood = [];

  @override
  void initState() {
    super.initState();
    listOfFood = [];
    populateFoodItems();
  }

  Future<void> wait(BuildContext context, VoidCallback onSuccess) async {
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) onSuccess.call();
  }

  Future<void> signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginOrRegisterPage()),
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

  Future<void> deleteFood() async {
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
  }

  Future<void> populateFoodItems() async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_food')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        List<Container> tempList = [];
        for (var doc in querySnapshot.docs) {
          tempList.add(
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                      width: 1.0, color: Colors.grey.withOpacity(0.5)),
                  bottom: BorderSide(
                      width: 1.0, color: Colors.grey.withOpacity(0.5)),
                ),
              ),
              child: GestureDetector(
                onLongPress: () {},
                child: ListTile(
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatFoodString(doc["food_description"])),
                      Text('${doc["food_calories"]}'),
                    ],
                  ),
                  tileColor: Colors.blue[900],
                  textColor: Colors.white,
                ),
              ),
            ),
          );
        }

        if (mounted) {
          setState(() {
            listOfFood = tempList;
          });
        }
      } else {
        print('No food items found for this user.');
        if (mounted) {
          setState(() {
            listOfFood = [];
          });
        }
      }
    } catch (e) {
      print('Error getting food data: $e');
      if (mounted) {
        setState(() {
          listOfFood = [];
        });
      }
    }
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
        actions: [
          IconButton(
              onPressed: () async {
                await navigateToProfilePage();
              },
              icon: Icon(Icons.person)),
          IconButton(
              onPressed: () async {
                await signOut(context);
              },
              icon: Icon(Icons.logout)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: CreditCard(
                showWater: true, showSteps: true, showPerformanceGauge: true),
          ),
          Expanded(
            child: Card(
              color: Colors.blue[900],
              margin: EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        children: listOfFood,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(width: 8),
                        Spacer(),
                        FloatingActionButton(
                          onPressed: () async {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (BuildContext context) {
                                return Center(
                                  child: CircularProgressIndicator(),
                                );
                              },
                            );

                            try {
                              await deleteFood();
                              await populateFoodItems();
                            } finally {
                              if (mounted) Navigator.pop(context);
                            }
                          },
                          heroTag: 'delete',
                          child: Icon(Icons.delete_forever),
                        ),
                        SizedBox(
                          width: 10,
                        ),
                        FloatingActionButton(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => AddFoodPage()),
                            );
                          },
                          heroTag: 'add',
                          child: Icon(Icons.add),
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
}
