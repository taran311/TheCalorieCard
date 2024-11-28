import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/components/swipe_animation_widget.dart';
import 'package:namer_app/pages/add_food_page.dart';
import 'package:namer_app/pages/login_or_register_page.dart';
import 'package:namer_app/pages/user_settings_page.dart';

class HomePage extends StatefulWidget {
  final bool addFoodAnimation;

  const HomePage({Key? key, this.addFoodAnimation = false}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Container> listOfFood = [];
  bool _showAnimations = false;

  @override
  void initState() {
    super.initState();
    _showAnimations =
        widget.addFoodAnimation; // Enable animations based on the parameter
    if (_showAnimations) {
      _startAnimations();
    }
    populateFoodItems();
  }

  Future<void> _startAnimations() async {
    // Ensure animations are shown for at least 3 seconds
    await Future.delayed(Duration(seconds: 3));
    setState(() {
      _showAnimations = false; // Hide animations after they complete
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
                      Text(doc["food_description"]),
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
        if (mounted) {
          setState(() {
            listOfFood = [];
          });
        }
      }
    } catch (e) {
      print('Error populating food items: $e');
      if (mounted) {
        setState(() {
          listOfFood = [];
        });
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () async {
              await navigateToProfilePage();
            },
            icon: Icon(Icons.person),
          ),
          IconButton(
            onPressed: () async {
              await signOut(context);
            },
            icon: Icon(Icons.logout),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: CreditCard(
                  showWater: true,
                  showSteps: true,
                  showPerformanceGauge: true,
                ),
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
          if (_showAnimations)
            Stack(
              children: [
                SwipeAnimationWidget(
                  onAnimationComplete: () {
                    print("Card animation complete.");
                  },
                ),
                CardReaderAnimationWidget(
                  onAnimationComplete: () {
                    print("Card reader animation complete.");
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}