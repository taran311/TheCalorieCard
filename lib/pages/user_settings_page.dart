import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/pages/home_page.dart';

class UserSettingsPage extends StatefulWidget {
  UserSettingsPage({
    super.key,
  });

  @override
  State<UserSettingsPage> createState() => _UserSettingsPageState();
}

class _UserSettingsPageState extends State<UserSettingsPage> {
  final user = FirebaseAuth.instance.currentUser!;

  @override
  void initState() {
    super.initState();

    populateData();
  }

  double _exerciseLevel = 0;
  String _exerciseText = 'No Activity';
  int? _selectedAge;

  int? calorieDeficit = 0;
  int? calorieMaintenance = 0;
  int? calorieSurplus = 0;
  int? cardActiveCalories = 0;
  String? calorieMode;

  final List<int> _ageOptions = List.generate(100, (index) => index + 1);
  List<bool> genderSelections = [true, false];
  List<bool> calorieSelections = [true, false, false];

  int? _selectedHeight;
  final List<int> _heightOptions = List.generate(151, (index) => index + 100);

  int? _selectedWeight;
  final List<int> _weightOptions = List.generate(171, (index) => index + 30);

  final date = DateTime.now().add(const Duration(days: 31));

  Future<void> saveData() async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // Get the document ID
        final docId = querySnapshot.docs.first.id;

        // Create a reference to the document
        final docRef =
            FirebaseFirestore.instance.collection('user_data').doc(docId);

        // Update the document
        await docRef.update({
          'age': _selectedAge,
          'height': _selectedHeight,
          'weight': _selectedWeight,
          'exercise_level': _exerciseLevel,
          'gender': genderSelections.first ? 'male' : 'female',
          'calorie_mode': calorieMode,
          'calories': cardActiveCalories,
          'water': 0,
          'steps': 0
        });

        print('User data updated successfully!');
      } else {
        print('No document found with the provided user_id.');
      }
    } catch (e) {
      print('Error updating user data: $e');
    }
  }

  Future<void> deleteFood() async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_food')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print(
          'All user food items for userId ${FirebaseAuth.instance.currentUser!.uid} have been deleted.');
    } catch (e) {
      print('Error deleting user food items: $e');
    }
  }

  Future<void> populateData() async {
    setState(() {
      isLoading = true;
    });

    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        Map<String, dynamic> userData =
            querySnapshot.docs.first.data() as Map<String, dynamic>;

        print('Retrieved user data: $userData'); // Debugging line

        setState(() {
          _selectedAge = userData['age'] as int?;
          _selectedHeight = userData['height'] as int?;
          _selectedWeight = userData['weight'] as int?;
          _exerciseLevel = (userData['exercise_level'] as num?)?.toDouble() ??
              0.0; // Handle null and convert to double
          if (_exerciseLevel == 0) {
            _exerciseText = 'No Activity';
          } else if (_exerciseLevel == 1) {
            _exerciseText = 'Little Activity (1-3 hrs)';
          } else if (_exerciseLevel == 2) {
            _exerciseText = 'Some Activity (4-6 hrs)';
          } else if (_exerciseLevel == 3) {
            _exerciseText = 'A lot of activity (7-9 hrs)';
          } else if (_exerciseLevel == 4) {
            _exerciseText = 'A ton of activity (10+ hrs)';
          }
          cardActiveCalories = userData['calories'] as int?;

          // Gender selection
          if (userData['gender'] == 'male') {
            genderSelections = [true, false];
          } else {
            genderSelections = [false, true];
          }

          if (userData['calorie_mode'] == 'deficit') {
            calorieSelections = [true, false, false];
          } else if (userData['calorie_mode'] == 'maintain') {
            calorieSelections = [false, true, false];
          } else if (userData['calorie_mode'] == 'gain') {
            calorieSelections = [false, false, true];
          }

          updateCalories();
          updateCardActiveCalories();
        });
      } else {
        print('No user found with the provided user_id.');
      }
    } catch (e) {
      print('Error getting user data: $e');
    } finally {
      if (context.mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void updateCardActiveCalories() {
    cardActiveCalories =
        calorieSelections[0] == true ? calorieDeficit : cardActiveCalories;
    cardActiveCalories =
        calorieSelections[1] == true ? calorieMaintenance : cardActiveCalories;
    cardActiveCalories =
        calorieSelections[2] == true ? calorieSurplus : cardActiveCalories;
  }

  Future<void> updateCalories() async {
    var genderAdjustment = genderSelections.first ? 5 : -161;
    double activityMultiplier = 0;

    switch (_exerciseLevel.round()) {
      case 0:
        activityMultiplier = 1.2;
      case 1:
        activityMultiplier = 1.375;
      case 2:
        activityMultiplier = 1.55;
      case 3:
        activityMultiplier = 1.725;
      case 4:
        activityMultiplier = 1.9;
    }

    try {
      var baseCalories =
          ((((10 * _selectedWeight!) + (6.25 * _selectedHeight!)) -
                  (5 * _selectedAge!) +
                  genderAdjustment) *
              activityMultiplier);

      calorieDeficit = (baseCalories * 0.85).round();
      calorieMaintenance = baseCalories.round();
      calorieSurplus = (baseCalories * 1.15).round();

      if (calorieDeficit! < 0) calorieDeficit = 0;
      if (calorieMaintenance! < 0) calorieMaintenance = 0;
      if (calorieSurplus! < 0) calorieSurplus = 0;
    } catch (e) {
      calorieDeficit = 0;
      calorieMaintenance = 0;
      calorieSurplus = 0;
    }

    updateCardActiveCalories();
  }

  Future<void> wait(BuildContext context, VoidCallback onSuccess) async {
    await Future.delayed(const Duration(seconds: 1));
    onSuccess.call();
  }

  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Card(
          child: isLoading
              ? Center(
                  child: CircularProgressIndicator()) // Show loading spinner
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(width: 8),
                        Text('Your User Settings',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            title: const Text('Age'),
                            subtitle: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                hint: Text(_selectedAge == null
                                    ? 'Select Years'
                                    : 'Age: $_selectedAge'),
                                value: _selectedAge,
                                items: _ageOptions.map((int age) {
                                  return DropdownMenuItem<int>(
                                    value: age,
                                    child: Text('$age Yrs'),
                                  );
                                }).toList(),
                                onChanged: (int? newValue) {
                                  setState(() {
                                    _selectedAge = newValue;
                                    updateCalories();
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            title: const Text('Gender'),
                            subtitle: ToggleButtons(
                              isSelected: genderSelections,
                              onPressed: (int index) {
                                setState(() {
                                  for (int i = 0;
                                      i < genderSelections.length;
                                      i++) {
                                    genderSelections[i] = i == index;
                                  }
                                  updateCalories();
                                });
                              },
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0),
                                  child: Icon(Icons.man),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0),
                                  child: Icon(Icons.woman),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            title: const Text('Height'),
                            subtitle: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                hint: Text(_selectedHeight == null
                                    ? 'Select CM'
                                    : 'Height: $_selectedHeight'),
                                value: _selectedHeight,
                                items: _heightOptions.map((int height) {
                                  return DropdownMenuItem<int>(
                                    value: height,
                                    child: Text('$height CM'),
                                  );
                                }).toList(),
                                onChanged: (int? newValue) {
                                  setState(() {
                                    _selectedHeight = newValue;
                                    updateCalories();
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            title: const Text('Weight'),
                            subtitle: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                hint: Text(_selectedWeight == null
                                    ? 'Select KG'
                                    : 'Weight: $_selectedWeight'),
                                value: _selectedWeight,
                                items: _weightOptions.map((int weight) {
                                  return DropdownMenuItem<int>(
                                    value: weight,
                                    child: Text('$weight KG'),
                                  );
                                }).toList(),
                                onChanged: (int? newValue) {
                                  setState(() {
                                    _selectedWeight = newValue;
                                    updateCalories();
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    ListTile(
                      title: const Text('Exercise Level'),
                      subtitle: Column(
                        children: [
                          Slider(
                            value: _exerciseLevel,
                            min: 0,
                            max: 4,
                            divisions: 4,
                            onChanged: (double value) {
                              setState(
                                () {
                                  _exerciseLevel = value;

                                  // Update the text based on slider value
                                  if (_exerciseLevel == 0) {
                                    _exerciseText = 'No Activity';
                                  } else if (_exerciseLevel == 1) {
                                    _exerciseText = 'Little Activity (1-3 hrs)';
                                  } else if (_exerciseLevel == 2) {
                                    _exerciseText = 'Some Activity (4-6 hrs)';
                                  } else if (_exerciseLevel == 3) {
                                    _exerciseText =
                                        'A lot of activity (7-9 hrs)';
                                  } else if (_exerciseLevel == 4) {
                                    _exerciseText =
                                        'A ton of activity (10+ hrs)';
                                  }
                                  updateCalories();
                                },
                              );
                            },
                          ),
                          Text(_exerciseText, style: TextStyle(fontSize: 16))
                        ],
                      ),
                    ),
                    ListTile(
                      subtitle: IntrinsicWidth(
                        // Makes sure the children have equal width
                        child: ToggleButtons(
                          isSelected: calorieSelections,
                          onPressed: (int index) {
                            setState(() {
                              for (int i = 0;
                                  i < calorieSelections.length;
                                  i++) {
                                calorieSelections[i] = i == index;
                              }
                            });
                            if (calorieSelections.first) {
                              calorieMode = 'lose';
                            } else if (calorieSelections[1]) {
                              calorieMode = 'maintain';
                            } else if (calorieSelections[2]) {
                              calorieMode = 'gain';
                            }
                            updateCardActiveCalories();
                          },
                          constraints: BoxConstraints(
                              minWidth:
                                  100), // Set a minimum width for each button
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                'Lose \n $calorieDeficit',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                'Maintain \n $calorieMaintenance',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                'Gain \n $calorieSurplus',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Flexible(
                      child: CreditCard(),
                    ),
                    SizedBox(height: 15),
                    Row(
                      children: [
                        const SizedBox(width: 150),
                        ElevatedButton(
                          onPressed: () {
                            saveData();
                            deleteFood();
                            wait(context, () async {
                              await Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => HomePage(),
                                  ),
                                  (route) => false);
                            });
                          },
                          style: ButtonStyle(
                            backgroundColor:
                                WidgetStateProperty.all(Colors.blueAccent),
                          ),
                          child: Text(
                            "Update",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
        ),
      ),
    );
  }
}
