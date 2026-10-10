import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';
import 'package:namer_app/components/measurement_input_field.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/pages/main_shell.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/goal_maths.dart';
import 'package:namer_app/services/profile_limits.dart';
import 'package:namer_app/services/units.dart';
import 'package:namer_app/services/weight_service.dart';
import 'package:namer_app/ui/body_inputs.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/card_reveal.dart';
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

  /// Shown under the activity slider. Display only: the value sent to the
  /// server comes from [_getExerciseLevelText].
  static const List<String> _exerciseLabels = [
    'No exercise',
    'Light: 1–3 hours a week',
    'Moderate: 4–6 hours a week',
    'Active: 7–9 hours a week',
    'Very active: 10+ hours a week',
  ];

  String get _exerciseText {
    final i = _exerciseLevel.round();
    if (i < 0 || i >= _exerciseLabels.length) return _exerciseLabels.first;
    return _exerciseLabels[i];
  }
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

  /// Always cm and kg; [_units] only changes what's shown.
  double? _selectedHeight;
  double? _selectedWeight;

  /// kg/cm or stones/pounds/feet. Starts from the device's country.
  UnitPrefs _units = UnitPrefs.forCountry(
      WidgetsBinding.instance.platformDispatcher.locale.countryCode);

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
  bool _canEstimateWithAI = false;
  Map<String, dynamic>? _lastAIData;

  /// AI targets per goal ('lose', 'maintain', 'gain') from Coach, so
  /// switching goal keeps Coach's macros.
  Map<String, dynamic>? _aiTargets;

  /// "Set my own" instead of "Calculate for me".
  bool _ownMode = false;
  final TextEditingController _manualCalorieController =
      TextEditingController();
  int? _manualCalorieGoal;

  @override
  void initState() {
    super.initState();
    // Wake the lookup server early (it sleeps when idle).
    ProxyClient.warmUp();
    _ageFocusNode = FocusNode();
    _proteinFocusNode = FocusNode();
    _carbsFocusNode = FocusNode();
    _fatsFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _ageFocusNode.dispose();
    _proteinFocusNode.dispose();
    _carbsFocusNode.dispose();
    _fatsFocusNode.dispose();
    _ageController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatsController.dispose();
    _manualCalorieController.dispose();
    super.dispose();
  }

  final date = DateTime.now().add(const Duration(days: 31));

  bool _finishingSetup = false;

  Future<void> saveData() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    final finalCalories = _ownMode ? _manualCalorieGoal : cardActiveCalories;

    if (finalCalories == null || finalCalories <= 0) {
      throw StateError('No calorie goal set');
    }

    // One profile per user. If a previous attempt got as far as creating
    // it, update that one instead of adding a duplicate (two profiles
    // would split the balance between them).
    final existing = await BalanceService.userDataDoc(userId);
    final profileRef = existing?.reference ??
        FirebaseFirestore.instance.collection('user_data').doc(userId);

    await profileRef.set({
      'user_id': userId,
      'age': _selectedAge,
      'gender': genderSelections.first ? 'male' : 'female',
      'height': _selectedHeight,
      'weight': _selectedWeight,
      'exercise_level': _exerciseLevel,
      'calories': finalCalories,
      'calorie_goal': finalCalories,
      'balance_date': BalanceService.dateKey(DateTime.now()),
      'calorie_mode': calorieMode,
      'protein_goal': _proteinGoal ?? 0,
      'carbs_goal': _carbsGoal ?? 0,
      'fats_goal': _fatsGoal ?? 0,
      'protein_balance': _proteinGoal ?? 0,
      'carbs_balance': _carbsGoal ?? 0,
      'fats_balance': _fatsGoal ?? 0,
      ..._units.toFields(),
    });

    // Starts the weight log, so the trend has a first point.
    final kg = _selectedWeight;
    if (kg != null && ProfileLimits.weightOk(kg)) {
      try {
        await WeightService.log(userId, kg);
      } catch (_) {
        // Not worth failing sign-up over; they can log it later.
      }
    }

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

    final mode = calorieSelections[0]
        ? 'lose'
        : calorieSelections[1]
            ? 'maintain'
            : 'gain';
    final aiTarget = _aiTargets?[mode];
    if (aiTarget is Map && aiTarget['protein_g'] != null) {
      setState(() {
        _proteinGoal = asInt(aiTarget['protein_g']);
        _carbsGoal = asInt(aiTarget['carbs_g']);
        _fatsGoal = asInt(aiTarget['fat_g']);
        _proteinController.text = _proteinGoal?.toString() ?? '';
        _carbsController.text = _carbsGoal?.toString() ?? '';
        _fatsController.text = _fatsGoal?.toString() ?? '';
      });
    } else {
      _prefillMacrosFromCalories();
    }
  }

  void _prefillMacrosFromCalories() {
    if (cardActiveCalories == null || (cardActiveCalories ?? 0) <= 0) {
      return;
    }

    final int calories = cardActiveCalories ?? 0;

    // Keep the split they have (30/40/30 if there isn't one yet).
    final m = macrosScaledTo(
      Macros(
        protein: (_proteinGoal ?? 0).toDouble(),
        carbs: (_carbsGoal ?? 0).toDouble(),
        fat: (_fatsGoal ?? 0).toDouble(),
      ),
      calories,
    );
    final int protein = m.protein.round();
    final int carbs = m.carbs.round();
    final int fats = m.fat.round();

    setState(() {
      _proteinGoal = protein;
      _proteinController.text = protein.toString();
      _carbsGoal = carbs;
      _carbsController.text = carbs.toString();
      _fatsGoal = fats;
      _fatsController.text = fats.toString();
    });
  }

  void _updateCaloriesFromMacros() {
    if (_proteinGoal == null || _carbsGoal == null || _fatsGoal == null) {
      return;
    }

    // Calculate calories from macros: Protein & Carbs = 4 cal/g, Fat = 9 cal/g
    final int calculatedCalories = caloriesFromMacros(
        _proteinGoal ?? 0, _carbsGoal ?? 0, _fatsGoal ?? 0);

    setState(() {
      cardActiveCalories = calculatedCalories;
      _manualCalorieGoal = calculatedCalories;
      _manualCalorieController.text = calculatedCalories.toString();
    });
  }

  void signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  /// Signs out and goes back to the sign-in screen.
  Future<void> _signOutAndLeave() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  }

  /// Age, height and weight are all filled in and believable.
  bool get _inputsValid =>
      ProfileLimits.ageOk(_selectedAge) &&
      ProfileLimits.heightOk(_selectedHeight) &&
      ProfileLimits.weightOk(_selectedWeight);

  /// The lowest "Lose" goal for these details (see [safeMinimumCalories]).
  double get _safeFloor => safeMinimumCalories(
        male: genderSelections.first,
        resting: restingCalories(
          age: _selectedAge,
          heightCm: _selectedHeight,
          weightKg: _selectedWeight,
          male: genderSelections.first,
        ),
      );

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

  /// Asks Coach for targets. Returns true only when targets were set.
  Future<bool> _estimateWithAI() async {
    if (_selectedAge == null ||
        _selectedHeight == null ||
        _selectedWeight == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add your age, height and weight first')),
      );
      return false;
    }

    bool gotTargets = false;

    setState(() {
      _isEstimatingWithAI = true;
    });

    try {
      final response = await ProxyClient.post('/macro-targets', {
          'age': _selectedAge,
          'gender': genderSelections.first ? 'male' : 'female',
          'height_cm': _selectedHeight,
          'weight_kg': _selectedWeight,
          'exercise_level': _getExerciseLevelText(),
        });
      if (!mounted) return false;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final raw =
            data['ai']?['final']?['targets'] ?? data['baseline']?['targets'];

        if (raw is Map) {
          final targets = withSafeLoseTarget(
              Map<String, dynamic>.from(raw), _safeFloor);
          setState(() {
            _aiTargets = targets;
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
            _canEstimateWithAI = false;
            _lastAIData = {
              'age': _selectedAge,
              'gender': genderSelections.first,
              'height': _selectedHeight,
              'weight': _selectedWeight,
              'exercise': _exerciseLevel,
            };
          });
          gotTargets = true;
        } else {
          throw Exception('No targets in response');
        }
      } else {
        throw Exception('Failed to estimate macros');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Coach couldn't work out your numbers just now. Try again, or enter them yourself."),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEstimatingWithAI = false;
        });
      }
    }
    return gotTargets;
  }

  void updateCalories() {
    _markFieldsChanged();
    // New details: back to the formula until Coach is asked again.
    _aiTargets = null;

    // Same sums as Goals and profile, so the two never disagree.
    final base = maintenanceCalories(
      age: _selectedAge,
      heightCm: _selectedHeight,
      weightKg: _selectedWeight,
      male: genderSelections.first,
      exerciseLevel: _exerciseLevel,
    );
    if (base != null && base.isFinite && base > 0) {
      calorieDeficit = suggestedCalorieGoal(base, 'lose', floor: _safeFloor);
      calorieMaintenance = suggestedCalorieGoal(base, 'maintain');
      calorieSurplus = suggestedCalorieGoal(base, 'gain');
    } else {
      calorieDeficit = 0;
      calorieMaintenance = 0;
      calorieSurplus = 0;
    }

    // "Set my own" keeps the numbers they typed.
    if (!_ownMode) updateCardActiveCalories();
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
            gradient: AppColors.brandGradient,
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
                  color: AppColors.ink,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.gray600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One option in a row of equal tiles (gender, goal).
  Widget _choiceTile({
    required bool selected,
    required IconData icon,
    required String label,
    String? detail,
    required VoidCallback onTap,
  }) {
    final Color fg = selected ? AppText.primaryDark : AppColors.gray700;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.indigo50 : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: fg,
                      ),
                    ),
                  ),
                  if (detail != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        detail,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

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

  void _selectGender(int index) {
    setState(() {
      for (int i = 0; i < genderSelections.length; i++) {
        genderSelections[i] = i == index;
      }
      updateCalories();
    });
  }

  /// Slim "About you → Goal → Your card" progress line under the header.
  Widget _buildProgress() {
    final int step = _canFinish ? 2 : ((_inputsValid || _ownMode) ? 1 : 0);
    const labels = ['About you', 'Goal', 'Your card'];
    return Semantics(
      label: 'Step ${step + 1} of 3: ${labels[step]}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (int i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= step
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            i == step ? FontWeight.w700 : FontWeight.w500,
                        color: i <= step
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    // Short screens, or the keyboard is up: keep the header small so the
    // form keeps most of the space.
    final bool compact = MediaQuery.viewInsetsOf(context).bottom > 0 ||
        MediaQuery.sizeOf(context).height < 640;

    final Widget signOut = SizedBox(
      width: 80,
      child: Align(
        alignment: Alignment.topRight,
        child: TextButton(
          onPressed: _signOutAndLeave,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('Sign out'),
        ),
      ),
    );

    final Widget badge = compact
        ? const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Welcome to The Calorie Card',
              maxLines: 1,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          )
        : Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.credit_card_rounded,
              size: 36,
              color: Colors.white,
            ),
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, compact ? 12 : 20),
      child: Column(
        children: [
          // Sign out sits top-right, level with the badge.
          Row(
            children: [
              const SizedBox(width: 80),
              Expanded(child: Center(child: badge)),
              signOut,
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Welcome to The Calorie Card',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                "Let's set up your card. It takes about a minute.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          SizedBox(height: compact ? 8 : 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildProgress(),
          ),
        ],
      ),
    );
  }

  /// Imperial heights and weights need two boxes each, so they get a row
  /// of their own; metric ones sit side by side.
  Widget _bodyFields() {
    final height = HeightInput(
      units: _units,
      valueCm: _selectedHeight,
      onChanged: (cm) {
        setState(() {
          _selectedHeight = cm;
          if (ProfileLimits.heightOk(cm)) updateCalories();
        });
      },
    );
    final weight = WeightInput(
      units: _units,
      valueKg: _selectedWeight,
      onChanged: (kg) {
        setState(() {
          _selectedWeight = kg;
          if (ProfileLimits.weightOk(kg)) updateCalories();
        });
      },
    );
    if (_units.isMetric) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: height),
          Expanded(child: weight),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [height, weight],
    );
  }

  Widget _buildAboutYou() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.person_outline,
          title: 'About you',
          subtitle: 'We use this to work out your daily budget',
        ),
        const SizedBox(height: 16),
        // Age & sex
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecor.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MeasurementInputField(
                label: 'Age',
                controller: _ageController,
                focusNode: _ageFocusNode,
                hintText: 'E.g. 30',
                unit: 'years',
                min: ProfileLimits.minAge.toDouble(),
                max: ProfileLimits.maxAge.toDouble(),
                rangeMessage: ProfileLimits.ageRangeMessage,
                onChanged: (value) {
                  setState(() {
                    _selectedAge = value?.round();
                    if (ProfileLimits.ageOk(_selectedAge)) {
                      updateCalories();
                    }
                  });
                },
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Text(
                  'Sex (used to work out your calories)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _choiceTile(
                        selected: genderSelections[0],
                        icon: Icons.man,
                        label: 'Male',
                        onTap: () => _selectGender(0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _choiceTile(
                        selected: genderSelections[1],
                        icon: Icons.woman,
                        label: 'Female',
                        onTap: () => _selectGender(1),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Height & weight, in the units they think in
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecor.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: UnitsPicker(
                  value: _units,
                  onChanged: (u) => setState(() => _units = u),
                ),
              ),
              const SizedBox(height: 4),
              _bodyFields(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Activity level
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecor.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How active are you?',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.ink,
                ),
              ),
              Slider(
                value: _exerciseLevel,
                min: 0,
                max: 4,
                divisions: 4,
                activeColor: AppColors.primary,
                onChanged: (double value) {
                  setState(() {
                    _exerciseLevel = value;
                    updateCalories();
                  });
                },
              ),
              Center(
                child: Text(
                  _exerciseText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppText.primaryDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A goal has been set and the card can be printed.
  bool get _canFinish {
    final calories = _ownMode ? _manualCalorieGoal : cardActiveCalories;
    return calories != null &&
        calories >= 500 &&
        calories <= 10000 &&
        (_ownMode || _inputsValid);
  }

  bool get _personalised => _lastAIData != null && !_canEstimateWithAI;

  void _setOwnMode(bool own) {
    if (own == _ownMode) return;
    setState(() {
      _ownMode = own;
      if (own) {
        // Start from the calculated numbers, so it's a tweak, not a blank.
        final start = cardActiveCalories;
        if (start != null && start > 0 && _manualCalorieGoal == null) {
          _manualCalorieGoal = start;
          _manualCalorieController.text = start.toString();
        }
      }
    });
    if (!own) updateCardActiveCalories();
  }

  Widget _modeButton(bool own, IconData icon, String label) {
    final selected = _ownMode == own;
    return Expanded(
      child: Material(
        color: selected ? AppColors.primaryDark : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _setOwnMode(own),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: selected ? Colors.white : AppColors.gray600),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.gray700,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
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

  Widget _coachButton() {
    if (_isEstimatingWithAI) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('Coach is working it out…'),
      );
    }
    if (_personalised) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: Icon(Icons.check_circle, color: AppText.emerald600, size: 20),
        label: Text(
          'Personalised by Coach',
          style: TextStyle(color: AppText.emerald600),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: _inputsValid ? () => _estimateWithAI() : null,
      icon: const Icon(Icons.auto_awesome, size: 20),
      label: Text(
          _lastAIData != null ? 'Update with Coach' : 'Personalise with Coach'),
    );
  }

  Widget _macroChip(String label, int? grams, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: AppDecor.inset,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              grams == null ? '–' : '${grams}g',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _macroField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required void Function(int?) onValue,
  }) {
    return Expanded(
      child: MeasurementInputField(
        label: label,
        controller: controller,
        focusNode: focusNode,
        hintText: hintText,
        unit: 'g',
        onChanged: (value) {
          setState(() {
            onValue(value?.round());
          });
          _updateCaloriesFromMacros();
        },
      ),
    );
  }

  /// Your goal: worked out as you type, or your own numbers.
  Widget _buildGoal() {
    final hasNumbers = _inputsValid && (calorieMaintenance ?? 0) > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecor.card,
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
                _modeButton(false, Icons.auto_awesome, 'Calculate for me'),
                _modeButton(true, Icons.edit_note, 'Set my own'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!_ownMode) ...[
            Text(
              hasNumbers
                  ? 'Pick a goal. The numbers update as you change your details.'
                  : 'Fill in your age, height and weight to see your numbers.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _choiceTile(
                    selected: calorieSelections[0],
                    icon: Icons.trending_down,
                    label: 'Lose',
                    detail: hasNumbers
                        ? '${formatCardKcal(calorieDeficit ?? 0)} kcal'
                        : '–',
                    onTap: () => _selectGoal(0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _choiceTile(
                    selected: calorieSelections[1],
                    icon: Icons.horizontal_rule,
                    label: 'Maintain',
                    detail: hasNumbers
                        ? '${formatCardKcal(calorieMaintenance ?? 0)} kcal'
                        : '–',
                    onTap: () => _selectGoal(1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _choiceTile(
                    selected: calorieSelections[2],
                    icon: Icons.trending_up,
                    label: 'Gain',
                    detail: hasNumbers
                        ? '${formatCardKcal(calorieSurplus ?? 0)} kcal'
                        : '–',
                    onTap: () => _selectGoal(2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Daily macros',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _macroChip('Protein', hasNumbers ? _proteinGoal : null,
                    CalorieCardColors.protein),
                const SizedBox(width: 8),
                _macroChip('Carbs', hasNumbers ? _carbsGoal : null,
                    CalorieCardColors.carbs),
                const SizedBox(width: 8),
                _macroChip('Fat', hasNumbers ? _fatsGoal : null,
                    CalorieCardColors.fat),
              ],
            ),
            const SizedBox(height: 16),
            _coachButton(),
            const SizedBox(height: 6),
            Text(
              'Optional. Coach fine-tunes your calories and macros from '
              'your details.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ] else ...[
            Text(
              'Daily calorie budget',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _manualCalorieController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              decoration: InputDecoration(
                labelText: 'kcal',
                hintText: 'E.g. 2000',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
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
                  _prefillMacrosFromCalories();
                });
              },
            ),
            LowCalorieNote(calories: _manualCalorieGoal),
            const SizedBox(height: 16),
            Text(
              'Daily macros',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _macroField(
                  label: 'Protein',
                  controller: _proteinController,
                  focusNode: _proteinFocusNode,
                  hintText: 'E.g. 150',
                  onValue: (value) => _proteinGoal = value,
                ),
                _macroField(
                  label: 'Carbs',
                  controller: _carbsController,
                  focusNode: _carbsFocusNode,
                  hintText: 'E.g. 200',
                  onValue: (value) => _carbsGoal = value,
                ),
                _macroField(
                  label: 'Fat',
                  controller: _fatsController,
                  focusNode: _fatsFocusNode,
                  hintText: 'E.g. 65',
                  onValue: (value) => _fatsGoal = value,
                ),
              ],
            ),
            Text(
              'Changing a macro updates your calories to match.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  /// Opens the card reveal, which saves the card while it "prints".
  Future<void> _finishSetup() async {
    if (_finishingSetup || !_canFinish) return;
    FocusScope.of(context).unfocus();
    setState(() => _finishingSetup = true);
    final calories =
        (_ownMode ? _manualCalorieGoal : cardActiveCalories) ?? 0;
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final holder = cardholderFromEmail(email);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (revealContext) => CardRevealPage(
          save: saveData,
          calories: calories,
          protein: _proteinGoal ?? 0,
          carbs: _carbsGoal ?? 0,
          fat: _fatsGoal ?? 0,
          holder: holder.isEmpty ? 'You' : holder,
          onDone: () {
            Navigator.of(revealContext, rootNavigator: true)
                .pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => const MainShell(initialIndex: 1),
              ),
              (route) => false,
            );
          },
        ),
      ),
    );
    // Back from a failed save: let them try again.
    if (mounted) setState(() => _finishingSetup = false);
  }

  Widget _buildFinish() {
    final int calories =
        (_ownMode ? _manualCalorieGoal : cardActiveCalories) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_canFinish)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${formatCardKcal(calories)} kcal a day · '
              '${_proteinGoal ?? 0}g protein · '
              '${_carbsGoal ?? 0}g carbs · '
              '${_fatsGoal ?? 0}g fat',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.gray700,
              ),
            ),
          ),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _finishingSetup || !_canFinish ? null : _finishSetup,
            style: FilledButton.styleFrom(
              disabledBackgroundColor:
                  AppColors.primaryDark.withValues(alpha: 0.6),
              disabledForegroundColor: Colors.white,
            ),
            child: _finishingSetup
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.credit_card_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Print my card',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
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
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  // Main content sheet
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.only(
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
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _buildAboutYou(),
                                const SizedBox(height: 24),
                                _buildSectionHeader(
                                  icon: Icons.track_changes,
                                  title: 'Your goal',
                                  subtitle:
                                      'How many calories a day, and how to split them',
                                ),
                                const SizedBox(height: 16),
                                _buildGoal(),
                                const SizedBox(height: 24),
                                _buildFinish(),
                                if (!_canFinish)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      _ownMode
                                          ? 'Enter a daily budget between '
                                              '500 and 10,000 kcal.'
                                          : 'Fill in your details above to '
                                              'print your card.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.muted),
                                    ),
                                  ),
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
        ],
      ),
    );
  }
}
