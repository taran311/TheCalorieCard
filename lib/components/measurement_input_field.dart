import 'package:flutter/material.dart';

class MeasurementInputField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final String suffix;
  final Function(int?) onChanged;

  const MeasurementInputField({
    Key? key,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.suffix,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<MeasurementInputField> createState() => _MeasurementInputFieldState();
}

class _MeasurementInputFieldState extends State<MeasurementInputField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() {
      if (!widget.focusNode.hasFocus &&
          widget.controller.text.isNotEmpty &&
          !widget.controller.text.endsWith(widget.suffix)) {
        widget.controller.text = '${widget.controller.text}${widget.suffix}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        title: Text(
          widget.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: widget.hintText,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
          ),
          onChanged: (value) {
            setState(() {
              int? parsedValue =
                  int.tryParse(value.replaceAll(widget.suffix, ''));
              widget.onChanged(parsedValue);
            });
          },
        ),
      ),
    );
  }
}
