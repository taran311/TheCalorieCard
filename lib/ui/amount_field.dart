import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/portion_amount.dart';
import 'package:namer_app/ui/responsive.dart';

/// Unit buttons for an amount box: "portions | g | oz" (or ml / fl oz).
/// Switching unit rewrites the number in the box, so it's the same amount.
class AmountUnitPicker extends StatelessWidget {
  final List<AmountUnit> units;
  final AmountUnit selected;
  final ValueChanged<AmountUnit>? onChanged;

  const AmountUnitPicker({
    super.key,
    required this.units,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (units.length < 2) return const SizedBox.shrink();
    return SegmentedButton<AmountUnit>(
      segments: [
        for (final u in units)
          ButtonSegment(value: u, label: Text(PortionAmount.label(u))),
      ],
      selected: {selected},
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      onSelectionChanged:
          onChanged == null ? null : (s) => onChanged!(s.first),
    );
  }
}

/// Keeps an amount box and its unit in step: converts the typed number
/// when the unit changes, and turns it into a multiplier of the portion.
class AmountInput {
  final PortionSize? size;
  final List<AmountUnit> units;
  final TextEditingController controller;
  AmountUnit unit;

  AmountInput({
    required String basePortion,
    required double multiplier,
    bool allowPortions = true,
    AmountUnit? startUnit,
    bool startEmpty = false,
  })  : size = PortionAmount.sizeOf(basePortion),
        units = PortionAmount.unitsFor(PortionAmount.sizeOf(basePortion),
            portions: allowPortions),
        unit = AmountUnit.portions,
        controller = TextEditingController() {
    unit = startUnit != null && units.contains(startUnit)
        ? startUnit
        : units.first;
    if (!startEmpty) {
      controller.text = PortionAmount.format(
          PortionAmount.valueFor(multiplier, unit, size), unit);
    }
  }

  static final inputFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
  ];

  double? get _value {
    final v = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    return v != null && v.isFinite ? v : null;
  }

  /// The multiplier the box says, or null if it's empty or not valid.
  double? get multiplier {
    final v = _value;
    return v == null ? null : PortionAmount.multiplierFor(v, unit, size);
  }

  bool get isEmpty => controller.text.trim().isEmpty;

  /// Switch unit, rewriting the number so it's the same amount.
  void setUnit(AmountUnit next) {
    if (next == unit) return;
    final m = multiplier;
    unit = next;
    if (m != null) {
      controller.text = PortionAmount.format(
          PortionAmount.valueFor(m, next, size), next);
    }
  }

  /// Shows [multiplier] in the current unit (after a preset is picked).
  void show(double multiplier) {
    controller.text = PortionAmount.format(
        PortionAmount.valueFor(multiplier, unit, size), unit);
  }

  /// The same amount said another way: "45 g" when typing portions or
  /// ounces, "1.5 × 30 g" when typing grams. Null if the size isn't known.
  String? equivalent(double multiplier, String basePortion) {
    final s = size;
    if (s == null) return null;
    final metric = s.volume ? AmountUnit.ml : AmountUnit.g;
    if (unit == metric) {
      final portions = PortionAmount.format(multiplier, AmountUnit.portions);
      return '$portions × ${basePortion.isEmpty ? 'portion' : basePortion}';
    }
    final value = PortionAmount.valueFor(multiplier, metric, s);
    return '${PortionAmount.format(value, metric)} ${PortionAmount.label(metric)}';
  }

  void dispose() => controller.dispose();
}

/// The small grey line under an amount box.
Widget amountHint(String text) => Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.muted)),
    );
