import 'package:namer_app/services/analytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/ui/responsive.dart';
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
import 'package:namer_app/ui/profile_editors.dart';
import 'package:namer_app/ui/calorie_symbol.dart';

/// Setting up a new card, one question per screen: about you, your goal
/// (with a goal weight and pace), then your plan and "Print my card".
class GetStartedPage extends StatefulWidget {
  GetStartedPage({super.key});

  @override
  State<GetStartedPage> createState() => _GetStartedPageState();
}

enum _Step { sex, age, height, weight, activity, goal, target, pace, plan }

class _GetStartedPageState extends State<GetStartedPage> {
  // About you
  bool? _male;
  int? _age;
  final _ageController = TextEditingController();
  double? _heightCm;
  double? _weightKg;
  double? _activity;

  /// kg/cm or stones/pounds/feet. Starts from the device's country.
  UnitPrefs _units = UnitPrefs.forCountry(
      WidgetsBinding.instance.platformDispatcher.locale.countryCode);

  // Goal
  String? _mode;
  double? _goalKg;
  GoalPace _pace = GoalPace.steady;

  // Plan
  bool _ownCalories = false;
  final _caloriesController = TextEditingController();
  int? _manualCalories;

  /// Macros once they've been changed; until then a default split of the
  /// plan's calories.
  ({int p, int c, int f})? _macros;
  bool _editingMacros = false;

  int _index = 0;
  bool _goingBack = false;

  /// A tapped option is about to move on: ignore a second tap meanwhile.
  bool _advancing = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    // Wake the lookup server early (it sleeps when idle).
    ProxyClient.warmUp();
  }

  @override
  void dispose() {
    _ageController.dispose();
    _caloriesController.dispose();
    super.dispose();
  }

  List<_Step> get _steps => [
        _Step.sex,
        _Step.age,
        _Step.height,
        _Step.weight,
        _Step.activity,
        _Step.goal,
        if (_mode == 'lose' || _mode == 'gain') ...[_Step.target, _Step.pace],
        _Step.plan,
      ];

  _Step get _step => _steps[_index.clamp(0, _steps.length - 1)];

  // --- Numbers ---------------------------------------------------------------

  double? get _maintenance => maintenanceCalories(
        age: _age,
        heightCm: _heightCm,
        weightKg: _weightKg,
        male: _male ?? true,
        exerciseLevel: _activity ?? 0,
      );

  double get _floor => safeMinimumCalories(
        male: _male ?? true,
        resting: restingCalories(
          age: _age,
          heightCm: _heightCm,
          weightKg: _weightKg,
          male: _male ?? true,
        ),
      );

  int get _planCalories {
    if (_ownCalories) return _manualCalories ?? 0;
    final m = _maintenance;
    if (m == null || !m.isFinite || m <= 0) return 0;
    return paceCalories(m, _mode, _pace.kgPerWeek, floor: _floor);
  }

  ({int p, int c, int f}) get _planMacros {
    final set = _macros;
    if (set != null) return set;
    final m = defaultMacrosFor(_planCalories);
    return (p: m.protein.round(), c: m.carbs.round(), f: m.fat.round());
  }

  bool get _hasGoalWeight => _mode == 'lose' || _mode == 'gain';

  /// Why this goal weight can't be used, or null if it's fine.
  String? get _goalProblem {
    final g = _goalKg;
    final w = _weightKg;
    if (g == null || w == null) return null;
    if (!ProfileLimits.weightOk(g)) return Units.weightRangeMessage(_units);
    if (!goalWeightFits(_mode, w, g)) {
      return _mode == 'lose'
          ? 'Your goal needs to be below your weight now '
              '(${Units.formatWeight(w, _units)}).'
          : 'Your goal needs to be above your weight now '
              '(${Units.formatWeight(w, _units)}).';
    }
    final h = _heightCm;
    if (_mode == 'lose' && h != null && g < minHealthyKg(h)) {
      return "That's below a healthy weight for your height "
          '(${Units.formatWeight(minHealthyKg(h), _units)}). Try a goal at '
          'or above it.';
    }
    return null;
  }

  bool get _canContinue => switch (_step) {
        _Step.sex => _male != null,
        _Step.age => ProfileLimits.ageOk(_age),
        _Step.height => ProfileLimits.heightOk(_heightCm),
        _Step.weight => ProfileLimits.weightOk(_weightKg),
        _Step.activity => _activity != null,
        _Step.goal => _mode != null,
        _Step.target => _goalKg != null && _goalProblem == null,
        _Step.pace => true,
        _Step.plan => _planCalories >= 500 && _planCalories <= 10000,
      };

  // --- Navigation ------------------------------------------------------------

  void _next() {
    if (!_canContinue) return;
    if (_step == _Step.plan) {
      _finishSetup();
      return;
    }
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() {
      _goingBack = false;
      _index = (_index + 1).clamp(0, _steps.length - 1);
    });
  }

  void _back() {
    if (_index == 0) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _goingBack = true;
      _index--;
    });
  }

  /// Picking an option moves straight on (nothing else to do there).
  void _pickThenNext(VoidCallback pick) {
    if (_advancing) return;
    setState(pick);
    _advancing = true;
    Future.delayed(const Duration(milliseconds: 180), () {
      _advancing = false;
      if (mounted) _next();
    });
  }

  Future<void> _signOutAndLeave() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  }

  // --- Saving ----------------------------------------------------------------

  Future<void> saveData() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final calories = _planCalories;
    if (calories <= 0) throw StateError('No calorie goal set');
    final macros = _planMacros;

    // One profile per user. If a previous attempt got as far as creating
    // it, update that one instead of adding a duplicate (two profiles
    // would split the balance between them).
    final existing = await BalanceService.userDataDoc(userId);
    final profileRef = existing?.reference ??
        FirebaseFirestore.instance.collection('user_data').doc(userId);

    await profileRef.set({
      'user_id': userId,
      'age': _age,
      'gender': (_male ?? true) ? 'male' : 'female',
      'height': _heightCm,
      'weight': _weightKg,
      'exercise_level': _activity ?? 0,
      'calories': calories,
      'calorie_goal': calories,
      'balance_date': BalanceService.dateKey(DateTime.now()),
      'calorie_mode': _mode ?? 'lose',
      'goal_weight': _hasGoalWeight ? _goalKg : null,
      'goal_pace': _hasGoalWeight ? _pace.kgPerWeek : null,
      'goal_source': _ownCalories ? 'manual' : 'calculated',
      'protein_goal': macros.p,
      'carbs_goal': macros.c,
      'fats_goal': macros.f,
      'protein_balance': macros.p,
      'carbs_balance': macros.c,
      'fats_balance': macros.f,
      ..._units.toFields(),
    });

    // Starts the weight log, so the trend has a first point.
    final kg = _weightKg;
    if (kg != null && ProfileLimits.weightOk(kg)) {
      try {
        await WeightService.log(userId, kg);
      } catch (_) {
        // Not worth failing sign-up over; they can log it later.
      }
    }

    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'email': FirebaseAuth.instance.currentUser!.email,
      'friends': [],
    }, SetOptions(merge: true));
  }

  /// Opens the card reveal, which saves the card while it "prints".
  Future<void> _finishSetup() async {
    if (_finishing || !_canContinue) return;
    FocusScope.of(context).unfocus();
    setState(() => _finishing = true);
    final macros = _planMacros;
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final holder = cardholderFromEmail(email);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (revealContext) => CardRevealPage(
          save: saveData,
          calories: _planCalories,
          protein: macros.p,
          carbs: macros.c,
          fat: macros.f,
          holder: holder.isEmpty ? 'You' : holder,
          onDone: () {
            Analytics.track('card_created');
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
    if (mounted) setState(() => _finishing = false);
  }

  // --- Screens ---------------------------------------------------------------

  ({String title, String? subtitle}) get _heading => switch (_step) {
        _Step.sex => (
            title: 'Which best describes you?',
            subtitle: 'Bodies burn calories a little differently, so this '
                'helps us get your numbers right.'
          ),
        _Step.age => (title: 'How old are you?', subtitle: null),
        _Step.height => (title: 'How tall are you?', subtitle: null),
        _Step.weight => (
            title: 'What do you weigh now?',
            subtitle: 'Only you can see this.'
          ),
        _Step.activity => (
            title: 'How active are you?',
            subtitle: 'Think of a normal week, including exercise.'
          ),
        _Step.goal => (title: "What's your goal?", subtitle: null),
        _Step.target => (
            title: "What's your goal weight?",
            subtitle: _weightKg == null
                ? null
                : "You're ${Units.formatWeight(_weightKg!, _units)} now."
          ),
        _Step.pace => (
            title: 'How fast?',
            subtitle: 'You can change this any time in Profile.'
          ),
        _Step.plan => (
            title: 'Your plan',
            subtitle: 'This is your card each morning. Change anything '
                'later in Profile → Goals and profile.'
          ),
      };

  Widget _body() => switch (_step) {
        _Step.sex => Column(children: [
            ProfileChoice(
              icon: Icons.man,
              title: 'Male',
              selected: _male == true,
              onTap: () => _pickThenNext(() => _male = true),
            ),
            ProfileChoice(
              icon: Icons.woman,
              title: 'Female',
              selected: _male == false,
              onTap: () => _pickThenNext(() => _male = false),
            ),
          ]),
        _Step.age => MeasurementInputField(
            label: 'Age',
            controller: _ageController,
            hintText: 'E.g. 30',
            unit: 'years',
            autofocus: true,
            min: ProfileLimits.minAge.toDouble(),
            max: ProfileLimits.maxAge.toDouble(),
            rangeMessage: ProfileLimits.ageRangeMessage,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _next(),
            onChanged: (v) => setState(() => _age = v?.round()),
          ),
        _Step.height => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UnitsPicker(
                value: _units,
                onChanged: (u) => setState(() => _units = u),
              ),
              const SizedBox(height: 8),
              HeightInput(
                key: ValueKey('h${_units.unitsField}'),
                units: _units,
                valueCm: _heightCm,
                onChanged: (cm) => setState(() => _heightCm = cm),
              ),
            ],
          ),
        // Units here too, not only on the height step: plenty of people
        // weigh in kg but measure height in feet, or skipped past it.
        _Step.weight => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UnitsPicker(
                value: _units,
                onChanged: (u) => setState(() => _units = u),
              ),
              const SizedBox(height: 8),
              WeightInput(
                key: ValueKey('w${_units.weightField}'),
                units: _units,
                valueKg: _weightKg,
                autofocus: true,
                onSubmitted: (_) => _next(),
                onChanged: (kg) => setState(() => _weightKg = kg),
              ),
            ],
          ),
        _Step.activity => Column(children: [
            for (var i = 0; i < activityLevels.length; i++)
              ProfileChoice(
                title: activityLevels[i].title,
                subtitle: activityLevels[i].subtitle,
                selected: _activity?.round() == i,
                onTap: () => _pickThenNext(() => _activity = i.toDouble()),
              ),
          ]),
        _Step.goal => GoalModeChoices(
            mode: _mode,
            onChanged: (m) => _pickThenNext(() {
              if (m != _mode) _goalKg = null;
              _mode = m;
              _pace = GoalPace.from(_pace.kgPerWeek, mode: m);
            }),
          ),
        _Step.target => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UnitsPicker(
                value: _units,
                onChanged: (u) => setState(() => _units = u),
              ),
              const SizedBox(height: 8),
              WeightInput(
                key: ValueKey('g${_units.weightField}'),
                label: 'Goal weight',
                units: _units,
                valueKg: _goalKg,
                autofocus: true,
                onSubmitted: (_) => _next(),
                onChanged: (kg) => setState(() => _goalKg = kg),
              ),
              if (_goalProblem != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: Text(
                    _goalProblem!,
                    style: TextStyle(fontSize: 13, color: AppText.amber700),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _goalKg = null;
                    _goingBack = false;
                    _index++;
                  }),
                  child: const Text("I don't have a goal weight"),
                ),
              ),
            ],
          ),
        _Step.pace => PaceChoices(
            mode: _mode,
            value: _pace,
            units: _units,
            maintenance: _maintenance ?? 0,
            floor: _floor,
            fromKg: _weightKg,
            goalKg: _goalKg,
            onChanged: (p) => setState(() => _pace = p),
          ),
        _Step.plan => _planBody(),
      };

  Widget _planBody() {
    final kcal = _planCalories;
    final m = _planMacros;
    final maintenance = _maintenance;
    String? goalLine;
    if (!_ownCalories && maintenance != null) {
      if (_mode == 'maintain') {
        goalLine = 'About what your body burns each day';
      } else {
        final o = paceOutcome(
          pace: _pace,
          mode: _mode,
          maintenance: maintenance,
          floor: _floor,
          fromKg: _weightKg,
          goalKg: _goalKg,
        );
        final verb = _mode == 'gain' ? 'Gain' : 'Lose';
        goalLine = [
          '$verb ${paceRate(_pace, _units)}',
          if (_goalKg != null && o.date != null)
            'reach ${Units.formatWeight(_goalKg!, _units)} by '
                '${formatGoalDate(o.date!)}',
        ].join(' · ');
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text(
                '$calSym${formatCardKcal(kcal)}',
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              Text(
                'to spend each day',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
              ),
              if (goalLine != null) ...[
                const SizedBox(height: 10),
                Text(
                  goalLine,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Protein ${m.p}g · Carbs ${m.c}g · Fat ${m.f}g',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _editingMacros = !_editingMacros),
              child: Text(_editingMacros ? 'Done' : 'Change'),
            ),
          ],
        ),
        if (_editingMacros)
          MacroEditor(
            key: ValueKey('macros$kcal'),
            calories: kcal,
            protein: m.p,
            carbs: m.c,
            fat: m.f,
            onChanged: (p, c, f) => setState(() => _macros = (p: p, c: c, f: f)),
          ),
        const SizedBox(height: 8),
        if (!_ownCalories)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _ownCalories = true;
                _manualCalories ??= kcal > 0 ? kcal : null;
                _caloriesController.text = '${_manualCalories ?? ''}';
              }),
              icon: const Icon(Icons.edit_note),
              label: const Text('Set my own calories instead'),
            ),
          )
        else ...[
          const SizedBox(height: 8),
          TextField(
            controller: _caloriesController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(5),
            ],
            decoration: InputDecoration(
              labelText: 'Calories a day',
              suffixText: 'kcal',
              helperText: 'For example from a coach or dietitian.',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (v) => setState(() {
              _manualCalories = int.tryParse(v);
              _macros = null; // re-split for the new number
            }),
          ),
          LowCalorieNote(calories: _manualCalories),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                _ownCalories = false;
                _macros = null;
              }),
              child: const Text('Use the calculated number'),
            ),
          ),
        ],
      ],
    );
  }

  // --- Layout ----------------------------------------------------------------

  Widget _header() {
    final steps = _steps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 14),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                child: _index > 0
                    ? IconButton(
                        tooltip: 'Back',
                        onPressed: _back,
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white),
                      )
                    : null,
              ),
              const Expanded(
                child: Text(
                  'Set up your card',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: TextButton(
                  onPressed: _signOutAndLeave,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: const Text('Sign out'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: 'Step ${_index + 1} of ${steps.length}',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: (_index + 1) / steps.length),
                    duration: MediaQuery.of(context).disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page() {
    final h = _heading;
    return SingleChildScrollView(
      key: ValueKey(_step),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                h.title,
                style: TextStyle(
                  fontSize: 26,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (h.subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  h.subtitle!,
                  style: TextStyle(fontSize: 15, color: AppColors.muted),
                ),
              ],
              const SizedBox(height: 22),
              _body(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final plan = _step == _Step.plan;
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: still
                                ? Duration.zero
                                : const Duration(milliseconds: 240),
                            transitionBuilder: (child, anim) {
                              final incoming =
                                  child.key == ValueKey(_step);
                              final from = Offset(
                                  (_goingBack ? -1 : 1) *
                                      (incoming ? 0.15 : -0.15),
                                  0);
                              return FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween(
                                          begin: from, end: Offset.zero)
                                      .animate(anim),
                                  child: child,
                                ),
                              );
                            },
                            child: _page(),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                            child: Center(
                              heightFactor: 1,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 520),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: FilledButton(
                                    onPressed: _canContinue && !_finishing
                                        ? _next
                                        : null,
                                    child: _finishing
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (plan) ...[
                                                const Icon(
                                                    Icons.credit_card_rounded,
                                                    size: 20),
                                                const SizedBox(width: 8),
                                              ],
                                              Text(
                                                plan
                                                    ? 'Print my card'
                                                    : 'Continue',
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
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
          ),
        ),
      ),
    );
  }
}
