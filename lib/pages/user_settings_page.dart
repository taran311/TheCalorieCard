import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/components/measurement_input_field.dart';
import 'package:namer_app/components/mini_game.dart';
import 'package:namer_app/pages/main_shell.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
    _manualCalorieController.dispose();
    super.dispose();
  }

  double _exerciseLevel = 0;
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

  // AI estimation state
  bool _isEstimatingWithAI = false;
  bool _showMiniGame = false;
  bool _canEstimateWithAI = false;
  bool _macrosFromAI = false;
  Map<String, dynamic>? _lastAIData;

  // Tab state
  int _selectedTabIndex = 0; // 0 = AI Calculated, 1 = Manual Input
  final TextEditingController _manualCalorieController =
      TextEditingController();
  int? _manualCalorieGoal;

  Future<Map<String, double>> _getCurrentIntakeTotals() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final snapshot = await FirebaseFirestore.instance
        .collection('user_food')
        .where('user_id', isEqualTo: userId)
        .get(const GetOptions(source: Source.server));

    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fats = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      DateTime? docDate;
      final timeAdded = data['time_added'];
      final createdAt = data['created_at'];

      if (timeAdded is Timestamp) {
        docDate = timeAdded.toDate();
      } else if (timeAdded is DateTime) {
        docDate = timeAdded;
      } else if (createdAt is Timestamp) {
        docDate = createdAt.toDate();
      } else if (createdAt is DateTime) {
        docDate = createdAt;
      }

      if (docDate == null ||
          docDate.isBefore(startOfDay) ||
          !docDate.isBefore(endOfDay)) {
        continue;
      }
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

  Future<void> _clearAllTodaysFoodItems() async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snapshot = await FirebaseFirestore.instance
          .collection('user_food')
          .where('user_id', isEqualTo: userId)
          .get(const GetOptions(source: Source.server));

      final batch = FirebaseFirestore.instance.batch();
      int count = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        DateTime? docDate;
        final timeAdded = data['time_added'];
        final createdAt = data['created_at'];

        if (timeAdded is Timestamp) {
          docDate = timeAdded.toDate();
        } else if (timeAdded is DateTime) {
          docDate = timeAdded;
        } else if (createdAt is Timestamp) {
          docDate = createdAt.toDate();
        } else if (createdAt is DateTime) {
          docDate = createdAt;
        }

        if (docDate != null &&
            !docDate.isBefore(startOfDay) &&
            docDate.isBefore(endOfDay)) {
          batch.delete(doc.reference);
          count++;
        }
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cleared $count food items from today')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing food items: $e')),
        );
      }
    }
  }

  Future<void> saveData() async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .get(const GetOptions(source: Source.server));

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

        // Use manual calorie goal if set, otherwise use AI calculated
        final double baseCalorieGoal =
            _selectedTabIndex == 1 && _manualCalorieGoal != null
                ? _manualCalorieGoal!.toDouble()
                : selectedCalories;

        // Update the document
        await docRef.update({
          'age': _selectedAge,
          'height': _selectedHeight,
          'weight': _selectedWeight,
          'exercise_level': _exerciseLevel,
          'gender': genderSelections.first ? 'male' : 'female',
          'calorie_mode': calorieMode,
          'calorie_goal': baseCalorieGoal, // Store base calorie goal
          'calories': baseCalorieGoal - (totals['calories'] ?? 0),
          'protein_goal': proteinGoal,
          'carbs_goal': carbsGoal,
          'fats_goal': fatsGoal,
          // balances now subtract current intake so card reflects remaining
          'protein_balance': proteinGoal - (totals['protein'] ?? 0),
          'carbs_balance': carbsGoal - (totals['carbs'] ?? 0),
          'fats_balance': fatsGoal - (totals['fats'] ?? 0),
        });

        // Wait a moment to ensure Firestore write propagates to server
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      // Error updating user data
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
          .get(const GetOptions(source: Source.server));

      if (querySnapshot.docs.isNotEmpty) {
        Map<String, dynamic> userData =
            querySnapshot.docs.first.data() as Map<String, dynamic>;

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

          // Gender selection
          if (userData['gender'] == 'male') {
            genderSelections = [true, false];
          } else {
            genderSelections = [false, true];
          }

          // Load calorie mode (default to 'lose' if null)
          calorieMode = userData['calorie_mode'] as String?;
          if (calorieMode == null ||
              calorieMode == 'deficit' ||
              calorieMode == 'lose') {
            calorieSelections = [true, false, false];
            calorieMode = 'lose'; // Normalize to 'lose'
          } else if (calorieMode == 'maintain') {
            calorieSelections = [false, true, false];
            calorieMode = 'maintain';
          } else if (calorieMode == 'gain') {
            calorieSelections = [false, false, true];
            calorieMode = 'gain';
          } else {
            // Fallback to lose if unrecognized
            calorieSelections = [true, false, false];
            calorieMode = 'lose';
          }

          _proteinGoal = (userData['protein_goal'] as num?)?.toInt();
          _carbsGoal = (userData['carbs_goal'] as num?)?.toInt();
          _fatsGoal = (userData['fats_goal'] as num?)?.toInt();
          _proteinController.text = _proteinGoal?.toString() ?? '';
          _carbsController.text = _carbsGoal?.toString() ?? '';
          _fatsController.text = _fatsGoal?.toString() ?? '';

          // Load calorie_goal for manual input
          final calorieGoal = (userData['calorie_goal'] as num?)?.toInt();
          if (calorieGoal != null) {
            _manualCalorieGoal = calorieGoal;
            _manualCalorieController.text = calorieGoal.toString();
          }

          updateCalories();
          updateCardActiveCalories();
        });
      }
    } catch (e) {
      // Error getting user data
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

    int maxRetries = 2;
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        attempt++;

        if (attempt > 1 && mounted) {
          // Show retry attempt to user
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Retrying... (Attempt $attempt of $maxRetries)'),
              duration: const Duration(seconds: 2),
            ),
          );
        }

        final response = await http
            .post(
          Uri.parse('https://fatsecret-proxy.onrender.com/macro-targets'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'age': _selectedAge,
            'gender': genderSelections.first ? 'male' : 'female',
            'height_cm': _selectedHeight,
            'weight_kg': _selectedWeight,
            'exercise_level': _getExerciseLevelText(),
          }),
        )
            .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception(
                'Request timed out. The server may be waking up from sleep. Please try again in a moment.');
          },
        );

        print('API Status Code: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          print('API Response: $data');
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
              _canEstimateWithAI = false;
              _lastAIData = {
                'age': _selectedAge,
                'gender': genderSelections.first,
                'height': _selectedHeight,
                'weight': _selectedWeight,
                'exercise': _exerciseLevel,
              };

              // Reset mini game and estimation state on success
              _isEstimatingWithAI = false;
              _showMiniGame = false;
            });

            // Success - exit retry loop
            return;
          } else {
            throw Exception('Targets data not found in response');
          }
        } else if (response.statusCode == 503 && attempt < maxRetries) {
          // Server is cold starting, wait and retry
          print('Server cold starting, will retry...');
          await Future.delayed(Duration(seconds: 5 * attempt));
          continue;
        } else {
          // Log detailed error information
          print('API Error - Status: ${response.statusCode}');
          print('API Error - Body: ${response.body}');

          String errorMessage = 'Server error';
          if (response.statusCode == 503) {
            errorMessage =
                'Server is starting up. Please wait 30 seconds and try again.';
          } else if (response.statusCode == 500) {
            errorMessage = 'Server error. Please try again or contact support.';
          } else if (response.statusCode == 400) {
            errorMessage =
                'Invalid request data. Please check your profile information.';
          } else {
            errorMessage =
                'Error ${response.statusCode}: ${response.body.length > 100 ? response.body.substring(0, 100) + "..." : response.body}';
          }

          throw Exception(errorMessage);
        }
      } catch (e) {
        print('AI Estimation Error (attempt $attempt): $e');

        // If this is the last attempt or not a retryable error, show error to user
        if (attempt >= maxRetries || !e.toString().contains('timed out')) {
          if (mounted) {
            String userMessage = e.toString().replaceFirst('Exception: ', '');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(userMessage),
                duration: const Duration(seconds: 5),
                backgroundColor: Colors.red.shade700,
              ),
            );
          }
          break;
        }

        // Wait before retry
        await Future.delayed(Duration(seconds: 3 * attempt));
      }
    }

    // Cleanup
    if (mounted) {
      setState(() {
        _isEstimatingWithAI = false;
        _showMiniGame = false;
      });
    }
  }

  Future<void> updateCalories() async {
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

  Widget _buildAICalculatedTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Always show input fields
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
                  fillColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  borderColor: const Color(0xFF6366F1),
                  selectedBorderColor: const Color(0xFF6366F1),
                  onPressed: (int index) {
                    setState(() {
                      for (int i = 0; i < genderSelections.length; i++) {
                        genderSelections[i] = i == index;
                      }
                      updateCalories();
                    });
                  },
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Icon(Icons.man),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
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
                      _selectedHeight! >= 120 &&
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
                      _selectedWeight! <= 300) {
                    updateCalories();
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Exercise Level',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Slider(
          value: _exerciseLevel,
          min: 0,
          max: 4,
          divisions: 4,
          label: _getExerciseLevelText(),
          activeColor: const Color(0xFF6366F1),
          inactiveColor: Colors.grey.shade300,
          onChanged: (double value) {
            setState(() {
              _exerciseLevel = value;
              updateCalories();
            });
          },
        ),
        Text(
          _getExerciseLevelText(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _canEstimateWithAI || !_macrosFromAI
                ? () async {
                    _markFieldsChanged();
                    await _estimateWithAI();
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(_macrosFromAI && !_canEstimateWithAI
                ? 'Estimated!'
                : 'Estimate Via AI'),
          ),
        ),
        // Show results after estimation
        if (_macrosFromAI) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: Center(
              child: IntrinsicWidth(
                child: ToggleButtons(
                  isSelected: calorieSelections,
                  selectedColor: Colors.white,
                  fillColor: const Color(0xFF6366F1),
                  borderColor: const Color(0xFF6366F1),
                  selectedBorderColor: const Color(0xFF6366F1),
                  onPressed: (int index) {
                    setState(() {
                      for (int i = 0; i < calorieSelections.length; i++) {
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
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'Lose\n${calorieDeficit ?? 0}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'Maintain\n${calorieMaintenance ?? 0}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
          const Text(
            'Macros',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildReadOnlyMacroField('Protein', _proteinGoal ?? 0),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildReadOnlyMacroField('Carbs', _carbsGoal ?? 0),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildReadOnlyMacroField('Fats', _fatsGoal ?? 0),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: AnimatedBuilder(
              animation: _jiggleAnimation ?? const AlwaysStoppedAnimation(0.0),
              builder: (context, child) {
                return Transform.rotate(
                  angle: _jiggleAnimation?.value ?? 0.0,
                  child: child,
                );
              },
              child: CreditCard(
                key: ValueKey(
                    '${cardActiveCalories}_${_proteinGoal}_${_carbsGoal}_$_fatsGoal'),
                initialCalories: cardActiveCalories ?? 0,
                caloriesOverride: cardActiveCalories ?? 0,
                proteinOverride: (_proteinGoal ?? 0).toDouble(),
                carbsOverride: (_carbsGoal ?? 0).toDouble(),
                fatsOverride: (_fatsGoal ?? 0).toDouble(),
                skipFetch: true,
                onToggleMacros: (showMacros) {
                  _jiggleAnimationController?.forward(from: 0);
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear Today\'s Food'),
                    content: const Text(
                        'This will delete all food items logged for today. This action cannot be undone. Continue?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _clearAllTodaysFoodItems();
                }
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Clear Today\'s Food'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
                              const MainShell(initialIndex: 1),
                        ),
                        (route) => false,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
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
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildReadOnlyMacroField(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${value}g',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualInputTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Calorie Balance',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _manualCalorieController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Calories',
            hintText: 'E.g. 2000',
            floatingLabelBehavior: FloatingLabelBehavior.always,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          onChanged: (value) {
            setState(() {
              _manualCalorieGoal = int.tryParse(value);
              cardActiveCalories = _manualCalorieGoal;
            });
          },
        ),
        const SizedBox(height: 20),
        const Text(
          'Macros',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _proteinGoal = int.tryParse(value);
                  });
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
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
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
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _fatsController,
                focusNode: _fatsFocusNode,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Fats (g)',
                  hintText: 'Fats',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
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
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: AnimatedBuilder(
            animation: _jiggleAnimation ?? const AlwaysStoppedAnimation(0.0),
            builder: (context, child) {
              return Transform.rotate(
                angle: _jiggleAnimation?.value ?? 0.0,
                child: child,
              );
            },
            child: CreditCard(
              key: ValueKey(
                  '${cardActiveCalories}_${_proteinGoal}_${_carbsGoal}_$_fatsGoal'),
              initialCalories: cardActiveCalories ?? 0,
              caloriesOverride: cardActiveCalories ?? 0,
              proteinOverride: (_proteinGoal ?? 0).toDouble(),
              carbsOverride: (_carbsGoal ?? 0).toDouble(),
              fatsOverride: (_fatsGoal ?? 0).toDouble(),
              skipFetch: true,
              onToggleMacros: (showMacros) {
                _jiggleAnimationController?.forward(from: 0);
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Today\'s Food'),
                  content: const Text(
                      'This will delete all food items logged for today. This action cannot be undone. Continue?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Clear All'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _clearAllTodaysFoodItems();
              }
            },
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Clear Today\'s Food'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ),
        const SizedBox(height: 12),
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
                        builder: (context) => const MainShell(initialIndex: 1),
                      ),
                      (route) => false,
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
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
                            padding:
                                EdgeInsets.fromLTRB(8, topPadding + 8, 8, 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1),
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
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
                                // Tabs
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
                                const SizedBox(height: 24),
                                // Tab content
                                if (_selectedTabIndex == 0)
                                  _buildAICalculatedTab()
                                else
                                  _buildManualInputTab(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          if (_isEstimatingWithAI && _showMiniGame) const PingPongGame(),
          if (_isEstimatingWithAI && !_showMiniGame)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
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
