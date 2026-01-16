import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/pages/home_page.dart';

class GetStartedPage extends StatefulWidget {
  GetStartedPage({
    super.key,
  });

  @override
  State<GetStartedPage> createState() => _GetStartedPageState();
}

class _GetStartedPageState extends State<GetStartedPage> {
  final user = FirebaseAuth.instance.currentUser!;

  double _exerciseLevel = 0;
  String _exerciseText = 'No Activity';
  int? _selectedAge;
  final TextEditingController _ageController = TextEditingController();

  int? calorieDeficit = 0;
  int? calorieMaintenance = 0;
  int? calorieSurplus = 0;
  int? cardActiveCalories = 0;
  String? calorieMode;

  List<bool> genderSelections = [true, false];
  List<bool> calorieSelections = [true, false, false];

  int? _selectedHeight;
  final TextEditingController _heightController = TextEditingController();
  late FocusNode _heightFocusNode;

  int? _selectedWeight;
  final TextEditingController _weightController = TextEditingController();
  late FocusNode _weightFocusNode;

  @override
  void initState() {
    super.initState();
    _heightFocusNode = FocusNode();
    _weightFocusNode = FocusNode();

    _heightFocusNode.addListener(() {
      if (!_heightFocusNode.hasFocus &&
          _heightController.text.isNotEmpty &&
          !_heightController.text.endsWith('cm')) {
        _heightController.text = '${_heightController.text}cm';
      }
    });

    _weightFocusNode.addListener(() {
      if (!_weightFocusNode.hasFocus &&
          _weightController.text.isNotEmpty &&
          !_weightController.text.endsWith('kg')) {
        _weightController.text = '${_weightController.text}kg';
      }
    });
  }

  @override
  void dispose() {
    _heightFocusNode.dispose();
    _weightFocusNode.dispose();
    super.dispose();
  }

  final date = DateTime.now().add(const Duration(days: 31));

  void saveData() async {
    await FirebaseFirestore.instance.collection('user_data').add({
      'user_id': FirebaseAuth.instance.currentUser!.uid,
      'age': _selectedAge,
      'gender': genderSelections.first ? 'male' : 'female',
      'height': _selectedHeight,
      'weight': _selectedWeight,
      'exercise_level': _exerciseLevel,
      'calories': cardActiveCalories,
      'calorie_mode': calorieMode,
      'water': 0,
      'steps': 0
    });
  }

  void updateCardActiveCalories() {
    cardActiveCalories =
        calorieSelections[0] == true ? calorieDeficit : cardActiveCalories;
    cardActiveCalories =
        calorieSelections[1] == true ? calorieMaintenance : cardActiveCalories;
    cardActiveCalories =
        calorieSelections[2] == true ? calorieSurplus : cardActiveCalories;
  }

  void signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  void updateCalories() {
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

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          margin: const EdgeInsets.all(16),
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Let\'s get to know you!',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            title: const Text(
                              'Age',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: TextField(
                              controller: _ageController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'E.g. 30 Years',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _selectedAge = int.tryParse(value);
                                  if (_selectedAge != null &&
                                      _selectedAge! >= 18 &&
                                      _selectedAge! <= 117) {
                                    updateCalories();
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            title: const Text(
                              'Gender',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: ToggleButtons(
                              isSelected: genderSelections,
                              selectedColor: Color(0xFF6366F1),
                              fillColor: Color(0xFF6366F1).withOpacity(0.2),
                              borderColor: Color(0xFF6366F1),
                              selectedBorderColor: Color(0xFF6366F1),
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
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.0,
                                  ),
                                  child: Icon(Icons.man),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.0,
                                  ),
                                  child: Icon(Icons.woman),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            title: const Text(
                              'Height',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: TextField(
                              controller: _heightController,
                              focusNode: _heightFocusNode,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'E.g. 180cm',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _selectedHeight = int.tryParse(
                                      value?.replaceAll('cm', '') ?? '');
                                  if (_selectedHeight != null &&
                                      _selectedHeight! >= 100 &&
                                      _selectedHeight! <= 250) {
                                    updateCalories();
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            title: const Text(
                              'Weight',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: TextField(
                              controller: _weightController,
                              focusNode: _weightFocusNode,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'E.g. 80kg',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _selectedWeight =
                                      int.tryParse(value.replaceAll('kg', ''));
                                  if (_selectedWeight != null &&
                                      _selectedWeight! >= 30 &&
                                      _selectedWeight! <= 200) {
                                    updateCalories();
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Exercise Level',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        children: [
                          Slider(
                            value: _exerciseLevel,
                            min: 0,
                            max: 4,
                            divisions: 4,
                            activeColor: Color(0xFF6366F1),
                            onChanged: (double value) {
                              setState(
                                () {
                                  _exerciseLevel = value;
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
                          Text(
                            _exerciseText,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Goal',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: IntrinsicWidth(
                        child: ToggleButtons(
                          isSelected: calorieSelections,
                          selectedColor: Colors.white,
                          fillColor: Color(0xFF6366F1),
                          borderColor: Color(0xFF6366F1),
                          selectedBorderColor: Color(0xFF6366F1),
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
                          constraints: const BoxConstraints(
                            minWidth: 90,
                            minHeight: 40,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Text(
                                'Lose\n${calorieDeficit ?? 0}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Text(
                                'Maintain\n${calorieMaintenance ?? 0}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Text(
                                'Gain\n${calorieSurplus ?? 0}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: CreditCard(
                        initialCalories: cardActiveCalories ?? 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          saveData();
                          await Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => HomePage(),
                            ),
                            (route) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF10B981),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                        child: const Text(
                          "Let's get started!",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
