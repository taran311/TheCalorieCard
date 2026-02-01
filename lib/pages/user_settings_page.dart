import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/components/measurement_input_field.dart';
import 'package:namer_app/pages/main_shell.dart';

class UserSettingsPage extends StatefulWidget {
  UserSettingsPage({
    super.key,
  });

  @override
  State<UserSettingsPage> createState() => _UserSettingsPageState();
}

class _UserSettingsPageState extends State<UserSettingsPage>
    with TickerProviderStateMixin {
  final user = FirebaseAuth.instance.currentUser!;
  AnimationController? _jiggleAnimationController;
  Animation<double>? _jiggleAnimation;

  @override
  void initState() {
    super.initState();

    _jiggleAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _jiggleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: -0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.05, end: 0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: -0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.05, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _jiggleAnimationController!,
      curve: Curves.easeInOut,
    ));

    _ageFocusNode = FocusNode();
    _heightFocusNode = FocusNode();
    _weightFocusNode = FocusNode();
    _proteinFocusNode = FocusNode();
    _carbsFocusNode = FocusNode();
    _fatsFocusNode = FocusNode();

    _proteinController = TextEditingController();
    _carbsController = TextEditingController();
    _fatsController = TextEditingController();

    populateData();
  }

  @override
  void dispose() {
    _jiggleAnimationController?.dispose();
    _ageFocusNode.dispose();
    _heightFocusNode.dispose();
    _weightFocusNode.dispose();
    _proteinFocusNode.dispose();
    _carbsFocusNode.dispose();
    _fatsFocusNode.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatsController.dispose();
    super.dispose();
  }

  double _exerciseLevel = 0;
  String _exerciseText = 'No Activity';
  int? _selectedAge;
  final TextEditingController _ageController = TextEditingController();
  late FocusNode _ageFocusNode;

  int? calorieDeficit = 0;
  int? calorieMaintenance = 0;
  int? calorieSurplus = 0;
  int? cardActiveCalories = 0;
  String? calorieMode;

  int? _selectedHeight;
  final TextEditingController _heightController = TextEditingController();
  late FocusNode _heightFocusNode;

  int? _selectedWeight;
  final TextEditingController _weightController = TextEditingController();
  late FocusNode _weightFocusNode;

  int? _proteinGoal;
  int? _carbsGoal;
  int? _fatsGoal;
  late TextEditingController _proteinController;
  late TextEditingController _carbsController;
  late TextEditingController _fatsController;
  late FocusNode _proteinFocusNode;
  late FocusNode _carbsFocusNode;
  late FocusNode _fatsFocusNode;

  List<bool> genderSelections = [true, false];
  List<bool> calorieSelections = [true, false, false];

  final date = DateTime.now().add(const Duration(days: 31));

  bool _isSaving = false;

  Future<Map<String, double>> _getCurrentIntakeTotals() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('user_food')
        .where('user_id', isEqualTo: userId)
        .get();

    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fats = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      calories += (data['food_calories'] as num?)?.toDouble() ?? 0;
      protein += (data['food_protein'] as num?)?.toDouble() ?? 0;
      carbs += (data['food_carbs'] as num?)?.toDouble() ?? 0;
      fats += (data['food_fat'] as num?)?.toDouble() ?? 0;
    }

    return {
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fats': fats,
    };
  }

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

        final totals = await _getCurrentIntakeTotals();

        final double selectedCalories = (cardActiveCalories ??
                calorieMaintenance ??
                calorieDeficit ??
                calorieSurplus ??
                0)
            .toDouble();

        final int proteinGoal = _proteinGoal ?? 0;
        final int carbsGoal = _carbsGoal ?? 0;
        final int fatsGoal = _fatsGoal ?? 0;

        // Update the document
        await docRef.update({
          'age': _selectedAge,
          'height': _selectedHeight,
          'weight': _selectedWeight,
          'exercise_level': _exerciseLevel,
          'gender': genderSelections.first ? 'male' : 'female',
          'calorie_mode': calorieMode,
          'calories': selectedCalories - (totals['calories'] ?? 0),
          'protein_goal': proteinGoal,
          'carbs_goal': carbsGoal,
          'fats_goal': fatsGoal,
          // balances now subtract current intake so card reflects remaining
          'protein_balance': proteinGoal - (totals['protein'] ?? 0),
          'carbs_balance': carbsGoal - (totals['carbs'] ?? 0),
          'fats_balance': fatsGoal - (totals['fats'] ?? 0),
        });

        print('User data updated successfully!');
      } else {
        print('No document found with the provided user_id.');
      }
    } catch (e) {
      print('Error updating user data: $e');
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
          _ageController.text =
              _selectedAge != null ? '$_selectedAge Years Old' : '';
          _selectedHeight = userData['height'] as int?;
          _heightController.text =
              _selectedHeight != null ? '${_selectedHeight}cm' : '';
          _selectedWeight = userData['weight'] as int?;
          _weightController.text =
              _selectedWeight != null ? '${_selectedWeight}kg' : '';
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

          _proteinGoal = (userData['protein_goal'] as num?)?.toInt();
          _carbsGoal = (userData['carbs_goal'] as num?)?.toInt();
          _fatsGoal = (userData['fats_goal'] as num?)?.toInt();
          _proteinController.text = _proteinGoal?.toString() ?? '';
          _carbsController.text = _carbsGoal?.toString() ?? '';
          _fatsController.text = _fatsGoal?.toString() ?? '';

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
    int? selectedCalories = cardActiveCalories;

    if (calorieSelections[0]) {
      selectedCalories = calorieDeficit;
    } else if (calorieSelections[1]) {
      selectedCalories = calorieMaintenance;
    } else if (calorieSelections[2]) {
      selectedCalories = calorieSurplus;
    }

    setState(() {
      cardActiveCalories = selectedCalories;
      _prefillMacrosFromCalories(selectedCalories);
    });
  }

  void _prefillMacrosFromCalories(int? calories) {
    if (calories == null || calories <= 0) return;

    final int protein = (calories * 0.30 / 4).round();
    final int carbs = (calories * 0.40 / 4).round();
    final int fats = (calories * 0.30 / 9).round();

    _proteinGoal = protein;
    _proteinController.text = protein.toString();
    _carbsGoal = carbs;
    _carbsController.text = carbs.toString();
    _fatsGoal = fats;
    _fatsController.text = fats.toString();
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
    } catch (e) {
      calorieDeficit = 0;
      calorieMaintenance = 0;
      calorieSurplus = 0;
    }

    updateCardActiveCalories();
  }

  bool isLoading = false;

  Future<void> wait(BuildContext context, VoidCallback onSuccess) async {
    await Future.delayed(const Duration(seconds: 1));
    onSuccess.call();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
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
        child: SafeArea(
          top: false,
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: EdgeInsets.fromLTRB(8, topPadding + 8, 8, 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.arrow_back),
                              color: Colors.white,
                              splashRadius: 20,
                              tooltip: 'Back',
                            ),
                            const Expanded(
                              child: Center(
                                child: Text(
                                  'Edit Profile',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                MeasurementInputField(
                                  label: 'Age',
                                  controller: _ageController,
                                  focusNode: _ageFocusNode,
                                  hintText: 'E.g. 30',
                                  suffix: ' Years Old',
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedAge = value;
                                      if (_selectedAge != null &&
                                          _selectedAge! >= 18 &&
                                          _selectedAge! <= 117) {
                                        updateCalories();
                                      }
                                    });
                                  },
                                ),
                                Expanded(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    title: const Text(
                                      'Gender',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: ToggleButtons(
                                      isSelected: genderSelections,
                                      selectedColor: const Color(0xFF6366F1),
                                      fillColor: const Color(0xFF6366F1)
                                          .withOpacity(0.2),
                                      borderColor: const Color(0xFF6366F1),
                                      selectedBorderColor:
                                          const Color(0xFF6366F1),
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
                            Row(
                              children: [
                                MeasurementInputField(
                                  label: 'Height',
                                  controller: _heightController,
                                  focusNode: _heightFocusNode,
                                  hintText: 'E.g. 180cm',
                                  suffix: 'cm',
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedHeight = value;
                                      if (_selectedHeight != null &&
                                          _selectedHeight! >= 100 &&
                                          _selectedHeight! <= 250) {
                                        updateCalories();
                                      }
                                    });
                                  },
                                ),
                                MeasurementInputField(
                                  label: 'Weight',
                                  controller: _weightController,
                                  focusNode: _weightFocusNode,
                                  hintText: 'E.g. 80kg',
                                  suffix: 'kg',
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedWeight = value;
                                      if (_selectedWeight != null &&
                                          _selectedWeight! >= 30 &&
                                          _selectedWeight! <= 200) {
                                        updateCalories();
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Exercise Level',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  Slider(
                                    value: _exerciseLevel,
                                    min: 0,
                                    max: 4,
                                    divisions: 4,
                                    activeColor: const Color(0xFF6366F1),
                                    onChanged: (double value) {
                                      setState(() {
                                        _exerciseLevel = value;
                                        if (_exerciseLevel == 0) {
                                          _exerciseText = 'No Activity';
                                        } else if (_exerciseLevel == 1) {
                                          _exerciseText =
                                              'Little Activity (1-3 hrs)';
                                        } else if (_exerciseLevel == 2) {
                                          _exerciseText =
                                              'Some Activity (4-6 hrs)';
                                        } else if (_exerciseLevel == 3) {
                                          _exerciseText =
                                              'A lot of activity (7-9 hrs)';
                                        } else if (_exerciseLevel == 4) {
                                          _exerciseText =
                                              'A ton of activity (10+ hrs)';
                                        }
                                        updateCalories();
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _exerciseText,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 0),
                              child: IntrinsicWidth(
                                child: ToggleButtons(
                                  isSelected: calorieSelections,
                                  selectedColor: Colors.white,
                                  fillColor: const Color(0xFF6366F1),
                                  borderColor: const Color(0xFF6366F1),
                                  selectedBorderColor: const Color(0xFF6366F1),
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
                            const SizedBox(height: 20),
                            const Text(
                              'Macros',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _proteinController,
                                    focusNode: _proteinFocusNode,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Protein (g)',
                                      hintText: 'Protein',
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        _proteinGoal = int.tryParse(value);
                                      });
                                      updateCardActiveCalories();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _carbsController,
                                    focusNode: _carbsFocusNode,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Carbs (g)',
                                      hintText: 'Carbs',
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        _carbsGoal = int.tryParse(value);
                                      });
                                      updateCardActiveCalories();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _fatsController,
                                    focusNode: _fatsFocusNode,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Fats (g)',
                                      hintText: 'Fats',
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        _fatsGoal = int.tryParse(value);
                                      });
                                      updateCardActiveCalories();
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 0),
                              child: AnimatedBuilder(
                                animation: _jiggleAnimation ??
                                    const AlwaysStoppedAnimation(0.0),
                                builder: (context, child) {
                                  return Transform.rotate(
                                    angle: _jiggleAnimation?.value ?? 0.0,
                                    child: child,
                                  );
                                },
                                child: CreditCard(
                                  key: ValueKey(
                                      '${cardActiveCalories}_${_proteinGoal}_${_carbsGoal}_${_fatsGoal}'),
                                  initialCalories: cardActiveCalories ?? 0,
                                  caloriesOverride: cardActiveCalories ?? 0,
                                  proteinOverride:
                                      (_proteinGoal ?? 0).toDouble(),
                                  carbsOverride: (_carbsGoal ?? 0).toDouble(),
                                  fatsOverride: (_fatsGoal ?? 0).toDouble(),
                                  skipFetch: true,
                                  onToggleMacros: (showMacros) {
                                    _jiggleAnimationController?.forward(
                                        from: 0);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _isSaving
                                    ? null
                                    : () async {
                                        setState(() {
                                          _isSaving = true;
                                        });
                                        await saveData();
                                        if (!mounted) return;
                                        setState(() {
                                          _isSaving = false;
                                        });
                                        await Navigator.pushAndRemoveUntil(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const MainShell(
                                                    initialIndex: 1),
                                          ),
                                          (route) => false,
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 4,
                                ),
                                child: _isSaving
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        'Save',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
