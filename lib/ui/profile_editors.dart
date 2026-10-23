// Pieces shared by Get started (one question per screen) and Goals and
// profile (tap a row to change one thing): big choice tiles, activity
// levels, goal pace, and the macro editor.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/goal_maths.dart';
import 'package:namer_app/services/units.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/calorie_symbol.dart';

/// A big tappable option: title, optional line under it, tick when chosen.
class ProfileChoice extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const ProfileChoice({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? AppColors.indigo50 : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon,
                          size: 26,
                          color:
                              selected ? AppText.primaryDark : AppColors.gray600),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? AppText.primaryDark
                                  : AppColors.ink,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: selected ? AppColors.primary : AppColors.border,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The five activity levels (stored as `exercise_level` 0–4).
const activityLevels = <({String title, String subtitle})>[
  (title: 'Not much', subtitle: 'Desk job, little or no exercise'),
  (title: 'A little', subtitle: '1–3 hours of exercise a week'),
  (title: 'Moderate', subtitle: '4–6 hours a week'),
  (title: 'Active', subtitle: '7–9 hours a week'),
  (title: 'Very active', subtitle: '10+ hours a week'),
];

String activityTitle(double level) {
  final i = level.round().clamp(0, activityLevels.length - 1).toInt();
  return activityLevels[i].title;
}

/// Sent to the server as `exercise_level` text; keep these as they are.
String activityServerText(double level) => switch (level.round()) {
      1 => '1-3 hours per week',
      2 => '4-6 hours per week',
      3 => '7-9 hours per week',
      4 => '10+ hours per week',
      _ => 'No activity',
    };

/// Lose, maintain or gain, as one big tile each.
class GoalModeChoices extends StatelessWidget {
  final String? mode;
  final ValueChanged<String> onChanged;

  const GoalModeChoices({super.key, required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ProfileChoice(
          icon: Icons.trending_down,
          title: 'Lose weight',
          subtitle: 'Eat a little less than you burn',
          selected: mode == 'lose',
          onTap: () => onChanged('lose'),
        ),
        ProfileChoice(
          icon: Icons.horizontal_rule,
          title: 'Stay as I am',
          subtitle: 'Eat about what you burn',
          selected: mode == 'maintain',
          onTap: () => onChanged('maintain'),
        ),
        ProfileChoice(
          icon: Icons.trending_up,
          title: 'Gain weight',
          subtitle: 'Build muscle with a small surplus',
          selected: mode == 'gain',
          onTap: () => onChanged('gain'),
        ),
      ],
    );
  }
}

String goalModeTitle(String? mode) => switch (mode) {
      'maintain' => 'Stay as I am',
      'gain' => 'Gain weight',
      _ => 'Lose weight',
    };

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "10 Mar 2027".
String formatGoalDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "0.5 kg a week" or "1 lb a week".
String paceRate(GoalPace pace, UnitPrefs units) {
  if (units.isMetric) {
    return '${Units.formatNumber(pace.kgPerWeek, maxPlaces: 2)} kg a week';
  }
  return switch (pace) {
    GoalPace.relaxed => '½ lb a week',
    GoalPace.steady => '1 lb a week',
    GoalPace.faster => '1½ lb a week',
  };
}

/// What a pace means for you: its calories a day and, with a goal weight,
/// when you'd get there.
({int calories, bool floored, DateTime? date}) paceOutcome({
  required GoalPace pace,
  required String? mode,
  required double maintenance,
  double? floor,
  double? fromKg,
  double? goalKg,
  DateTime? start,
}) {
  final kcal = paceCalories(maintenance, mode, pace.kgPerWeek, floor: floor);
  final wanted = paceCalories(maintenance, mode, pace.kgPerWeek);
  final floored = kcal != wanted;
  DateTime? date;
  if (fromKg != null && goalKg != null) {
    date = goalReachedBy(
      fromKg: fromKg,
      goalKg: goalKg,
      kgPerWeek: kgPerWeekAt(maintenance, kcal),
      start: start ?? DateTime.now(),
    );
  }
  return (calories: kcal, floored: floored, date: date);
}

/// Relaxed / Steady / Faster, each showing its calories and goal date.
class PaceChoices extends StatelessWidget {
  final String? mode;
  final GoalPace value;
  final ValueChanged<GoalPace> onChanged;
  final double maintenance;
  final double? floor;
  final double? fromKg;
  final double? goalKg;
  final UnitPrefs units;

  const PaceChoices({
    super.key,
    required this.mode,
    required this.value,
    required this.onChanged,
    required this.maintenance,
    required this.units,
    this.floor,
    this.fromKg,
    this.goalKg,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final pace in GoalPace.forMode(mode))
          Builder(builder: (context) {
            final o = paceOutcome(
              pace: pace,
              mode: mode,
              maintenance: maintenance,
              floor: floor,
              fromKg: fromKg,
              goalKg: goalKg,
            );
            final parts = [
              '$calSym${formatCardKcal(o.calories)} a day'
                  '${o.floored ? ' (the safe minimum)' : ''}',
              if (o.date != null) 'goal by ${formatGoalDate(o.date!)}',
            ];
            return ProfileChoice(
              title: '${pace.label} · ${paceRate(pace, units)}',
              subtitle: parts.join(' · '),
              selected: value == pace,
              onTap: () => onChanged(pace),
            );
          }),
        if (mode == 'lose')
          Text(
            'Losing about 0.5 kg (1 lb) a week is a pace most people can '
            'keep up. Your calories never go below a safe minimum.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
      ],
    );
  }
}

/// Protein, carbs and fat: one-tap splits and the three numbers.
class MacroEditor extends StatefulWidget {
  /// The calorie goal the splits are worked out for.
  final int calories;
  final int? protein;
  final int? carbs;
  final int? fat;
  final void Function(int protein, int carbs, int fat) onChanged;

  const MacroEditor({
    super.key,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.onChanged,
  });

  @override
  State<MacroEditor> createState() => _MacroEditorState();
}

class _MacroEditorState extends State<MacroEditor> {
  late final _p = TextEditingController(text: '${widget.protein ?? ''}');
  late final _c = TextEditingController(text: '${widget.carbs ?? ''}');
  late final _f = TextEditingController(text: '${widget.fat ?? ''}');

  @override
  void dispose() {
    _p.dispose();
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  int _v(TextEditingController t) => int.tryParse(t.text) ?? 0;

  void _emit() => widget.onChanged(_v(_p), _v(_c), _v(_f));

  void _pick(MacroSplit split) {
    final m = split.macrosFor(widget.calories);
    setState(() {
      _p.text = '${m.protein.round()}';
      _c.text = '${m.carbs.round()}';
      _f.text = '${m.fat.round()}';
    });
    _emit();
  }

  Widget _field(String label, TextEditingController t, Color dot) {
    return Expanded(
      child: TextField(
        controller: t,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'g',
          isDense: true,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 10, right: 6),
            child: Icon(Icons.circle, size: 9, color: dot),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onChanged: (_) {
          setState(() {});
          _emit();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = MacroSplit.matching(_v(_p), _v(_c), _v(_f));
    final total = caloriesFromMacros(_v(_p), _v(_c), _v(_f));
    final off = (total - widget.calories).abs() > 60 && total > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final split in MacroSplit.presets)
              ChoiceChip(
                label: Text(split.label),
                selected: current?.id == split.id,
                onSelected: widget.calories <= 0 ? null : (_) => _pick(split),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          current == null
              ? 'Your own split'
              : current.id == 'keto'
                  ? '${current.hint}. Keto is a big change for most people: '
                      'worth checking with your doctor if you have a health '
                      'condition.'
                  : current.hint,
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _field('Protein', _p, CalorieCardColors.protein),
            const SizedBox(width: 8),
            _field('Carbs', _c, CalorieCardColors.carbs),
            const SizedBox(width: 8),
            _field('Fat', _f, CalorieCardColors.fat),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          off
              ? 'These add up to $calSym${formatCardKcal(total)}; your goal is '
                  '$calSym${formatCardKcal(widget.calories)}.'
              : 'Adds up to $calSym${formatCardKcal(total)}.',
          style: TextStyle(
            fontSize: 12,
            color: off ? AppText.amber700 : AppColors.muted,
          ),
        ),
      ],
    );
  }
}
