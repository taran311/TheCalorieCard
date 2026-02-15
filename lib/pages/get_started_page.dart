import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/components/measurement_input_field.dart';
import 'package:namer_app/components/mini_game.dart';
import 'package:namer_app/pages/main_shell.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  late FocusNode _ageFocusNode;

  int? calorieDeficit = 0;
  int? calorieMaintenance = 0;
  int? calorieSurplus = 0;
  int? cardActiveCalories = 0;
  String? calorieMode = 'lose'; // Default to match calorieSelections

  List<bool> genderSelections = [true, false];
  List<bool> calorieSelections = [true, false, false];

  int? _selectedHeight;
  final TextEditingController _heightController = TextEditingController();
  late FocusNode _heightFocusNode;

  int? _selectedWeight;
  final TextEditingController _weightController = TextEditingController();
  late FocusNode _weightFocusNode;

  // Macro input fields
  int? _proteinGoal;
  final TextEditingController _proteinController = TextEditingController();
  late FocusNode _proteinFocusNode;

  int? _carbsGoal;
  final TextEditingController _carbsController = TextEditingController();
  late FocusNode _carbsFocusNode;

  int? _fatsGoal;
  final TextEditingController _fatsController = TextEditingController();
  late FocusNode _fatsFocusNode;

  // AI estimation state
  bool _isEstimatingWithAI = false;
  bool _showMiniGame = false;
  bool _canEstimateWithAI = false;
  bool _macrosFromAI = false;
  Map<String, dynamic>? _lastAIData;
  bool _showAIResults = false; // Toggle between inputs and results in AI tab

  // Tab state for AI vs Manual input
  int _selectedTabIndex = 0; // 0 = AI Calculated, 1 = Manual Input
  final TextEditingController _manualCalorieController =
      TextEditingController();
  int? _manualCalorieGoal;

  @override
  void initState() {
    super.initState();
    _ageFocusNode = FocusNode();
    _heightFocusNode = FocusNode();
    _weightFocusNode = FocusNode();
    _proteinFocusNode = FocusNode();
    _carbsFocusNode = FocusNode();
    _fatsFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _ageFocusNode.dispose();
    _heightFocusNode.dispose();
    _weightFocusNode.dispose();
    _proteinFocusNode.dispose();
    _carbsFocusNode.dispose();
    _fatsFocusNode.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatsController.dispose();
    _manualCalorieController.dispose();
    super.dispose();
  }

  final date = DateTime.now().add(const Duration(days: 31));

  void saveData() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    // Use manual calorie goal if manual input is selected
    final finalCalories = _selectedTabIndex == 1 && _manualCalorieGoal != null
        ? _manualCalorieGoal
        : cardActiveCalories;

    await FirebaseFirestore.instance.collection('user_data').add({
      'user_id': userId,
      'age': _selectedAge,
      'gender': genderSelections.first ? 'male' : 'female',
      'height': _selectedHeight,
      'weight': _selectedWeight,
      'exercise_level': _exerciseLevel,
      'calories': finalCalories,
      'calorie_mode': calorieMode,
      'protein_goal': _proteinGoal ?? 0,
      'carbs_goal': _carbsGoal ?? 0,
      'fats_goal': _fatsGoal ?? 0,
      'protein_balance': _proteinGoal ?? 0,
      'carbs_balance': _carbsGoal ?? 0,
      'fats_balance': _fatsGoal ?? 0,
    });

    // Create user document with friends list
    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'email': FirebaseAuth.instance.currentUser!.email,
      'friends': [],
    }, SetOptions(merge: true));
  }

  void updateCardActiveCalories() {
    cardActiveCalories =
        calorieSelections[0] == true ? calorieDeficit : cardActiveCalories;
    cardActiveCalories =
        calorieSelections[1] == true ? calorieMaintenance : cardActiveCalories;
    cardActiveCalories =
        calorieSelections[2] == true ? calorieSurplus : cardActiveCalories;

    _prefillMacrosFromCalories();
  }

  void _prefillMacrosFromCalories() {
    if (cardActiveCalories == null || (cardActiveCalories ?? 0) <= 0) {
      return;
    }

    final int calories = cardActiveCalories ?? 0;

    // Simple macro split: 30% protein, 40% carbs, 30% fats
    final int protein = (calories * 0.30 / 4).round();
    final int carbs = (calories * 0.40 / 4).round();
    final int fats = (calories * 0.30 / 9).round();

    setState(() {
      _proteinGoal = protein;
      _proteinController.text = protein.toString();
      _carbsGoal = carbs;
      _carbsController.text = carbs.toString();
      _fatsGoal = fats;
      _fatsController.text = fats.toString();
    });
  }

  void signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  void _markFieldsChanged() {
    if (!_isEstimatingWithAI && _lastAIData != null) {
      setState(() {
        _canEstimateWithAI = true;
      });
    }
  }

  String _getExerciseLevelText() {
    if (_exerciseLevel == 0) return 'No activity';
    if (_exerciseLevel == 1) return '1-3 hours per week';
    if (_exerciseLevel == 2) return '4-6 hours per week';
    if (_exerciseLevel == 3) return '7-9 hours per week';
    if (_exerciseLevel == 4) return '10+ hours per week';
    return 'No activity';
  }

  Future<void> _estimateWithAI() async {
    if (_selectedAge == null ||
        _selectedHeight == null ||
        _selectedWeight == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill in age, height, and weight first')),
      );
      return;
    }

    setState(() {
      _isEstimatingWithAI = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://fatsecret-proxy.onrender.com/macro-targets'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'age': _selectedAge,
          'gender': genderSelections.first ? 'male' : 'female',
          'height_cm': _selectedHeight,
          'weight_kg': _selectedWeight,
          'exercise_level': _getExerciseLevelText(),
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final targets =
            data['ai']?['final']?['targets'] ?? data['baseline']?['targets'];

        if (targets != null) {
          setState(() {
            calorieDeficit = targets['lose']?['calories'];
            calorieMaintenance = targets['maintain']?['calories'];
            calorieSurplus = targets['gain']?['calories'];

            // Set macros based on selected goal
            final selectedTarget = calorieSelections[0]
                ? targets['lose']
                : calorieSelections[1]
                    ? targets['maintain']
                    : targets['gain'];

            _proteinGoal = selectedTarget?['protein_g'];
            _carbsGoal = selectedTarget?['carbs_g'];
            _fatsGoal = selectedTarget?['fat_g'];

            _proteinController.text = _proteinGoal?.toString() ?? '0';
            _carbsController.text = _carbsGoal?.toString() ?? '0';
            _fatsController.text = _fatsGoal?.toString() ?? '0';

            updateCardActiveCalories();

            _macrosFromAI = true;
            _showAIResults = true; // Show results view after estimation
            _canEstimateWithAI = false;
            _lastAIData = {
              'age': _selectedAge,
              'gender': genderSelections.first,
              'height': _selectedHeight,
              'weight': _selectedWeight,
              'exercise': _exerciseLevel,
            };
          });
        }
      } else {
        throw Exception('Failed to estimate macros');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error estimating with AI: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEstimatingWithAI = false;
          _showMiniGame = false;
        });
      }
    }
  }

  void updateCalories() {
    _markFieldsChanged();
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

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF6366F1),
                const Color(0xFF8B5CF6),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade900,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF6366F1),
                  const Color(0xFF8B5CF6),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    child: Column(
                      children: [
                        // Icon Badge
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.fitness_center,
                            size: 48,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Welcome to TheCalorieCard!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Let\'s set up your profile to get started',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withOpacity(0.95),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Main content card
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _buildSectionHeader(
                                  icon: Icons.person_outline,
                                  title: 'Basic Info',
                                  subtitle: 'Tell us about yourself',
                                ),
                                const SizedBox(height: 16),
                                const SizedBox(height: 16),
                                // Age & Gender
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
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
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          title: const Text(
                                            'Gender',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
                                          subtitle: ToggleButtons(
                                            isSelected: genderSelections,
                                            selectedColor: Color(0xFF6366F1),
                                            fillColor: Color(0xFF6366F1)
                                                .withOpacity(0.2),
                                            borderColor: Color(0xFF6366F1),
                                            selectedBorderColor:
                                                Color(0xFF6366F1),
                                            onPressed: (int index) {
                                              setState(() {
                                                for (int i = 0;
                                                    i < genderSelections.length;
                                                    i++) {
                                                  genderSelections[i] =
                                                      i == index;
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
                                const SizedBox(height: 16),
                                // Height & Weight
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
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
                                ),
                                const SizedBox(height: 16),
                                // Exercise Level
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Exercise Level',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
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
                                            },
                                          );
                                        },
                                      ),
                                      Center(
                                        child: Text(
                                          _exerciseText,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFF6366F1),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                // AI Estimate Button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: (_canEstimateWithAI ||
                                                _lastAIData == null) &&
                                            !_isEstimatingWithAI
                                        ? _estimateWithAI
                                        : null,
                                    icon: const Icon(Icons.auto_awesome,
                                        size: 20),
                                    label: const Text(
                                      'Estimate Via AI',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6366F1),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _buildSectionHeader(
                                  icon: Icons.track_changes,
                                  title: 'Your Goal',
                                  subtitle: 'Choose calculation method',
                                ),
                                const SizedBox(height: 16),
                                // Tabs for AI vs Manual
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedTabIndex = 0;
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            decoration: BoxDecoration(
                                              color: _selectedTabIndex == 0
                                                  ? const Color(0xFF6366F1)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'AI Calculated',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: _selectedTabIndex == 0
                                                    ? Colors.white
                                                    : Colors.grey.shade700,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedTabIndex = 1;
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            decoration: BoxDecoration(
                                              color: _selectedTabIndex == 1
                                                  ? const Color(0xFF6366F1)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Manual Input',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: _selectedTabIndex == 1
                                                    ? Colors.white
                                                    : Colors.grey.shade700,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Tab Content
                                if (_selectedTabIndex == 0)
                                  // AI Calculated Tab
                                  _showAIResults
                                      ? // Show Results View
                                      Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            // Back Button
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  bottom: 16),
                                              child: OutlinedButton.icon(
                                                onPressed: () {
                                                  setState(() {
                                                    _showAIResults = false;
                                                  });
                                                },
                                                icon: const Icon(
                                                    Icons.arrow_back,
                                                    size: 18),
                                                label: const Text(
                                                  'Back to Inputs',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      const Color(0xFF6366F1),
                                                  side: const BorderSide(
                                                      color:
                                                          Color(0xFF6366F1)),
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 12),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // Results Container
                                            Container(
                                              padding:
                                                  const EdgeInsets.all(20),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.05),
                                                    blurRadius: 15,
                                                    offset:
                                                        const Offset(0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: Column(
                                                children: [
                                                  // Goal Selection
                                                  const Text(
                                                    'Select Your Goal',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Color(0xFF1F2937),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  ToggleButtons(
                                                    isSelected:
                                                        calorieSelections,
                                                    selectedColor:
                                                        Colors.white,
                                                    fillColor:
                                                        Color(0xFF6366F1),
                                                    borderColor:
                                                        Color(0xFF6366F1),
                                                    selectedBorderColor:
                                                        Color(0xFF6366F1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                    onPressed: (int index) {
                                                      setState(() {
                                                        for (int i = 0;
                                                            i <
                                                                calorieSelections
                                                                    .length;
                                                            i++) {
                                                          calorieSelections[
                                                              i] = i == index;
                                                        }
                                                      });
                                                      if (calorieSelections
                                                          .first) {
                                                        calorieMode = 'lose';
                                                      } else if (calorieSelections[
                                                          1]) {
                                                        calorieMode =
                                                            'maintain';
                                                      } else if (calorieSelections[
                                                          2]) {
                                                        calorieMode = 'gain';
                                                      }

                                                      updateCardActiveCalories();
                                                    },
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 90,
                                                      minHeight: 52,
                                                    ),
                                                    children: [
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8.0,
                                                        ),
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            const Icon(
                                                                Icons
                                                                    .trending_down,
                                                                size: 18),
                                                            const SizedBox(
                                                                height: 4),
                                                            const Text(
                                                              'Lose',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontSize: 13,
                                                              ),
                                                            ),
                                                            Text(
                                                              '${calorieDeficit ?? 0}',
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8.0,
                                                        ),
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            const Icon(
                                                                Icons
                                                                    .horizontal_rule,
                                                                size: 18),
                                                            const SizedBox(
                                                                height: 4),
                                                            const Text(
                                                              'Maintain',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontSize: 13,
                                                              ),
                                                            ),
                                                            Text(
                                                              '${calorieMaintenance ?? 0}',
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8.0,
                                                        ),
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            const Icon(
                                                                Icons
                                                                    .trending_up,
                                                                size: 18),
                                                            const SizedBox(
                                                                height: 4),
                                                            const Text(
                                                              'Gain',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontSize: 13,
                                                              ),
                                                            ),
                                                            Text(
                                                              '${calorieSurplus ?? 0}',
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 24),
                                                  // Macros Section
                                                  _buildSectionHeader(
                                                    icon: Icons.restaurant,
                                                    title: 'Macros',
                                                    subtitle:
                                                        'Your daily targets',
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child:
                                                            MeasurementInputField(
                                                          label: 'Protein',
                                                          controller:
                                                              _proteinController,
                                                          focusNode:
                                                              _proteinFocusNode,
                                                          hintText: 'E.g. 150',
                                                          suffix: 'g',
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _proteinGoal =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child:
                                                            MeasurementInputField(
                                                          label: 'Carbs',
                                                          controller:
                                                              _carbsController,
                                                          focusNode:
                                                              _carbsFocusNode,
                                                          hintText: 'E.g. 200',
                                                          suffix: 'g',
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _carbsGoal = value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child:
                                                            MeasurementInputField(
                                                          label: 'Fats',
                                                          controller:
                                                              _fatsController,
                                                          focusNode:
                                                              _fatsFocusNode,
                                                          hintText: 'E.g. 65',
                                                          suffix: 'g',
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _fatsGoal = value;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      const Expanded(
                                                          child: SizedBox()),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 24),
                                                  // Credit Card Preview
                                                  CreditCard(
                                                    key: ValueKey(
                                                        '${cardActiveCalories}_${_proteinGoal}_${_carbsGoal}_${_fatsGoal}'),
                                                    initialCalories:
                                                        cardActiveCalories ?? 0,
                                                    caloriesOverride:
                                                        cardActiveCalories ?? 0,
                                                    proteinOverride:
                                                        (_proteinGoal ?? 0)
                                                            .toDouble(),
                                                    carbsOverride:
                                                        (_carbsGoal ?? 0)
                                                            .toDouble(),
                                                    fatsOverride:
                                                        (_fatsGoal ?? 0)
                                                            .toDouble(),
                                                    skipFetch: true,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      : // Show Inputs View
                                      Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.04),
                                                blurRadius: 10,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.auto_awesome,
                                                size: 48,
                                                color: Color(0xFF6366F1)
                                                    .withOpacity(0.3),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                'No AI Estimation Yet',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey.shade800,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Enter your details above and tap\n"Estimate Via AI" to get started',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                else
                                  // Manual Input Tab
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.04),
                                          blurRadius: 10,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Enter Your Calorie Goal',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _manualCalorieController,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: 'Calories',
                                            hintText: 'E.g. 2000',
                                            floatingLabelBehavior:
                                                FloatingLabelBehavior.always,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 12,
                                            ),
                                          ),
                                          onChanged: (value) {
                                            setState(() {
                                              _manualCalorieGoal =
                                                  int.tryParse(value);
                                              cardActiveCalories =
                                                  _manualCalorieGoal;
                                              _prefillMacrosFromCalories();
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 24),
                                _buildSectionHeader(
                                  icon: Icons.restaurant_menu,
                                  title: 'Macro Goals',
                                  subtitle: 'Set your daily nutrition targets',
                                ),
                                const SizedBox(height: 16),
                                // Macros
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _proteinController,
                                          focusNode: _proteinFocusNode,
                                          keyboardType: TextInputType.number,
                                          enabled: !_macrosFromAI,
                                          decoration: InputDecoration(
                                            labelText: 'Protein (g)',
                                            hintText: 'Protein',
                                            floatingLabelBehavior:
                                                FloatingLabelBehavior.always,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 12,
                                            ),
                                          ),
                                          onChanged: (value) {
                                            setState(() {
                                              _proteinGoal =
                                                  int.tryParse(value);
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          controller: _carbsController,
                                          focusNode: _carbsFocusNode,
                                          keyboardType: TextInputType.number,
                                          enabled: !_macrosFromAI,
                                          decoration: InputDecoration(
                                            labelText: 'Carbs (g)',
                                            hintText: 'Carbs',
                                            floatingLabelBehavior:
                                                FloatingLabelBehavior.always,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
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
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          controller: _fatsController,
                                          focusNode: _fatsFocusNode,
                                          keyboardType: TextInputType.number,
                                          enabled: !_macrosFromAI,
                                          decoration: InputDecoration(
                                            labelText: 'Fats (g)',
                                            hintText: 'Fats',
                                            floatingLabelBehavior:
                                                FloatingLabelBehavior.always,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
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
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                // Credit Card Preview
                                CreditCard(
                                  key: ValueKey(
                                      '${cardActiveCalories}_${_proteinGoal}_${_carbsGoal}_${_fatsGoal}'),
                                  initialCalories: cardActiveCalories ?? 0,
                                  caloriesOverride: cardActiveCalories ?? 0,
                                  proteinOverride:
                                      (_proteinGoal ?? 0).toDouble(),
                                  carbsOverride: (_carbsGoal ?? 0).toDouble(),
                                  fatsOverride: (_fatsGoal ?? 0).toDouble(),
                                  skipFetch: true,
                                ),
                                const SizedBox(height: 24),
                                // Save Button
                                Container(
                                  width: double.infinity,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0xFF10B981).withOpacity(0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      saveData();
                                      await Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const MainShell(initialIndex: 1),
                                        ),
                                        (route) => false,
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: const [
                                        Text(
                                          "Let's get started!",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Icon(Icons.arrow_forward_rounded,
                                            size: 22),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isEstimatingWithAI && _showMiniGame) const PingPongGame(),
          if (_isEstimatingWithAI && !_showMiniGame)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'AI is calculating your\nmacros and calories...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _showMiniGame = true;
                            });
                          },
                          icon: const Icon(Icons.sports_esports, size: 18),
                          label: const Text('Play Solo Ping Pong'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
