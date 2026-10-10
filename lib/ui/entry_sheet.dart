import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/ui/home_widgets.dart';
import 'package:namer_app/ui/responsive.dart';

/// What the person chose in the food sheet.
enum EntrySheetAction {
  /// Portion, calories or meal were changed and saved.
  saved,

  /// Delete was tapped (the caller removes it, so it can refresh).
  delete,

  /// Logged again to today ([EntrySheetResult.logged] says what).
  loggedAgain,

  /// "Make it a direct debit" was tapped (the caller runs that flow).
  directDebit,
}

class EntrySheetResult {
  final EntrySheetAction action;

  /// For [EntrySheetAction.loggedAgain]: what was logged, for Undo.
  final LoggedFoods? logged;

  const EntrySheetResult(this.action, {this.logged});
}

/// Opens one of your logged foods: see it, change the portion, fix the
/// calories, move it to another meal, delete it, log it again or make it a
/// direct debit. [canEdit] is false on past or closed days (view only).
Future<EntrySheetResult?> showEntrySheet(
  BuildContext context, {
  required String entryId,
  required Map<String, dynamic> entry,
  required bool canEdit,
  bool canDirectDebit = true,
  List<Map<String, dynamic>> reactions = const [],
  String? logAgainMeal,
}) {
  return showModalBottomSheet<EntrySheetResult>(
    context: context,
    // Above the bottom bar, so the Coach button never covers Save.
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _EntrySheet(
      entryId: entryId,
      entry: entry,
      canEdit: canEdit,
      canDirectDebit: canDirectDebit,
      reactions: reactions,
      logAgainMeal: logAgainMeal,
    ),
  );
}

class _EntrySheet extends StatefulWidget {
  final String entryId;
  final Map<String, dynamic> entry;
  final bool canEdit;
  final bool canDirectDebit;
  final List<Map<String, dynamic>> reactions;
  final String? logAgainMeal;

  const _EntrySheet({
    required this.entryId,
    required this.entry,
    required this.canEdit,
    required this.canDirectDebit,
    required this.reactions,
    required this.logAgainMeal,
  });

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  static const _portions = [0.5, 1.0, 1.5, 2.0, 3.0];

  late final Macros _base = FoodLog.baseOf(widget.entry);
  late final double _startMultiplier = FoodLog.multiplierOf(widget.entry);
  late final String _startMeal = FoodLog.mealOf(widget.entry['foodCategory']);

  late double _multiplier = _startMultiplier;
  late String _meal = _startMeal;
  final _customController = TextEditingController();
  final _caloriesController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _customController.dispose();
    _caloriesController.dispose();
    super.dispose();
  }

  String get _name =>
      (widget.entry['food_description'] ?? 'Food').toString();

  bool get _isEstimate => widget.entry['food_estimate'] == true;

  /// The calories typed in "Fix calories" (null if empty or not valid).
  double? get _fixedCalories {
    final text = _caloriesController.text.trim();
    if (text.isEmpty) return null;
    final v = double.tryParse(text);
    return v != null && v.isFinite && v >= 0 ? v : null;
  }

  bool get _caloriesInvalid =>
      _caloriesController.text.trim().isNotEmpty && _fixedCalories == null;

  bool get _customInvalid {
    final text = _customController.text.trim();
    if (text.isEmpty) return false;
    final v = double.tryParse(text);
    return v == null || !v.isFinite || v <= 0;
  }

  bool _same(double a, double b) => (a - b).abs() < 0.0001;

  /// What the food will be once saved, for the preview.
  Macros get _preview {
    // Unchanged portion: show it as it is now (keeps an earlier fix).
    final scaled = _same(_multiplier, _startMultiplier)
        ? Macros.fromEntry(widget.entry)
        : _base.scaled(_multiplier);
    final fixed = _fixedCalories;
    return fixed == null
        ? scaled
        : Macros(
            calories: fixed,
            protein: scaled.protein,
            carbs: scaled.carbs,
            fat: scaled.fat,
          );
  }

  bool get _changed =>
      !_same(_multiplier, _startMultiplier) ||
      _fixedCalories != null ||
      _meal != _startMeal;

  void _pickPortion(double m) {
    setState(() {
      _multiplier = m;
      _customController.clear();
    });
  }

  void _onCustomChanged(String text) {
    final v = double.tryParse(text.trim());
    setState(() {
      if (v != null && v.isFinite && v > 0) _multiplier = v;
    });
  }

  Future<void> _save() async {
    if (_busy || !_changed || _caloriesInvalid || _customInvalid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FoodLog.updateEntry(
        widget.entryId,
        entry: widget.entry,
        multiplier:
            _same(_multiplier, _startMultiplier) ? null : _multiplier,
        calories: _fixedCalories,
        meal: _meal != _startMeal ? _meal : null,
      );
      if (mounted) {
        Navigator.pop(context, const EntrySheetResult(EntrySheetAction.saved));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't save that. Please try again.";
        });
      }
    }
  }

  Future<void> _logAgain() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final now = Macros.fromEntry(widget.entry);
    try {
      final logged = await FoodLog.logFoods(
        items: [
          {
            'name': _name,
            'portion': (widget.entry['food_portion'] ?? '').toString(),
            'calories': now.calories,
            'protein': now.protein,
            'carbs': now.carbs,
            'fat': now.fat,
            'source': 'recent',
            // Still an estimate if it was one.
            if (_isEstimate) 'needs_review': true,
          }
        ],
        meal: widget.logAgainMeal ?? _meal,
      );
      if (mounted) {
        Navigator.pop(
          context,
          EntrySheetResult(EntrySheetAction.loggedAgain, logged: logged),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't log that. Please try again.";
        });
      }
    }
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.ink,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final portion = (widget.entry['food_portion'] ?? '').toString();
    final preview = _preview;
    final canEdit = widget.canEdit;
    final logMeal = widget.logAgainMeal ?? _meal;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            if (portion.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(portion, style: TextStyle(color: AppColors.muted)),
            ],
            if (_isEstimate) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.amber50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.amber200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 18, color: AppText.amber700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Estimate: AI guessed these numbers. If you know '
                        'the real calories, fix them below.',
                        style: TextStyle(fontSize: 13, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            // What it costs (as it will be once saved).
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.indigo50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${preview.calories.round()}',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppText.primaryDark,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'kcal',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppText.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: MacroText(
                        protein: preview.protein,
                        carbs: preview.carbs,
                        fat: preview.fat,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (canEdit) ...[
              const SizedBox(height: 18),
              _sectionLabel('Portion'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final m in _portions)
                    ChoiceChip(
                      label: Text('×${FoodLog.formatAmount(m)}'),
                      selected: _customController.text.trim().isEmpty &&
                          _same(_multiplier, m),
                      showCheckmark: false,
                      onSelected: _busy ? null : (_) => _pickPortion(m),
                    ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _customController,
                      enabled: !_busy,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: _onCustomChanged,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Other',
                        prefixText: '×',
                        errorText: _customInvalid ? 'Above 0' : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '×1 is the amount you first logged.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              _sectionLabel('Fix calories'),
              TextField(
                controller: _caloriesController,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'e.g. ${preview.calories.round()}',
                  suffixText: 'kcal',
                  helperText: 'Only if you know the real number. '
                      'Protein, carbs and fat stay as they are.',
                  errorText:
                      _caloriesInvalid ? 'Enter a whole number of kcal' : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              _sectionLabel('Meal'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in FoodLog.meals)
                    ChoiceChip(
                      label: Text(m),
                      selected: _meal == m,
                      showCheckmark: false,
                      onSelected: _busy ? null : (_) => setState(() => _meal = m),
                    ),
                ],
              ),
            ],
            if (widget.reactions.isNotEmpty) ...[
              const SizedBox(height: 18),
              _sectionLabel('Reactions'),
              for (final r in widget.reactions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          (r['username'] ?? 'Someone').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.gray700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        (r['emoji'] ?? '').toString(),
                        style: const TextStyle(fontSize: 20),
                      ),
                    ],
                  ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppText.red600)),
            ],
            if (canEdit) ...[
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ||
                          !_changed ||
                          _caloriesInvalid ||
                          _customInvalid
                      ? null
                      : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (canEdit)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _logAgain,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text('Log again to $logMeal'),
                  ),
                if (widget.canDirectDebit)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(
                              context,
                              const EntrySheetResult(
                                  EntrySheetAction.directDebit),
                            ),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.autorenew),
                    label: const Text('Make it a direct debit'),
                  ),
                if (canEdit)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(
                              context,
                              const EntrySheetResult(EntrySheetAction.delete),
                            ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppText.red600,
                      minimumSize: const Size(0, 44),
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
