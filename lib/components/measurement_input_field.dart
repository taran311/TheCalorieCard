import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/units.dart';

/// A labelled number field for age, height, weight and macros.
///
/// The unit ("cm", "kg", "g") is shown beside the number as decoration and
/// is never part of the text, so deleting a digit can't make the value
/// unreadable. Only digits (and a decimal point when [decimal] is on) can
/// be typed. When [min]/[max] are given, an out-of-range value shows
/// [rangeMessage] under the field: once you've left it, or straight away
/// if it's already too big.
class MeasurementInputField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;

  /// Shown after the number, e.g. "cm".
  final String? unit;

  /// Allow a decimal point (weight). Off for whole numbers (age, grams).
  final bool decimal;

  final double? min;
  final double? max;
  final String? rangeMessage;

  /// An error from outside (e.g. a combined feet + inches check).
  final String? errorText;

  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// The number typed, or null when the field is empty or unreadable.
  final ValueChanged<double?> onChanged;

  const MeasurementInputField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.hintText,
    this.unit,
    this.decimal = false,
    this.min,
    this.max,
    this.rangeMessage,
    this.errorText,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
  });

  /// [value] as the field shows it: no trailing ".0", no unit.
  static String textFor(num? value, {int maxPlaces = 1}) =>
      value == null
          ? ''
          : Units.formatNumber(value.toDouble(), maxPlaces: maxPlaces);

  @override
  State<MeasurementInputField> createState() => _MeasurementInputFieldState();
}

class _MeasurementInputFieldState extends State<MeasurementInputField> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(MeasurementInputField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    super.dispose();
  }

  // Re-check the range message when focus leaves.
  void _onFocus() {
    if (mounted) setState(() {});
  }

  String? get _rangeError {
    final v = Units.parseNumber(widget.controller.text);
    if (v == null) return null;
    final tooSmall = widget.min != null && v < widget.min!;
    final tooBig = widget.max != null && v > widget.max!;
    if (tooBig || (tooSmall && !_focus.hasFocus)) {
      return widget.rangeMessage ?? 'That looks too ${tooBig ? 'high' : 'low'}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.errorText ?? _rangeError;
    // The unit beside the number only shows once something's typed, so
    // the hint carries it until then ("E.g. 175 cm").
    final unit = widget.unit;
    final hint = widget.hintText;
    final shownHint = hint != null && unit != null && !hint.endsWith(unit)
        ? '$hint $unit'
        : hint;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            keyboardType:
                TextInputType.numberWithOptions(decimal: widget.decimal),
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            autofocus: widget.autofocus,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  widget.decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]')),
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              hintText: shownHint,
              suffixText: unit,
              errorText: error,
              errorMaxLines: 3,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
            onChanged: (value) {
              // Rebuild for the range message, then report the number.
              setState(() {});
              widget.onChanged(Units.parseNumber(value));
            },
          ),
        ],
      ),
    );
  }
}
