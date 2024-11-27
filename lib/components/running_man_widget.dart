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

  // Open input dialog to set steps
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
      onTap:
          widget.isActive ? _showInputDialog : null, // Disable tap if inactive
      child: Opacity(
        opacity: widget.isActive ? 1.0 : 0.5, // Dim if inactive
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Running Man Outline
            Container(
              width: 50, // Icon-sized
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2, // Outer border for visibility
                ),
              ),
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Orange fill
                    FractionallySizedBox(
                      heightFactor: fillProportion,
                      child: Container(
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
            // Steps Label
            Positioned(
              bottom: -10,
              child: Text(
                '$steps steps',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      blurRadius: 2,
                      color: Colors.black.withOpacity(0.7),
                      offset: Offset(0.5, 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
