import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/components/measurement_input_field.dart';
import 'package:namer_app/components/mini_game.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/pages/main_shell.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/spotlight_tour.dart';
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
  Map<String, dynamic>? _lastAIData;

  // Flow state: 'input' = entering personal data, 'calculation' = choosing method, 'results' = confirming values
  String _flowState = 'input'; // 'input', 'calculation', 'results'
  final TextEditingController _manualCalorieController =
      TextEditingController();
  int? _manualCalorieGoal;

  // First-time walkthrough of the card once it's revealed.
  final _cardTour = CardTourKeys();
  final _tourCard = GlobalKey(debugLabel: 'tour-card');
  bool _cardTourStarted = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_maybeStartCardTour);
    // Wake the lookup server early (it sleeps when idle).
    ProxyClient.warmUp();
    _ageFocusNode = FocusNode();
    _heightFocusNode = FocusNode();
    _weightFocusNode = FocusNode();
    _proteinFocusNode = FocusNode();
    _carbsFocusNode = FocusNode();
    _fatsFocusNode = FocusNode();
  }

  /// Walks through each part of the card the first time it has numbers on
  /// it, and not while they're typing.
  bool _cardReadyForTour() {
    if (!mounted || _flowState != 'results') return false;
    // The card is filled in: a balance and all three macros.
    if ((cardActiveCalories ?? 0) <= 0 ||
        _proteinGoal == null ||
        _carbsGoal == null ||
        _fatsGoal == null) {
      return false;
    }
    // Not while they're typing.
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        focus.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    return _tourCard.currentContext != null;
  }

  void _maybeStartCardTour() {
    if (_cardTourStarted || !_cardReadyForTour()) return;
    _cardTourStarted = true;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_cardReadyForTour()) {
        _cardTourStarted = false;
        return;
      }
      SpotlightTour.showOnce(context,
          id: 'card_intro', canStart: _cardReadyForTour, steps: [
        TourStep(
          target: _tourCard,
          title: 'This is your Calorie Card',
          body: 'Think of calories like money. Your card is topped up every '
              'day, and the food you log is spent from it.',
          padding: 6,
          radius: 24,
        ),
        TourStep(
          target: _cardTour.balance,
          title: 'Your calorie balance',
          body: "What you've got left to spend today. If you go over, it "
              'turns red with a minus.',
          radius: 10,
        ),
        TourStep(
          target: _cardTour.protein,
          title: 'Protein allowance',
          body: "How much protein you've got left today. It keeps you full "
              'and helps build muscle.',
          radius: 10,
        ),
        TourStep(
          target: _cardTour.carbs,
          title: 'Carbs allowance',
          body: 'Your main energy for the day: bread, rice, pasta, fruit '
              'and the like.',
          radius: 10,
        ),
        TourStep(
          target: _cardTour.fat,
          title: 'Fat allowance',
          body: 'Fats from things like oils, nuts, cheese and meat. You need '
              'some, but they add up fast.',
          radius: 10,
        ),
        TourStep(
          target: _cardTour.holder,
          title: 'Your name',
          body: 'Your name goes on your card, just like a real one. Friends '
              'see it too.',
          radius: 10,
        ),
        TourStep(
          target: _cardTour.validThru,
          title: "Today's date",
          body: 'Each card is good for one day. At midnight it starts again '
              'with a full balance.',
          radius: 10,
        ),
      ]).then((done) {
        // Couldn't show yet (e.g. they started typing): try again later.
        if (!done && mounted) _cardTourStarted = false;
      });
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_maybeStartCardTour);
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

  bool _finishingSetup = false;

  Future<void> saveData() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    // Use manual calorie goal if no AI data (manual input path), otherwise use AI calculated
    final finalCalories = _lastAIData == null && _manualCalorieGoal != null
        ? _manualCalorieGoal
        : cardActiveCalories;

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

  void _updateCaloriesFromMacros() {
    if (_proteinGoal == null || _carbsGoal == null || _fatsGoal == null) {
      return;
    }

    // Calculate calories from macros: Protein & Carbs = 4 cal/g, Fat = 9 cal/g
    final int calculatedCalories =
        ((_proteinGoal ?? 0) * 4) + ((_carbsGoal ?? 0) * 4) + ((_fatsGoal ?? 0) * 9);

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
  bool get _inputsValid {
    final age = _selectedAge;
    final height = _selectedHeight;
    final weight = _selectedWeight;
    return age != null &&
        age >= 13 &&
        age <= 120 &&
        height != null &&
        height >= 100 &&
        height <= 250 &&
        weight != null &&
        weight >= 30 &&
        weight <= 350;
  }

  /// 2150 -> "2,150".
  String _thousands(int n) {
    final digits = n.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return n < 0 ? '-$out' : out.toString();
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

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final targets =
            data['ai']?['final']?['targets'] ?? data['baseline']?['targets'];

        if (targets != null) {
          setState(() {
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
          _showMiniGame = false;
        });
      }
    }
    return gotTargets;
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.ink,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
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
    final Color fg = selected ? AppColors.primaryDark : AppColors.gray700;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.indigo50 : Colors.white,
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
                        style: const TextStyle(
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
    final int step = _flowState == 'results' ? 2 : (_inputsValid ? 1 : 0);
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
        // Age & gender
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecor.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                ],
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Text(
                  'Gender',
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
        // Height & weight
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecor.card,
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
        // Activity level
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecor.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Choose between Coach working it out and typing your own numbers.
  Widget _buildMethodChoice() {
    final bool canAsk = _inputsValid &&
        (_canEstimateWithAI || _lastAIData == null) &&
        !_isEstimatingWithAI;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecor.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'How should we set your budget?',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: canAsk
                  ? () async {
                      final ok = await _estimateWithAI();
                      if (ok && mounted) {
                        setState(() {
                          _flowState = 'results';
                        });
                        WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _maybeStartCardTour());
                      }
                    }
                  : null,
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: const Text(
                'Let Coach work it out',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (!_inputsValid) ...[
            const SizedBox(height: 8),
            const Text(
              'Fill in your age, height and weight to continue',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _flowState = 'results';
                  _manualCalorieGoal = null;
                  _manualCalorieController.clear();
                });
              },
              icon: const Icon(Icons.edit_note, size: 20),
              label: const Text(
                "I'll enter my own",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
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
    return MeasurementInputField(
      label: label,
      controller: controller,
      focusNode: focusNode,
      hintText: hintText,
      suffix: 'g',
      onChanged: (value) {
        setState(() {
          onValue(value);
        });
        _updateCaloriesFromMacros();
      },
    );
  }

  Widget _buildResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _flowState = 'input';
                });
              },
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Change how we set it'),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecor.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Manual calorie entry
              if (_lastAIData == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
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
                    ],
                  ),
                )
              else ...[
                // Goal selection (Coach's results)
                const Text(
                  'Pick your goal',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gray800,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _choiceTile(
                        selected: calorieSelections[0],
                        icon: Icons.trending_down,
                        label: 'Lose',
                        detail: '${_thousands(calorieDeficit ?? 0)} kcal',
                        onTap: () => _selectGoal(0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _choiceTile(
                        selected: calorieSelections[1],
                        icon: Icons.horizontal_rule,
                        label: 'Maintain',
                        detail: '${_thousands(calorieMaintenance ?? 0)} kcal',
                        onTap: () => _selectGoal(1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _choiceTile(
                        selected: calorieSelections[2],
                        icon: Icons.trending_up,
                        label: 'Gain',
                        detail: '${_thousands(calorieSurplus ?? 0)} kcal',
                        onTap: () => _selectGoal(2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              // Macros
              const Text(
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
                ],
              ),
              Row(
                children: [
                  _macroField(
                    label: 'Fat',
                    controller: _fatsController,
                    focusNode: _fatsFocusNode,
                    hintText: 'E.g. 65',
                    onValue: (value) => _fatsGoal = value,
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Card preview
        KeyedSubtree(
          key: _tourCard,
          child: CreditCard(
            key: ValueKey(
                '${cardActiveCalories}_${_proteinGoal}_${_carbsGoal}_$_fatsGoal'),
            initialCalories: cardActiveCalories ?? 0,
            caloriesOverride: cardActiveCalories ?? 0,
            proteinOverride: (_proteinGoal ?? 0).toDouble(),
            carbsOverride: (_carbsGoal ?? 0).toDouble(),
            fatsOverride: (_fatsGoal ?? 0).toDouble(),
            skipFetch: true,
            tourKeys: _cardTour,
          ),
        ),
      ],
    );
  }

  Future<void> _finishSetup() async {
    // Save first (and only once): the card reads this data as soon as the
    // app opens.
    if (_finishingSetup) return;
    setState(() => _finishingSetup = true);
    try {
      await saveData();
    } catch (e) {
      if (!mounted) return;
      setState(() => _finishingSetup = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is StateError
            ? 'Set your daily calorie budget first.'
            : "Couldn't save your card. Check your connection and try again."),
      ));
      return;
    }
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const MainShell(initialIndex: 1),
      ),
      (route) => false,
    );
  }

  Widget _buildFinish() {
    final int calories = cardActiveCalories ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (calories > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${_thousands(calories)} kcal a day · '
              '${_proteinGoal ?? 0}g protein · '
              '${_carbsGoal ?? 0}g carbs · '
              '${_fatsGoal ?? 0}g fat',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.gray700,
              ),
            ),
          ),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _finishingSetup ? null : _finishSetup,
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
                      Icon(Icons.check_circle, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Activate my card',
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

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: AppDecor.card,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Coach is working out\nyour daily budget…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showMiniGame = true;
                      });
                    },
                    icon: const Icon(Icons.sports_esports, size: 18),
                    label: const Text(
                      'Play a quick game while you wait',
                      textAlign: TextAlign.center,
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
                      decoration: const BoxDecoration(
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
                                      'Pick a goal and check your daily allowance',
                                ),
                                const SizedBox(height: 16),
                                if (_flowState == 'input')
                                  _buildMethodChoice()
                                else if (_flowState == 'results')
                                  _buildResults(),
                                const SizedBox(height: 24),
                                // Save button (only once results are ready)
                                if (_flowState == 'results') _buildFinish(),
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
          if (_isEstimatingWithAI && !_showMiniGame) _buildLoadingOverlay(),
        ],
      ),
    );
  }
}
