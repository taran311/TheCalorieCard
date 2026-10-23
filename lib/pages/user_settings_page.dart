import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/components/measurement_input_field.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/card_design_service.dart';
import 'package:namer_app/services/food_country.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/goal_maths.dart';
import 'package:namer_app/services/profile_limits.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/services/units.dart';
import 'package:namer_app/services/weight_service.dart';
import 'package:namer_app/ui/body_inputs.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/profile_editors.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';
import 'package:namer_app/ui/calorie_symbol.dart';

// The calorie sums used to live here; other screens still import them
// from this file.
export 'package:namer_app/services/goal_maths.dart'
    show maintenanceCalories, suggestedCalorieGoal, defaultMacrosFor;

/// A message that is safe to show as-is when working out targets fails.
class _EstimateError implements Exception {
  final String message;
  const _EstimateError(this.message);

  @override
  String toString() => message;
}

/// Goals and profile: a summary of your plan and details. Tap a row to
/// change just that one thing; Save stores it all. (Sign-up asks the same
/// questions one screen at a time instead.)
class UserSettingsPage extends StatefulWidget {
  UserSettingsPage({super.key});

  @override
  State<UserSettingsPage> createState() => _UserSettingsPageState();
}

class _UserSettingsPageState extends State<UserSettingsPage> {
  CardDesign _cardDesign = CardDesign.midnight;
  bool _loading = true;
  bool _saving = false;

  // About you (always cm and kg; [_units] only changes what's shown)
  bool _male = true;
  int? _age;
  double? _heightCm;
  double? _weightKg;
  double _activity = 0;
  UnitPrefs _units = UnitPrefs.forCountry(
      WidgetsBinding.instance.platformDispatcher.locale.countryCode);

  /// The weight when the page opened, so Save knows whether to add a
  /// weigh-in to the weight log.
  double? _loadedWeight;

  // Your plan
  String _mode = 'lose';
  double? _goalKg;
  GoalPace _pace = GoalPace.steady;

  /// Calories typed in (or from Coach) rather than worked out.
  bool _ownCalories = false;
  bool _fromCoach = false;

  /// The daily calorie goal Save will store.
  int _goal = 0;
  int? _protein;
  int? _carbs;
  int? _fat;

  /// Keeps the macro split when the calorie goal changes.
  final _scaler = MacroScaler();

  bool _askingCoach = false;

  /// Everything Save would store, as it was when loaded or last saved.
  String? _savedSnapshot;

  @override
  void initState() {
    super.initState();
    ProxyClient.warmUp();
    FoodCountry.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      CardDesignService.watch(uid).first.then((d) {
        if (mounted) setState(() => _cardDesign = d);
      }, onError: (_) {});
    }
    _load();
  }

  // --- Loading and saving ----------------------------------------------------

  Future<void> _load() async {
    try {
      final doc = await BalanceService.userDataDoc(
          FirebaseAuth.instance.currentUser!.uid);
      final d = doc?.data();
      if (!mounted) return;
      if (d != null) {
        setState(() {
          _units = UnitPrefs.fromProfile(d,
              countryCode: WidgetsBinding
                  .instance.platformDispatcher.locale.countryCode);
          _age = asInt(d['age']);
          _heightCm = asDouble(d['height']);
          _weightKg = asDouble(d['weight']);
          _loadedWeight = _weightKg;
          _activity = (d['exercise_level'] as num?)?.toDouble() ?? 0;
          _male = d['gender'] != 'female';
          final mode = d['calorie_mode'];
          // Missing, 'deficit' (older accounts) or unrecognised: lose.
          _mode = mode == 'maintain' || mode == 'gain' ? mode : 'lose';
          _goalKg = asDouble(d['goal_weight']);
          _pace = GoalPace.from(d['goal_pace'], mode: _mode);
          _ownCalories = d['goal_source'] == 'manual';
          // Show what's saved, not a fresh estimate: opening this page and
          // pressing Save must not change your goals.
          _goal = BalanceService.calorieGoalFrom(d)?.round() ?? 0;
          if (_goal <= 0 && !_ownCalories) _goal = _calculatedGoal ?? 0;
          _protein = asInt(d['protein_goal']);
          _carbs = asInt(d['carbs_goal']);
          _fat = asInt(d['fats_goal']);
          if (_protein == null || _carbs == null || _fat == null) {
            final m = defaultMacrosFor(_goal);
            _protein = m.protein.round();
            _carbs = m.carbs.round();
            _fat = m.fat.round();
          }
          _savedSnapshot = _snapshot;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't load your details. Check your "
                'connection and try again.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _snapshot => [
        _male,
        _age,
        _heightCm,
        _weightKg,
        _activity,
        _units.unitsField,
        _units.weightField,
        _mode,
        _goalKg,
        _pace.kgPerWeek,
        _ownCalories,
        _goal,
        _protein,
        _carbs,
        _fat,
      ].join('|');

  bool get _dirty => _savedSnapshot != null && _snapshot != _savedSnapshot;

  bool get _hasGoalWeight => _mode == 'lose' || _mode == 'gain';

  /// Why the goal weight can't be used, or null if it's fine (or unset).
  String? get _goalProblem {
    final g = _goalKg;
    final w = _weightKg;
    if (!_hasGoalWeight || g == null || w == null) return null;
    if (!ProfileLimits.weightOk(g)) return Units.weightRangeMessage(_units);
    if (!goalWeightFits(_mode, w, g)) {
      return _mode == 'lose'
          ? 'Your goal weight needs to be below your weight now.'
          : 'Your goal weight needs to be above your weight now.';
    }
    final h = _heightCm;
    if (_mode == 'lose' && h != null && g < minHealthyKg(h)) {
      return "That's below a healthy weight for your height "
          '(${Units.formatWeight(minHealthyKg(h), _units)}).';
    }
    return null;
  }

  Future<String?> _save() async {
    if (_goal < 500 || _goal > 10000) {
      return 'Set a daily calorie goal between 500 and 10,000 first.';
    }
    if ((_protein ?? -1) < 0 || (_carbs ?? -1) < 0 || (_fat ?? -1) < 0) {
      return 'Fill in protein, carbs and fat (0 is fine).';
    }
    if (_age != null && !ProfileLimits.ageOk(_age)) {
      return ProfileLimits.ageRangeMessage;
    }
    if (_heightCm != null && !ProfileLimits.heightOk(_heightCm)) {
      return Units.heightRangeMessage(_units);
    }
    if (_weightKg != null && !ProfileLimits.weightOk(_weightKg)) {
      return Units.weightRangeMessage(_units);
    }
    final problem = _goalProblem;
    if (problem != null) return problem;
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      await BalanceService.applyGoals(
        userId,
        goals: Macros(
          calories: _goal.toDouble(),
          protein: _protein!.toDouble(),
          carbs: _carbs!.toDouble(),
          fat: _fat!.toDouble(),
        ),
        extra: {
          'age': _age,
          'height': _heightCm,
          'weight': _weightKg,
          'exercise_level': _activity,
          'gender': _male ? 'male' : 'female',
          'calorie_mode': _mode,
          'goal_weight': _hasGoalWeight ? _goalKg : null,
          'goal_pace': _hasGoalWeight ? _pace.kgPerWeek : null,
          // Reopening this page knows whether to keep working it out.
          'goal_source': _ownCalories ? 'manual' : 'calculated',
          ..._units.toFields(),
        },
      );
      // A new weight here is a weigh-in too, so the weight log keeps up.
      final kg = _weightKg;
      if (kg != null && kg != _loadedWeight && ProfileLimits.weightOk(kg)) {
        unawaited(WeightService.log(userId, kg).catchError((_) {}));
      }
      FoodLog.notifyChanged();
      return null;
    } catch (_) {
      return "Couldn't save your changes. Check your connection and try again.";
    }
  }

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    final error = await _save();
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.red700),
      );
      return;
    }
    _savedSnapshot = _snapshot;
    _loadedWeight = _weightKg;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Goals saved. Your card is up to date.')),
    );
  }

  Future<void> _confirmLeave() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text("You've changed your goals or details but "
            "haven't saved them."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  // --- Numbers ---------------------------------------------------------------

  double? get _maintenance => maintenanceCalories(
        age: _age,
        heightCm: _heightCm,
        weightKg: _weightKg,
        male: _male,
        exerciseLevel: _activity,
      );

  double get _floor => safeMinimumCalories(
        male: _male,
        resting: restingCalories(
          age: _age,
          heightCm: _heightCm,
          weightKg: _weightKg,
          male: _male,
        ),
      );

  /// The goal worked out from your details, goal and pace.
  int? get _calculatedGoal {
    final m = _maintenance;
    if (m == null || !m.isFinite || m <= 0) return null;
    return paceCalories(m, _mode, _pace.kgPerWeek, floor: _floor);
  }

  /// Sets a new calorie goal, keeping the macro split.
  void _setGoal(int kcal) {
    if (kcal <= 0) return;
    final m = _scaler.scale(_protein ?? 0, _carbs ?? 0, _fat ?? 0, kcal);
    _goal = kcal;
    _protein = m.protein.round();
    _carbs = m.carbs.round();
    _fat = m.fat.round();
  }

  /// After any change to your details or goal: work the goal out again
  /// (unless you've set your own number).
  void _recalculate() {
    if (_ownCalories) return;
    final g = _calculatedGoal;
    if (g != null) _setGoal(g);
  }

  DateTime? get _goalDate {
    final m = _maintenance;
    final w = _weightKg;
    final g = _goalKg;
    if (!_hasGoalWeight || m == null || w == null || g == null) return null;
    if (_goalProblem != null) return null;
    // Your own number has to move you the right way for a date to mean
    // anything.
    if (_mode == 'lose' ? _goal >= m : _goal <= m) return null;
    return goalReachedBy(
      fromKg: w,
      goalKg: g,
      kgPerWeek: kgPerWeekAt(m, _goal),
      start: DateTime.now(),
    );
  }

  /// Asks Coach for calories and macros for your goal; they become your
  /// own numbers ("from Coach").
  Future<void> _askCoach(void Function() refresh) async {
    if (_age == null || _heightCm == null || _weightKg == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fill in your age, height and weight first.')));
      return;
    }
    setState(() => _askingCoach = true);
    refresh();
    try {
      for (var attempt = 1; attempt <= 2; attempt++) {
        final response = await ProxyClient.post('/macro-targets', {
          'age': _age,
          'gender': _male ? 'male' : 'female',
          'height_cm': _heightCm,
          'weight_kg': _weightKg,
          'exercise_level': activityServerText(_activity),
        }).timeout(const Duration(seconds: 30),
            onTimeout: () => throw const _EstimateError(
                'That timed out. Please try again in a moment.'));
        if (response.statusCode == 503 && attempt < 2) {
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }
        if (response.statusCode != 200) {
          throw const _EstimateError(
              "Coach couldn't work out your numbers just now. Please try "
              'again.');
        }
        final data = json.decode(response.body);
        final raw =
            data['ai']?['final']?['targets'] ?? data['baseline']?['targets'];
        if (raw is! Map) {
          throw const _EstimateError(
              "Coach couldn't work out your numbers just now. Please try "
              'again.');
        }
        // "Lose" never below the safe minimum, whatever Coach says.
        final targets =
            withSafeLoseTarget(Map<String, dynamic>.from(raw), _floor);
        final t = targets[_mode];
        final kcal = asInt(t is Map ? t['calories'] : null);
        if (kcal == null || kcal <= 0) {
          throw const _EstimateError(
              "Coach couldn't work out your numbers just now. Please try "
              'again.');
        }
        if (!mounted) return;
        setState(() {
          _ownCalories = true;
          _fromCoach = true;
          _goal = kcal;
          _protein = asInt(t['protein_g']) ?? _protein;
          _carbs = asInt(t['carbs_g']) ?? _carbs;
          _fat = asInt(t['fat_g']) ?? _fat;
        });
        break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is _EstimateError
              ? e.message
              : "Couldn't reach Coach. Check your connection and try again."),
          backgroundColor: AppColors.red700,
        ));
      }
    } finally {
      if (mounted) setState(() => _askingCoach = false);
      refresh();
    }
  }

  // --- Editing sheets --------------------------------------------------------

  /// Opens an editor for one thing. Changes apply as you make them; Save
  /// (on the page) stores them.
  Future<void> _edit(String title,
      Widget Function(void Function(VoidCallback) update) body) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          void update(VoidCallback f) {
            // Closed meanwhile (Coach can answer after): nothing to show.
            if (!sheetContext.mounted) return;
            setState(f);
            setSheet(() {});
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 0, 20, 16 + MediaQuery.viewInsetsOf(sheetContext).bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 16),
                    body(update),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _editSex() => _edit('Sex', (update) => Column(children: [
        ProfileChoice(
          icon: Icons.man,
          title: 'Male',
          selected: _male,
          onTap: () => update(() {
            _male = true;
            _recalculate();
          }),
        ),
        ProfileChoice(
          icon: Icons.woman,
          title: 'Female',
          selected: !_male,
          onTap: () => update(() {
            _male = false;
            _recalculate();
          }),
        ),
      ]));

  void _editAge() {
    final controller = TextEditingController(text: _age?.toString() ?? '');
    _edit(
      'Age',
      (update) => MeasurementInputField(
        label: 'Age',
        controller: controller,
        hintText: 'E.g. 30',
        unit: 'years',
        autofocus: true,
        min: ProfileLimits.minAge.toDouble(),
        max: ProfileLimits.maxAge.toDouble(),
        rangeMessage: ProfileLimits.ageRangeMessage,
        onChanged: (v) => update(() {
          _age = v?.round();
          if (ProfileLimits.ageOk(_age)) _recalculate();
        }),
      ),
    ).whenComplete(controller.dispose);
  }

  void _editHeight() => _edit(
        'Height',
        (update) => HeightInput(
          key: ValueKey('h${_units.unitsField}'),
          units: _units,
          valueCm: _heightCm,
          onChanged: (cm) => update(() {
            _heightCm = cm;
            if (ProfileLimits.heightOk(cm)) _recalculate();
          }),
        ),
      );

  void _editWeight() => _edit(
        'Weight now',
        (update) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WeightInput(
              key: ValueKey('w${_units.weightField}'),
              units: _units,
              valueKg: _weightKg,
              autofocus: true,
              onChanged: (kg) => update(() {
                _weightKg = kg;
                if (ProfileLimits.weightOk(kg)) _recalculate();
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(
                'Saving adds this to your weight log too.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ),
          ],
        ),
      );

  void _editActivity() => _edit(
        'How active are you?',
        (update) => Column(children: [
          for (var i = 0; i < activityLevels.length; i++)
            ProfileChoice(
              title: activityLevels[i].title,
              subtitle: activityLevels[i].subtitle,
              selected: _activity.round() == i,
              onTap: () => update(() {
                _activity = i.toDouble();
                _recalculate();
              }),
            ),
        ]),
      );

  void _editUnits() => _edit(
        'Units',
        (update) => UnitsPicker(
          value: _units,
          onChanged: (u) => update(() => _units = u),
        ),
      );

  void _editGoal() => _edit(
        'Your goal',
        (update) {
          final m = _maintenance;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GoalModeChoices(
                mode: _mode,
                onChanged: (mode) => update(() {
                  if (mode != _mode) _goalKg = null;
                  _mode = mode;
                  _pace = GoalPace.from(_pace.kgPerWeek, mode: mode);
                  _recalculate();
                }),
              ),
              if (_hasGoalWeight) ...[
                const SizedBox(height: 8),
                WeightInput(
                  key: ValueKey('g$_mode${_units.weightField}'),
                  label: 'Goal weight (optional)',
                  units: _units,
                  valueKg: _goalKg,
                  onChanged: (kg) => update(() => _goalKg = kg),
                ),
                if (_goalProblem != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: Text(_goalProblem!,
                        style:
                            TextStyle(fontSize: 13, color: AppText.amber700)),
                  ),
                const SizedBox(height: 16),
                Text(
                  'How fast?',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.ink),
                ),
                const SizedBox(height: 10),
                if (m == null)
                  Text('Add your age, height and weight to see your options.',
                      style: TextStyle(color: AppColors.muted))
                else
                  PaceChoices(
                    mode: _mode,
                    value: _pace,
                    units: _units,
                    maintenance: m,
                    floor: _floor,
                    fromKg: _weightKg,
                    goalKg: _goalProblem == null ? _goalKg : null,
                    onChanged: (p) => update(() {
                      _pace = p;
                      _recalculate();
                    }),
                  ),
              ],
              if (_ownCalories)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    "You've set your own calories, so they stay at "
                    '$calSym${formatCardKcal(_goal)}. Switch back in Daily '
                    'calories to use your goal.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ),
            ],
          );
        },
      );

  void _editCalories() {
    final controller = TextEditingController(text: '$_goal');
    _edit('Daily calories', (update) {
      final calculated = _calculatedGoal;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileChoice(
            title: 'Work it out from my goal',
            subtitle: calculated == null
                ? 'Add your age, height and weight first'
                : '$calSym${formatCardKcal(calculated)} a day',
            selected: !_ownCalories,
            onTap: calculated == null
                ? () {}
                : () => update(() {
                      _ownCalories = false;
                      _fromCoach = false;
                      _setGoal(calculated);
                      controller.text = '$_goal';
                    }),
          ),
          ProfileChoice(
            title: 'Set my own number',
            subtitle: _fromCoach
                ? 'From Coach'
                : 'For example from a coach or dietitian',
            selected: _ownCalories,
            onTap: () => update(() => _ownCalories = true),
          ),
          if (_ownCalories) ...[
            const SizedBox(height: 4),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              decoration: InputDecoration(
                labelText: 'Calories a day',
                suffixText: 'kcal',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => update(() {
                _fromCoach = false;
                final n = int.tryParse(v);
                if (n != null) _setGoal(n);
              }),
            ),
            LowCalorieNote(calories: _goal),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _askingCoach
                ? null
                : () => _askCoach(() => update(() => controller.text = '$_goal')),
            icon: _askingCoach
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome, size: 20),
            label: Text(_askingCoach
                ? 'Coach is working it out…'
                : 'Fine-tune with Coach'),
          ),
          const SizedBox(height: 4),
          Text(
            'Optional. Coach suggests calories and macros from your details.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      );
    }).whenComplete(controller.dispose);
  }

  void _editMacros() => _edit(
        'Macros',
        (update) => MacroEditor(
          calories: _goal,
          protein: _protein,
          carbs: _carbs,
          fat: _fat,
          onChanged: (p, c, f) => update(() {
            _protein = p;
            _carbs = c;
            _fat = f;
          }),
        ),
      );

  // --- Page ------------------------------------------------------------------

  Widget _row(String title, String value, VoidCallback onTap,
      {String? note}) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(fontSize: 13, color: AppColors.muted)),
                    const SizedBox(height: 2),
                    Text(value,
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    if (note != null)
                      Text(note,
                          style: TextStyle(
                              fontSize: 12.5, color: AppText.primaryDark)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _group(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.gray700)),
        ),
        Container(
          decoration: AppDecor.card,
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: AppColors.border),
                  rows[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String get _goalValue {
    final g = _goalKg;
    if (!_hasGoalWeight || g == null) return goalModeTitle(_mode);
    return '${goalModeTitle(_mode)} · to ${Units.formatWeight(g, _units)}';
  }

  String? get _goalNote {
    if (!_hasGoalWeight) return null;
    final parts = <String>[
      if (!_ownCalories) paceRate(_pace, _units),
      if (_goalDate != null) 'by ${formatGoalDate(_goalDate!)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _foodCountryRow() => _row(
        'Food country',
        FoodCountry.nameOf(FoodCountry.code),
        _pickFoodCountry,
        note: FoodCountry.chosen ? null : "From this device's region",
      );

  Future<void> _pickFoodCountry() async {
    final device = FoodCountry.deviceCountry;
    final entries = FoodCountry.countries.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    // '' = back to the device's region.
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.phone_iphone),
                title: Text("This device's region "
                    '(${FoodCountry.nameOf(device)})'),
                selected: !FoodCountry.chosen,
                onTap: () => Navigator.pop(context, ''),
              ),
              const Divider(height: 1),
              for (final e in entries)
                ListTile(
                  title: Text(e.value),
                  selected: FoodCountry.chosen && FoodCountry.code == e.key,
                  onTap: () => Navigator.pop(context, e.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Saved straight away: it's not part of the goal.
      await FoodCountry.choose(picked.isEmpty ? null : picked);
      if (mounted) setState(() {});
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't save that. Please try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('Goals and profile')),
        bottomNavigationBar: _loading
            ? null
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxWidth: Breakpoints.contentMaxWidth),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton(
                            onPressed: dirty || _saving ? _onSave : null,
                            child: _saving
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
                                : Text(
                                    dirty ? 'Save changes' : 'No changes',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: Breakpoints.contentMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: CreditCard(
                            design: _cardDesign,
                            key: ValueKey('$_goal|$_protein|$_carbs|$_fat'),
                            initialCalories: _goal,
                            caloriesOverride: _goal,
                            proteinOverride: (_protein ?? 0).toDouble(),
                            carbsOverride: (_carbs ?? 0).toDouble(),
                            fatsOverride: (_fat ?? 0).toDouble(),
                            skipFetch: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your card each morning',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.muted),
                        ),
                        const SizedBox(height: 20),
                        _group('Your plan', [
                          _row('Goal', _goalValue, _editGoal, note: _goalNote),
                          _row(
                            'Daily calories',
                            '$calSym${formatCardKcal(_goal)}',
                            _editCalories,
                            note: _ownCalories
                                ? (_fromCoach ? 'From Coach' : 'Your own number')
                                : 'Worked out from your goal',
                          ),
                          _row(
                            'Macros',
                            'Protein ${_protein ?? 0}g · Carbs ${_carbs ?? 0}g · '
                                'Fat ${_fat ?? 0}g',
                            _editMacros,
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _group('About you', [
                          _row('Sex', _male ? 'Male' : 'Female', _editSex),
                          _row('Age', _age == null ? 'Add' : '$_age', _editAge),
                          _row(
                            'Height',
                            _heightCm == null
                                ? 'Add'
                                : Units.formatHeight(_heightCm!, _units),
                            _editHeight,
                          ),
                          _row(
                            'Weight now',
                            _weightKg == null
                                ? 'Add'
                                : Units.formatWeight(_weightKg!, _units),
                            _editWeight,
                          ),
                          _row('Activity', activityTitle(_activity),
                              _editActivity),
                          _row(
                            'Units',
                            _units.isMetric
                                ? 'Kilograms and centimetres'
                                : _units.weight == WeightUnit.stLb
                                    ? 'Stones and feet'
                                    : 'Pounds and feet',
                            _editUnits,
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _group('Food', [_foodCountryRow()]),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
