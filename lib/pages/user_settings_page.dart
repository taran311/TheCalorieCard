import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/components/measurement_input_field.dart';
import 'package:namer_app/components/mini_game.dart';
import 'package:namer_app/pages/main_shell.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/services/card_design_service.dart';
import 'dart:convert';

/// Calories a day to stay the same weight: Mifflin–St Jeor times an
/// activity factor for [exerciseLevel] (0 = little or none ... 4 = 10+
/// hours a week). Null if age, height or weight is missing.
double? maintenanceCalories({
  required int? age,
  required int? heightCm,
  required int? weightKg,
  required bool male,
  required double exerciseLevel,
}) {
  if (age == null || heightCm == null || weightKg == null) return null;
  const multipliers = [1.2, 1.375, 1.55, 1.725, 1.9];
  final level = exerciseLevel.round().clamp(0, 4).toInt();
  return ((10 * weightKg) + (6.25 * heightCm) - (5 * age) + (male ? 5 : -161)) *
      multipliers[level];
}

/// The suggested daily calorie goal for a goal [mode] ('lose', 'maintain'
/// or 'gain'; anything else counts as 'lose', as Settings does).
int suggestedCalorieGoal(double maintenance, String? mode) {
  if (mode == 'maintain') return maintenance.round();
  if (mode == 'gain') return (maintenance * 1.15).round();
  return (maintenance * 0.85).round();
}

/// A default macro split for a calorie goal (30% protein, 40% carbs,
/// 30% fat), used when there are no AI targets.
Macros defaultMacrosFor(int calories) => Macros(
      calories: calories.toDouble(),
      protein: (calories * 0.30 / 4).round().toDouble(),
      carbs: (calories * 0.40 / 4).round().toDouble(),
      fat: (calories * 0.30 / 9).round().toDouble(),
    );

/// A message that is safe to show as-is when working out targets fails.
class _EstimateError implements Exception {
  final String message;
  const _EstimateError(this.message);

  @override
  String toString() => message;
}

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

  CardDesign _cardDesign = CardDesign.midnight;

  @override
  void initState() {
    super.initState();
    // Open a connection to the lookup server early.
    ProxyClient.warmUp();

    // Show the preview card in your chosen finish.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      CardDesignService.watch(uid).first.then((d) {
        if (mounted) setState(() => _cardDesign = d);
      }, onError: (_) {});
    }

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

  bool _isSaving = false;

  // AI estimation state
  bool _isEstimatingWithAI = false;
  bool _showMiniGame = false;
  bool _canEstimateWithAI = false;
  bool _macrosFromAI = false;
  Map<String, dynamic>? _lastAIData;
  bool _showAIResults = false; // Toggle between inputs and results in AI tab

  // Tab state
  int _selectedTabIndex = 0; // 0 = AI Calculated, 1 = Manual Input
  final TextEditingController _manualCalorieController =
      TextEditingController();
  int? _manualCalorieGoal;

  /// AI targets per goal ('lose', 'maintain', 'gain'), from the last
  /// estimate, so switching goal keeps the AI's macros.
  Map<String, dynamic>? _aiTargets;

  Future<void> _clearAllTodaysFoodItems() async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      // Removes today's food (recipes you've saved are kept) and puts the
      // card back to your full daily goals.
      final count = await BalanceService.clearToday(userId);
      FoodLog.notifyChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(count == 0
                  ? 'Nothing logged today'
                  : 'Cleared $count food item${count == 1 ? '' : 's'} from today')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't clear today's food. Please try again.")),
        );
      }
    }
  }

  /// The calorie goal that Save will store.
  double get _goalToSave {
    if (_selectedTabIndex == 1 && _manualCalorieGoal != null) {
      return _manualCalorieGoal!.toDouble();
    }
    return (cardActiveCalories ??
            calorieMaintenance ??
            calorieDeficit ??
            calorieSurplus ??
            0)
        .toDouble();
  }

  /// Saves the profile and goals. Today's card becomes the new goal minus
  /// what's already been eaten today. Returns an error message, or null
  /// when saved.
  Future<String?> saveData() async {
    final goal = _goalToSave;
    if (goal < 500 || goal > 10000) {
      return 'Set a daily calorie goal between 500 and 10,000 first.';
    }
    if (_proteinGoal == null || _carbsGoal == null || _fatsGoal == null) {
      return 'Fill in protein, carbs and fat (0 is fine).';
    }
    if (_proteinGoal! < 0 || _carbsGoal! < 0 || _fatsGoal! < 0) {
      return "Macros can't be negative.";
    }

    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      await BalanceService.applyGoals(
        userId,
        goals: Macros(
          calories: goal,
          protein: _proteinGoal!.toDouble(),
          carbs: _carbsGoal!.toDouble(),
          fat: _fatsGoal!.toDouble(),
        ),
        extra: {
          'age': _selectedAge,
          'height': _selectedHeight,
          'weight': _selectedWeight,
          'exercise_level': _exerciseLevel,
          'gender': genderSelections.first ? 'male' : 'female',
          'calorie_mode': calorieMode,
          // Reopening Settings shows the tab these goals came from.
          'goal_source': _selectedTabIndex == 1 ? 'manual' : 'calculated',
        },
      );
      FoodLog.notifyChanged();
      return null;
    } catch (e) {
      return "Couldn't save your changes. Check your connection and try again.";
    }
  }

  Future<void> _onSavePressed() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });
    final error = await saveData();
    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.red700),
      );
      return;
    }
    // The messenger sits above the navigator, so the message stays up
    // after this page is replaced.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const MainShell(initialIndex: 1),
      ),
      (route) => false,
    );
    messenger.showSnackBar(
      const SnackBar(content: Text('Goals saved. Your card is up to date.')),
    );
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

        setState(() {
          _selectedAge = asInt(userData['age']);
          _ageController.text =
              _selectedAge != null ? '$_selectedAge years' : '';
          _selectedHeight = asInt(userData['height']);
          _heightController.text =
              _selectedHeight != null ? '${_selectedHeight}cm' : '';
          _selectedWeight = asInt(userData['weight']);
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

          _proteinGoal = asInt(userData['protein_goal']);
          _carbsGoal = asInt(userData['carbs_goal']);
          _fatsGoal = asInt(userData['fats_goal']);
          _proteinController.text = _proteinGoal?.toString() ?? '';
          _carbsController.text = _carbsGoal?.toString() ?? '';
          _fatsController.text = _fatsGoal?.toString() ?? '';

          // Load calorie_goal for manual input
          final calorieGoal = asInt(userData['calorie_goal']);
          if (calorieGoal != null) {
            _manualCalorieGoal = calorieGoal;
            _manualCalorieController.text = calorieGoal.toString();
          }

          updateCalories();
          updateCardActiveCalories();

          // Show what's saved, not a fresh estimate: opening Settings and
          // pressing Save must not change your goals.
          final storedGoal = BalanceService.calorieGoalFrom(userData)?.round();
          if (storedGoal != null && storedGoal > 0) {
            cardActiveCalories = storedGoal;
          }
          _proteinGoal = asInt(userData['protein_goal']);
          _carbsGoal = asInt(userData['carbs_goal']);
          _fatsGoal = asInt(userData['fats_goal']);
          _proteinController.text = _proteinGoal?.toString() ?? '';
          _carbsController.text = _carbsGoal?.toString() ?? '';
          _fatsController.text = _fatsGoal?.toString() ?? '';
          if (userData['goal_source'] == 'manual') {
            _selectedTabIndex = 1;
          } else if (storedGoal != null && storedGoal > 0) {
            // Returning users see their saved goal (and Save) straight away.
            _showAIResults = true;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Couldn't load your details. Check your connection and try again."),
          ),
        );
      }
    } finally {
      if (mounted) {
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

    final mode = calorieSelections[0]
        ? 'lose'
        : calorieSelections[1]
            ? 'maintain'
            : 'gain';
    final aiTarget = _aiTargets?[mode];

    setState(() {
      cardActiveCalories = selectedCalories;
      if (aiTarget is Map && aiTarget['protein_g'] != null) {
        // Keep the AI's macros for this goal rather than a generic split.
        _proteinGoal = asInt(aiTarget['protein_g']);
        _carbsGoal = asInt(aiTarget['carbs_g']);
        _fatsGoal = asInt(aiTarget['fat_g']);
        _proteinController.text = _proteinGoal?.toString() ?? '';
        _carbsController.text = _carbsGoal?.toString() ?? '';
        _fatsController.text = _fatsGoal?.toString() ?? '';
      } else {
        _prefillMacrosFromCalories(selectedCalories);
      }
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

  /// What the activity slider shows. (The server gets
  /// [_getExerciseLevelText], which must not change.)
  String _exerciseLevelLabel() {
    switch (_exerciseLevel.round()) {
      case 1:
        return '1–3 hours a week';
      case 2:
        return '4–6 hours a week';
      case 3:
        return '7–9 hours a week';
      case 4:
        return '10+ hours a week';
      default:
        return 'Little or none';
    }
  }

  /// Sent to the server as `exercise_level`; keep these values as they are.
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
            content: Text('Fill in your age, height and weight first.')),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trying again…'),
              duration: Duration(seconds: 2),
            ),
          );
        }

        final response = await ProxyClient.post('/macro-targets', {
            'age': _selectedAge,
            'gender': genderSelections.first ? 'male' : 'female',
            'height_cm': _selectedHeight,
            'weight_kg': _selectedWeight,
            'exercise_level': _getExerciseLevelText(),
          })
            .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            // The retry check below looks for "timed out".
            throw const _EstimateError(
                'That timed out. Please try again in a moment.');
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final targets =
              data['ai']?['final']?['targets'] ?? data['baseline']?['targets'];

          if (targets != null) {
            setState(() {
              _aiTargets = Map<String, dynamic>.from(targets as Map);
              calorieDeficit = asInt(targets['lose']?['calories']);
              calorieMaintenance = asInt(targets['maintain']?['calories']);
              calorieSurplus = asInt(targets['gain']?['calories']);

              // Set macros based on selected goal
              final selectedTarget = calorieSelections[0]
                  ? targets['lose']
                  : calorieSelections[1]
                      ? targets['maintain']
                      : targets['gain'];

              _proteinGoal = asInt(selectedTarget?['protein_g']);
              _carbsGoal = asInt(selectedTarget?['carbs_g']);
              _fatsGoal = asInt(selectedTarget?['fat_g']);

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

              // Reset mini game and estimation state on success
              _isEstimatingWithAI = false;
              _showMiniGame = false;
            });

            // Success - exit retry loop
            return;
          } else {
            throw const _EstimateError(
                "Couldn't work out your targets just now. Please try again.");
          }
        } else if (response.statusCode == 503 && attempt < maxRetries) {
          // Busy for a moment: wait and retry.
          debugPrint('macro-targets: 503, retrying');
          await Future.delayed(Duration(seconds: 5 * attempt));
          continue;
        } else {
          debugPrint('macro-targets failed: status ${response.statusCode}');

          String errorMessage;
          if (response.statusCode == 503) {
            errorMessage =
                "The server's busy right now. Please try again in a minute.";
          } else if (response.statusCode == 500) {
            errorMessage = 'Something went wrong on our side. Please try again.';
          } else if (response.statusCode == 400) {
            errorMessage =
                'Some of your details look wrong. Check your age, height and weight.';
          } else {
            errorMessage =
                "Couldn't work out your targets just now. Please try again.";
          }

          throw _EstimateError(errorMessage);
        }
      } catch (e) {
        debugPrint('macro-targets error (attempt $attempt): $e');

        // Only our own messages are shown; anything else (no connection,
        // a bad reply) gets a friendly fallback.
        final userMessage = e is _EstimateError
            ? e.message
            : "Couldn't reach the server. Check your connection and try again.";

        // If this is the last attempt or not a retryable error, show error to user
        if (attempt >= maxRetries || !userMessage.contains('timed out')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(userMessage),
                duration: const Duration(seconds: 5),
                backgroundColor: AppColors.red700,
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
    _aiTargets = null;

    final base = maintenanceCalories(
      age: _selectedAge,
      heightCm: _selectedHeight,
      weightKg: _selectedWeight,
      male: genderSelections.first,
      exerciseLevel: _exerciseLevel,
    );
    if (base != null && base.isFinite) {
      calorieDeficit = suggestedCalorieGoal(base, 'lose');
      calorieMaintenance = suggestedCalorieGoal(base, 'maintain');
      calorieSurplus = suggestedCalorieGoal(base, 'gain');
    } else {
      calorieDeficit = 0;
      calorieMaintenance = 0;
      calorieSurplus = 0;
    }

    updateCardActiveCalories();
  }

  bool isLoading = false;

  bool get _hasGoal => (cardActiveCalories ?? 0) > 0;

  void _selectGoal(int index) {
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
  }

  Widget _goalOption(IconData icon, String label, int? kcal) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          Text(
            '${kcal ?? 0}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// The card preview, which jiggles when you flip to the macros side.
  Widget _cardPreview() {
    return Center(
      // Keep the card at its natural size; the stretch column
      // would otherwise pull it to full width.
      child: AnimatedBuilder(
        animation: _jiggleAnimation ?? const AlwaysStoppedAnimation(0.0),
        builder: (context, child) {
          return Transform.rotate(
            angle: _jiggleAnimation?.value ?? 0.0,
            child: child,
          );
        },
        child: CreditCard(
          design: _cardDesign,
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
    );
  }

  Widget _buildAICalculatedTab() {
    // Show Results View
    if (_showAIResults) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _showAIResults = false;
              });
            },
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to my details'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Your goal',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.gray800,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            // Shrinks to fit on very narrow phones instead of overflowing.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ToggleButtons(
                isSelected: calorieSelections,
                selectedColor: Colors.white,
                fillColor: AppColors.primary,
                borderColor: AppColors.primary,
                selectedBorderColor: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
                onPressed: _selectGoal,
                constraints: const BoxConstraints(
                  minWidth: 84,
                  minHeight: 52,
                ),
                children: [
                  _goalOption(Icons.trending_down, 'Lose', calorieDeficit),
                  _goalOption(
                      Icons.horizontal_rule, 'Maintain', calorieMaintenance),
                  _goalOption(Icons.trending_up, 'Gain', calorieSurplus),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Macros',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 12),
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
                child: _buildReadOnlyMacroField('Fat', _fatsGoal ?? 0),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _cardPreview(),
        ],
      );
    }

    // Show Inputs View
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            MeasurementInputField(
              label: 'Age',
              controller: _ageController,
              focusNode: _ageFocusNode,
              hintText: 'E.g. 30',
              suffix: ' years',
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
                  selectedColor: AppColors.primary,
                  fillColor: AppColors.primary.withValues(alpha: 0.2),
                  borderColor: AppColors.primary,
                  selectedBorderColor: AppColors.primary,
                  onPressed: (int index) {
                    setState(() {
                      for (int i = 0; i < genderSelections.length; i++) {
                        genderSelections[i] = i == index;
                      }
                      updateCalories();
                    });
                  },
                  children: const [
                    Tooltip(
                      message: 'Male',
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Icon(Icons.man, semanticLabel: 'Male'),
                      ),
                    ),
                    Tooltip(
                      message: 'Female',
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Icon(Icons.woman, semanticLabel: 'Female'),
                      ),
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
          'Activity',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Slider(
          value: _exerciseLevel,
          min: 0,
          max: 4,
          divisions: 4,
          label: _exerciseLevelLabel(),
          activeColor: AppColors.primary,
          inactiveColor: AppColors.gray300,
          onChanged: (double value) {
            setState(() {
              _exerciseLevel = value;
              updateCalories();
            });
          },
        ),
        Text(
          _exerciseLevelLabel(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _canEstimateWithAI || !_macrosFromAI
                ? () async {
                    _markFieldsChanged();
                    await _estimateWithAI();
                  }
                : null,
            icon: const Icon(Icons.auto_awesome, size: 20),
            label: Text(_macrosFromAI && !_canEstimateWithAI
                ? 'Done'
                : 'Work out my targets'),
          ),
        ),
        if (_hasGoal) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _showAIResults = true;
                });
              },
              child: const Text('Review and save'),
            ),
          ),
        ]
        // Empty state when nothing has been worked out yet
        else if (!_macrosFromAI) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: AppDecor.inset,
            child: Column(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 48,
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Let us work out your targets',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gray800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Fill in your details, then tap "Work out my targets".',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.gray600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReadOnlyMacroField(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gray300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.gray600,
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

  InputDecoration _numberDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
    );
  }

  Widget _buildManualInputTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Daily calorie goal',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _manualCalorieController,
          keyboardType: TextInputType.number,
          decoration: _numberDecoration('Calories', 'E.g. 2000'),
          onChanged: (value) {
            setState(() {
              _manualCalorieGoal = int.tryParse(value);
              cardActiveCalories = _manualCalorieGoal;
              _prefillMacrosFromCalories(_manualCalorieGoal);
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
                decoration: _numberDecoration('Protein (g)', 'Protein'),
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
                decoration: _numberDecoration('Carbs (g)', 'Carbs'),
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
                decoration: _numberDecoration('Fat (g)', 'Fat'),
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
        _cardPreview(),
      ],
    );
  }

  Future<void> _confirmClearToday() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear today's food?"),
        content: const Text(
            "This removes everything you've logged today and puts your card "
            'back to your full daily goal. Saved recipes are kept. '
            "You can't undo this."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear today'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _clearAllTodaysFoodItems();
    }
  }

  void _selectTab(int index) {
    setState(() {
      _selectedTabIndex = index;
      if (index == 1 && _manualCalorieGoal != null) {
        cardActiveCalories = _manualCalorieGoal;
      }
    });
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final selected = _selectedTabIndex == index;
    return Expanded(
      child: Material(
        color: selected ? AppColors.primaryDark : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _selectTab(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : AppColors.gray600,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.gray700,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Goals and profile')),
      body: Stack(
        children: [
          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else
            SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: Breakpoints.contentMaxWidth),
                    child: Container(
                      decoration: AppDecor.card,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.gray100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                _tabButton(0, Icons.auto_awesome, 'Calculate'),
                                _tabButton(1, Icons.edit_note, 'Set my own'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_selectedTabIndex == 0)
                            _buildAICalculatedTab()
                          else
                            _buildManualInputTab(),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              // _onSavePressed ignores taps while saving.
                              onPressed: _onSavePressed,
                              child: _isSaving
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : const Text(
                                      'Save goals',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton.icon(
                              onPressed: _confirmClearToday,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.red600,
                              ),
                              icon: const Icon(Icons.delete_sweep),
                              label: const Text("Clear today's food"),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Working out your calories and macros…',
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
                          label: const Text('Play ping pong while you wait'),
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
