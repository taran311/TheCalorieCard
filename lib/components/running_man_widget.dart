import 'package:flutter/material.dart';

class RunningManWidget extends StatefulWidget {
  final ValueChanged<int> onStepsChanged; // Callback for step updates
  final bool isActive; // Determines if the widget is active or disabled
  final int initialSteps; // Initial step count

  RunningManWidget({
    required this.onStepsChanged,
    this.isActive = true,
    this.initialSteps = 0,
  });

  @override
  _RunningManWidgetState createState() => _RunningManWidgetState();
}

class _RunningManWidgetState extends State<RunningManWidget> {
  int steps = 0; // Step count
  final int maxSteps = 10000; // Maximum steps

  @override
  void initState() {
    super.initState();
    steps = widget.initialSteps; // Set initial value
  }

  void _showInputDialog() {
    if (!widget.isActive) return; // Ignore taps if inactive

    final TextEditingController controller =
        TextEditingController(text: steps.toString());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            'Enter Steps Count',
            style: TextStyle(color: Colors.orangeAccent),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Enter a value (0 - 10,000)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child:
                  Text('Cancel', style: TextStyle(color: Colors.orangeAccent)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  steps = int.tryParse(controller.text) ?? 0;
                  steps = steps.clamp(0, maxSteps); // Clamp to range
                  widget.onStepsChanged(steps); // Notify parent
                });
                Navigator.of(context).pop();
              },
              child:
                  Text('Submit', style: TextStyle(color: Colors.orangeAccent)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double fillProportion = (steps / maxSteps).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: widget.isActive ? _showInputDialog : null,
      child: Opacity(
        opacity: widget.isActive ? 1.0 : 0.5,
        child: Focus(
          canRequestFocus: false, // Prevent focus outlines
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 2,
                style: BorderStyle.solid,
              ),
            ),
            child: ClipOval(
              clipBehavior: Clip.hardEdge,
              child: Stack(
                alignment: Alignment.bottomCenter, // Align content to bottom
                children: [
                  // Orange fill
                  FractionallySizedBox(
                    alignment: Alignment.bottomCenter, // Align to the bottom
                    heightFactor: fillProportion,
                    child: Container(
                      width: double.infinity, // Fill the width
                      color: Colors.orangeAccent,
                    ),
                  ),
                  // Running man icon
                  Center(
                    child: Icon(
                      Icons.directions_run,
                      size: 30,
                      color: Colors.white,
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
}
