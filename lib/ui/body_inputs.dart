import 'package:flutter/material.dart';
import 'package:namer_app/components/measurement_input_field.dart';
import 'package:namer_app/services/goal_maths.dart';
import 'package:namer_app/services/profile_limits.dart';
import 'package:namer_app/services/units.dart';
import 'package:namer_app/ui/responsive.dart';

/// Metric, stones or pounds. Used on Get started, Goals and profile and
/// the weight log.
class UnitsPicker extends StatelessWidget {
  final UnitPrefs value;
  final ValueChanged<UnitPrefs> onChanged;

  const UnitsPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Units',
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<UnitPrefs>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            selectedBackgroundColor: AppColors.primary.withValues(alpha: 0.15),
            selectedForegroundColor: AppText.primary,
          ),
          segments: [
            for (final u in UnitPrefs.choices)
              ButtonSegment<UnitPrefs>(
                value: u,
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(u.label, maxLines: 1),
                ),
              ),
          ],
          selected: {value},
          onSelectionChanged: (picked) => onChanged(picked.first),
        ),
      ),
    );
  }
}

/// A small red message under a pair of fields (feet + inches, stones +
/// pounds).
class _PairError extends StatelessWidget {
  final String message;

  const _PairError(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}

/// Height in cm, or feet and inches. Reports cm (or null) whatever is
/// shown. [valueCm] is the current value: pass back what [onChanged] gave
/// you; a different value (e.g. once your profile has loaded) refills the
/// fields.
class HeightInput extends StatefulWidget {
  final UnitPrefs units;
  final double? valueCm;
  final ValueChanged<double?> onChanged;
  final String label;

  const HeightInput({
    super.key,
    required this.units,
    required this.valueCm,
    required this.onChanged,
    this.label = 'Height',
  });

  @override
  State<HeightInput> createState() => _HeightInputState();
}

class _HeightInputState extends State<HeightInput> {
  final _cm = TextEditingController();
  final _ft = TextEditingController();
  final _in = TextEditingController();
  final _ftFocus = FocusNode();
  final _inFocus = FocusNode();
  double? _value;

  @override
  void initState() {
    super.initState();
    _fill(widget.valueCm);
    _ftFocus.addListener(_refresh);
    _inFocus.addListener(_refresh);
  }

  @override
  void didUpdateWidget(HeightInput old) {
    super.didUpdateWidget(old);
    if (old.units.height != widget.units.height ||
        widget.valueCm != _value) {
      _fill(widget.valueCm);
    }
  }

  @override
  void dispose() {
    _cm.dispose();
    _ft.dispose();
    _in.dispose();
    _ftFocus.dispose();
    _inFocus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _fill(double? cm) {
    _value = cm;
    if (cm == null) {
      _cm.text = '';
      _ft.text = '';
      _in.text = '';
      return;
    }
    _cm.text = '${cm.round()}';
    final fi = Units.cmToFeetInches(cm);
    _ft.text = '${fi.ft}';
    _in.text = '${fi.inches}';
  }

  void _report(double? cm) {
    final stored = cm == null ? null : Units.storeCm(cm);
    _value = stored;
    widget.onChanged(stored);
  }

  void _onImperial() {
    final ft = Units.parseNumber(_ft.text);
    final inches = Units.parseNumber(_in.text);
    setState(() {});
    if (ft == null && inches == null) {
      _report(null);
      return;
    }
    _report(Units.feetInchesToCm(ft ?? 0, inches ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.units.height == HeightUnit.cm) {
      return MeasurementInputField(
        label: widget.label,
        controller: _cm,
        hintText: 'E.g. 175',
        unit: 'cm',
        min: ProfileLimits.minHeightCm,
        max: ProfileLimits.maxHeightCm,
        rangeMessage: Units.heightRangeMessage(widget.units),
        textInputAction: TextInputAction.next,
        onChanged: _report,
      );
    }
    final v = _value;
    final busy = _ftFocus.hasFocus || _inFocus.hasFocus;
    final showError = v != null && !ProfileLimits.heightOk(v) && !busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MeasurementInputField(
                label: widget.label,
                controller: _ft,
                focusNode: _ftFocus,
                hintText: '5',
                unit: 'ft',
                textInputAction: TextInputAction.next,
                onChanged: (_) => _onImperial(),
              ),
            ),
            Expanded(
              child: MeasurementInputField(
                label: '',
                controller: _in,
                focusNode: _inFocus,
                hintText: '9',
                unit: 'in',
                textInputAction: TextInputAction.next,
                onChanged: (_) => _onImperial(),
              ),
            ),
          ],
        ),
        if (showError) _PairError(Units.heightRangeMessage(widget.units)),
      ],
    );
  }
}

/// Weight in kg, stones and pounds, or pounds. Reports kg (or null).
/// [valueKg] works like [HeightInput.valueCm].
class WeightInput extends StatefulWidget {
  final UnitPrefs units;
  final double? valueKg;
  final ValueChanged<double?> onChanged;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  const WeightInput({
    super.key,
    required this.units,
    required this.valueKg,
    required this.onChanged,
    this.label = 'Weight',
    this.autofocus = false,
    this.onSubmitted,
  });

  @override
  State<WeightInput> createState() => _WeightInputState();
}

class _WeightInputState extends State<WeightInput> {
  final _main = TextEditingController(); // kg, lb, or stones
  final _lb = TextEditingController(); // pounds beside stones
  final _mainFocus = FocusNode();
  final _lbFocus = FocusNode();
  double? _value;

  @override
  void initState() {
    super.initState();
    _fill(widget.valueKg);
    _mainFocus.addListener(_refresh);
    _lbFocus.addListener(_refresh);
  }

  @override
  void didUpdateWidget(WeightInput old) {
    super.didUpdateWidget(old);
    if (old.units.weight != widget.units.weight ||
        widget.valueKg != _value) {
      _fill(widget.valueKg);
    }
  }

  @override
  void dispose() {
    _main.dispose();
    _lb.dispose();
    _mainFocus.dispose();
    _lbFocus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _fill(double? kg) {
    _value = kg;
    if (kg == null) {
      _main.text = '';
      _lb.text = '';
      return;
    }
    switch (widget.units.weight) {
      case WeightUnit.kg:
        _main.text = MeasurementInputField.textFor(kg);
        _lb.text = '';
      case WeightUnit.lb:
        _main.text = MeasurementInputField.textFor(Units.kgToLb(kg));
        _lb.text = '';
      case WeightUnit.stLb:
        final v = Units.kgToStLb(kg);
        _main.text = '${v.st}';
        _lb.text = MeasurementInputField.textFor(v.lb);
    }
  }

  void _report(double? kg) {
    final stored = kg == null ? null : Units.storeKg(kg);
    _value = stored;
    widget.onChanged(stored);
  }

  void _onStones() {
    final st = Units.parseNumber(_main.text);
    final lb = Units.parseNumber(_lb.text);
    setState(() {});
    if (st == null && lb == null) {
      _report(null);
      return;
    }
    _report(Units.stLbToKg(st ?? 0, lb ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final units = widget.units;
    switch (units.weight) {
      case WeightUnit.kg:
        return MeasurementInputField(
          label: widget.label,
          controller: _main,
          focusNode: _mainFocus,
          hintText: 'E.g. 72.5',
          unit: 'kg',
          decimal: true,
          min: ProfileLimits.minWeightKg,
          max: ProfileLimits.maxWeightKg,
          rangeMessage: Units.weightRangeMessage(units),
          autofocus: widget.autofocus,
          onSubmitted: widget.onSubmitted,
          onChanged: _report,
        );
      case WeightUnit.lb:
        return MeasurementInputField(
          label: widget.label,
          controller: _main,
          focusNode: _mainFocus,
          hintText: 'E.g. 160',
          unit: 'lb',
          decimal: true,
          min: Units.kgToLb(ProfileLimits.minWeightKg),
          max: Units.kgToLb(ProfileLimits.maxWeightKg),
          rangeMessage: Units.weightRangeMessage(units),
          autofocus: widget.autofocus,
          onSubmitted: widget.onSubmitted,
          onChanged: (lb) => _report(lb == null ? null : Units.lbToKg(lb)),
        );
      case WeightUnit.stLb:
        final v = _value;
        final busy = _mainFocus.hasFocus || _lbFocus.hasFocus;
        final showError = v != null && !ProfileLimits.weightOk(v) && !busy;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MeasurementInputField(
                    label: widget.label,
                    controller: _main,
                    focusNode: _mainFocus,
                    hintText: '11',
                    unit: 'st',
                    autofocus: widget.autofocus,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _onStones(),
                  ),
                ),
                Expanded(
                  child: MeasurementInputField(
                    label: '',
                    controller: _lb,
                    focusNode: _lbFocus,
                    hintText: '4',
                    unit: 'lb',
                    decimal: true,
                    onSubmitted: widget.onSubmitted,
                    onChanged: (_) => _onStones(),
                  ),
                ),
              ],
            ),
            if (showError) _PairError(Units.weightRangeMessage(units)),
          ],
        );
    }
  }
}

/// A gentle, non-blocking note under "Set my own" when the daily budget is
/// very low. Nothing when [calories] is empty or a usual amount.
class LowCalorieNote extends StatelessWidget {
  final num? calories;

  const LowCalorieNote({super.key, required this.calories});

  @override
  Widget build(BuildContext context) {
    final c = calories;
    if (c == null || c <= 0 || c >= lowCalorieWarningKcal) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.amber50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.amber200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: AppText.amber700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "That's a very low daily budget. Under 1,200 kcal it's hard "
                'to get everything your body needs, so it\'s best done with '
                'advice from your GP. You can still save it.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppColors.gray800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
