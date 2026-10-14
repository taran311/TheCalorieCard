import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/food_resolver.dart';
import 'package:namer_app/services/portion_amount.dart';
import 'package:namer_app/ui/amount_field.dart';
import 'package:namer_app/ui/calorie_card.dart';
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

/// Opens one of your logged foods like a bank-app transaction receipt:
/// what it was, when, how much, where it came from and a note, with the
/// actions underneath (change it, log it again, make it a direct debit,
/// delete). [canEdit] is false on past, closed or rest days (view only);
/// a note can still be added unless [canNote] is false. [canDelete]
/// (default: same as [canEdit]) allows Delete on its own, so food can be
/// removed from any day.
Future<EntrySheetResult?> showEntrySheet(
  BuildContext context, {
  required String entryId,
  required Map<String, dynamic> entry,
  required bool canEdit,
  bool? canDelete,
  bool canDirectDebit = true,
  bool canNote = true,
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
      canDelete: canDelete ?? canEdit,
      canDirectDebit: canDirectDebit,
      canNote: canNote,
      reactions: reactions,
      logAgainMeal: logAgainMeal,
    ),
  );
}

/// The big emoji at the top of the receipt: a recipe, or the meal.
String entryEmoji(Map<String, dynamic> entry, {String? meal}) {
  if (entry['is_recipe'] == true) return '🍲';
  switch (meal ?? FoodLog.mealOf(entry['foodCategory'])) {
    case 'Breakfast':
      return '🥣';
    case 'Lunch':
      return '🥪';
    case 'Dinner':
      return '🍝';
    default:
      return '🍎';
  }
}

/// "Today, 12:41", "Yesterday, 08:05" or "Fri 9 Oct, 19:30".
String entryTimeLabel(DateTime at) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final now = BalanceService.now();
  final time = '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
  final String day;
  if (BalanceService.sameDay(at, now)) {
    day = 'Today';
  } else if (BalanceService.sameDay(at, BalanceService.addDays(now, -1))) {
    day = 'Yesterday';
  } else {
    final year = at.year == now.year ? '' : ' ${at.year}';
    day = '${days[at.weekday - 1]} ${at.day} ${months[at.month - 1]}'
        '$year';
  }
  return '$day, $time';
}

/// Where the numbers came from, in plain words ("✨ AI estimate"), or null
/// if the entry doesn't say (older entries).
String? entrySourceLabel(Map<String, dynamic> entry) {
  final estimate = entry['food_estimate'] == true;
  final edited = entry['food_edited'] == true;
  String? label;
  if (entry['is_recipe'] == true) {
    label = '📖 Your recipe';
  } else {
    switch (entry['food_source']) {
      case 'ai':
        label = '✨ AI estimate';
      case 'barcode':
        label = '📷 Scanned barcode';
      case 'fatsecret':
        label = '🔎 Database match';
      case 'web':
        label = '🌐 Found online';
      case 'recent':
        label = '🔁 Logged again';
      case 'manual':
        label = '✍️ Typed in by you';
    }
  }
  if (label == null && estimate) label = '✨ Estimate';
  if (label == null) return edited ? '✍️ Calories fixed by you' : null;
  if (estimate && !label.contains('estimate') && !label.contains('Estimate')) {
    label = '$label · estimate';
  }
  if (edited) label = '$label · calories fixed by you';
  return label;
}

class _EntrySheet extends StatefulWidget {
  final String entryId;
  final Map<String, dynamic> entry;
  final bool canEdit;
  final bool canDelete;
  final bool canDirectDebit;
  final bool canNote;
  final List<Map<String, dynamic>> reactions;
  final String? logAgainMeal;

  const _EntrySheet({
    required this.entryId,
    required this.entry,
    required this.canEdit,
    required this.canDelete,
    required this.canDirectDebit,
    required this.canNote,
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
  late final String _basePortion = FoodLog.basePortionOf(widget.entry);

  /// Any other amount: a multiple that isn't one of the buttons (×2.5), or
  /// grams / ounces when the portion says what it weighs.
  late final AmountInput _amount = AmountInput(
    basePortion: _basePortion,
    multiplier: _startMultiplier,
    startEmpty: _portions.any((m) => _same(m, _startMultiplier)),
  );
  final _caloriesController = TextEditingController();
  late final _noteController =
      TextEditingController(text: FoodLog.noteOf(widget.entry));

  /// The note as last saved (so we know when there's something to save).
  late String _savedNote = FoodLog.noteOf(widget.entry);
  bool _savingNote = false;
  bool _noteJustSaved = false;

  /// The portion / calories / meal controls are tucked away until asked
  /// for, so the receipt reads first.
  bool _editing = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    // Closing the sheet never loses a typed note (like a bank app's
    // transaction notes, it just saves).
    if (_noteDirty) {
      FoodLog.setNote(widget.entryId, _noteController.text)
          .catchError((Object _) {});
    }
    _amount.dispose();
    _caloriesController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String get _name =>
      (widget.entry['food_description'] ?? 'Food').toString();

  bool get _isEstimate => widget.entry['food_estimate'] == true;

  bool get _noteDirty =>
      widget.canNote && _noteController.text.trim() != _savedNote;

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
    if (_amount.isEmpty) return false;
    final m = _amount.multiplier;
    return m == null || m <= 0;
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
      // In portions the buttons say it; in grams the box shows it.
      if (_amount.unit == AmountUnit.portions) {
        _amount.controller.clear();
      } else {
        _amount.show(m);
      }
    });
  }

  void _onCustomChanged(String _) {
    final m = _amount.multiplier;
    setState(() {
      if (m != null && m.isFinite && m > 0) _multiplier = m;
    });
  }

  void _setUnit(AmountUnit unit) {
    setState(() {
      // Switching to grams shows the current amount in grams.
      if (_amount.isEmpty && unit != AmountUnit.portions) {
        _amount.unit = unit;
        _amount.show(_multiplier);
      } else {
        _amount.setUnit(unit);
        if (unit == AmountUnit.portions &&
            _portions.any((m) => _same(m, _multiplier))) {
          _amount.controller.clear();
        }
      }
    });
  }

  Future<void> _saveNote() async {
    if (_savingNote || !_noteDirty) return;
    final text = _noteController.text.trim();
    setState(() {
      _savingNote = true;
      _error = null;
    });
    try {
      await FoodLog.setNote(widget.entryId, text);
      if (!mounted) return;
      setState(() {
        _savedNote = text;
        _savingNote = false;
        _noteJustSaved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingNote = false;
        _error = "Couldn't save your note. Please try again.";
      });
    }
  }

  Future<void> _save() async {
    if (_busy || !_changed || _caloriesInvalid || _customInvalid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // A typed note goes with it (it's only the note field).
      if (_noteDirty) {
        final text = _noteController.text.trim();
        await FoodLog.setNote(widget.entryId, text);
        _savedNote = text;
      }
      // Fixing a looked-up food's calories: tell the server (per portion),
      // so an answer several people correct is looked up again.
      final fixed = _fixedCalories;
      final source = '${widget.entry['food_source'] ?? ''}';
      if (fixed != null &&
          _multiplier > 0 &&
          FoodResolver.lookupSources.contains(source)) {
        FoodResolver.reportFix(_name, fixed / _multiplier);
      }
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

  /// One "label ........ value" line of the receipt.
  Widget _detailRow(String label, Widget value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: value),
            ),
          ],
        ),
      );

  Widget _detailText(String text) => Text(
        text,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      );

  /// A row in the actions list under the receipt.
  Widget _actionTile({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
    Widget? trailing,
  }) {
    final c = color ?? AppColors.ink;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color ?? AppText.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: onTap == null ? AppColors.muted : c,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  /// "×1 is 30 g. Now 45 g.", so the amount is clear whichever way it's
  /// typed.
  String _portionHint() {
    final one = _basePortion.isEmpty
        ? '×1 is one portion, as it was looked up.'
        : '×1 is $_basePortion.';
    final other = _amount.equivalent(_multiplier, _basePortion);
    if (other == null || _same(_multiplier, 1)) return one;
    return '$one Now $other.';
  }

  Widget _editPanel(Macros preview) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('Portion'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final m in _portions)
                ChoiceChip(
                  label: Text('×${FoodLog.formatAmount(m)}'),
                  selected: _same(_multiplier, m) &&
                      (_amount.isEmpty ||
                          _amount.unit != AmountUnit.portions),
                  showCheckmark: false,
                  onSelected: _busy ? null : (_) => _pickPortion(m),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_amount.units.length > 1) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: AmountUnitPicker(
                units: _amount.units,
                selected: _amount.unit,
                onChanged: _busy ? null : _setUnit,
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _amount.controller,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: AmountInput.inputFormatters,
            onChanged: _onCustomChanged,
            decoration: InputDecoration(
              isDense: true,
              labelText: _amount.unit == AmountUnit.portions
                  ? 'Other'
                  : 'Exact amount',
              prefixText: _amount.unit == AmountUnit.portions ? '×' : null,
              suffixText: _amount.unit == AmountUnit.portions
                  ? null
                  : PortionAmount.label(_amount.unit),
              errorText: _customInvalid ? 'Above 0' : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _portionHint(),
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
              helperMaxLines: 2,
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
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed:
                  _busy || !_changed || _caloriesInvalid || _customInvalid
                      ? null
                      : _save,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save changes',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final portion = (widget.entry['food_portion'] ?? '').toString();
    final preview = _preview;
    final canEdit = widget.canEdit;
    final logMeal = widget.logAgainMeal ?? _meal;
    final loggedAt = BalanceService.entryDate(widget.entry);
    final source = entrySourceLabel(widget.entry);
    final logged = Macros.fromEntry(widget.entry);
    final kcalChanged = preview.calories.round() != logged.calories.round();

    final actions = <Widget>[
      if (canEdit)
        _actionTile(
          icon: Icons.tune_rounded,
          label: 'Change portion, calories or meal',
          onTap: _busy ? null : () => setState(() => _editing = !_editing),
          trailing: Icon(
            _editing ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            color: AppColors.muted,
          ),
        ),
      if (canEdit && _editing) _editPanel(preview),
      if (canEdit)
        _actionTile(
          icon: Icons.replay_rounded,
          label: 'Log again to $logMeal',
          onTap: _busy ? null : _logAgain,
        ),
      if (widget.canDirectDebit)
        _actionTile(
          icon: Icons.autorenew,
          label: 'Make it a direct debit',
          onTap: _busy
              ? null
              : () => Navigator.pop(
                    context,
                    const EntrySheetResult(EntrySheetAction.directDebit),
                  ),
        ),
      // Delete is always last, and red.
      if (widget.canDelete)
        _actionTile(
          icon: Icons.delete_outline,
          label: 'Delete',
          color: AppText.red600,
          onTap: _busy
              ? null
              : () => Navigator.pop(
                    context,
                    const EntrySheetResult(EntrySheetAction.delete),
                  ),
        ),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The receipt header: what, how much, when.
            Center(
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.indigo50,
                  shape: BoxShape.circle,
                ),
                child: ExcludeSemantics(
                  child: Text(
                    entryEmoji(widget.entry, meal: _meal),
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _name,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatCardKcal(preview.calories)} kcal',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (kcalChanged)
              Text(
                'was ${formatCardKcal(logged.calories)} '
                'kcal · not saved yet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppText.amber700),
              ),
            const SizedBox(height: 2),
            Text(
              [
                if (loggedAt != null) entryTimeLabel(loggedAt),
                _meal,
              ].join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
            if (_isEstimate) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                decoration: BoxDecoration(
                  color: AppColors.amber50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.amber200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 18, color: AppText.amber700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Estimate: AI guessed these numbers. If you know '
                        'the real calories, fix them.',
                        style: TextStyle(fontSize: 13, color: AppColors.ink),
                      ),
                    ),
                    if (canEdit && !_editing)
                      TextButton(
                        onPressed: () => setState(() => _editing = true),
                        style: TextButton.styleFrom(
                            minimumSize: const Size(0, 44)),
                        child: const Text('Fix'),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // The details, like a receipt.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.gray50,
                borderRadius: BorderRadius.circular(AppDecor.radius),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  // When and which meal are in the header above.
                  if (portion.isNotEmpty)
                    _detailRow('Portion', _detailText(portion)),
                  _detailRow(
                    'Macros',
                    MacroText(
                      protein: preview.protein,
                      carbs: preview.carbs,
                      fat: preview.fat,
                      fontSize: 14,
                    ),
                  ),
                  if (source != null)
                    _detailRow('Source', _detailText(source)),
                ],
              ),
            ),
            if (widget.canNote) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _noteController,
                enabled: !_busy,
                minLines: 1,
                maxLines: 3,
                maxLength: FoodLog.maxNoteLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() => _noteJustSaved = false),
                onSubmitted: (_) => _saveNote(),
                decoration: InputDecoration(
                  labelText: 'Note',
                  hintText: "Add a note… e.g. at Nando's with Sam",
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  prefixIcon: const Icon(Icons.edit_note_rounded),
                  // Counter only once it matters.
                  counterText: _noteController.text.length >
                          FoodLog.maxNoteLength - 40
                      ? null
                      : '',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_noteDirty || _noteJustSaved || _savingNote)
                Align(
                  alignment: Alignment.centerRight,
                  child: _noteJustSaved && !_noteDirty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Note saved',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppText.emerald700,
                            ),
                          ),
                        )
                      : TextButton(
                          onPressed: _savingNote ? null : _saveNote,
                          style: TextButton.styleFrom(
                              minimumSize: const Size(0, 44)),
                          child: Text(_savingNote ? 'Saving…' : 'Save note'),
                        ),
                ),
            ],
            if (widget.reactions.isNotEmpty) ...[
              const SizedBox(height: 16),
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
            // Actions under the details; Delete last.
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                decoration: AppDecor.card,
                clipBehavior: Clip.antiAlias,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 1, thickness: 1, color: AppColors.border),
                        actions[i],
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (!canEdit && widget.canNote) ...[
              const SizedBox(height: 10),
              Text(
                "Food on a past, closed or rest day can't be changed. "
                'Notes still save.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
