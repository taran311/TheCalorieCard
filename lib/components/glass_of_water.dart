import 'package:flutter/material.dart';

class GlassOfWaterWidget extends StatefulWidget {
  final ValueChanged<double> onWaterLevelChanged; // Callback for water updates
  final bool isActive; // Determines if the widget is active or disabled
  final double initialValue; // Initial water level

  GlassOfWaterWidget({
    required this.onWaterLevelChanged,
    this.isActive = true,
    this.initialValue = 0.0,
  });

  @override
  _GlassOfWaterWidgetState createState() => _GlassOfWaterWidgetState();
}

class _GlassOfWaterWidgetState extends State<GlassOfWaterWidget> {
  double inputValue = 0.0; // Water value in liters (0 to 5)
  final double maxLiters = 5.0; // Maximum liters for the glass

  @override
  void initState() {
    super.initState();
    inputValue = widget.initialValue; // Set initial value
  }

  // Open input dialog to set water level
  void _showInputDialog() {
    if (!widget.isActive) return; // Ignore taps if inactive

    final TextEditingController controller =
        TextEditingController(text: inputValue.toString());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            'Enter Water Level (liters)',
            style: TextStyle(color: Colors.blueAccent),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Enter a value (0 - 5)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel', style: TextStyle(color: Colors.blueAccent)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  inputValue = double.tryParse(controller.text) ?? 0.0;
                  inputValue = inputValue.clamp(0.0, maxLiters);
                  widget.onWaterLevelChanged(inputValue); // Notify parent
                });
                Navigator.of(context).pop();
              },
              child: Text('Submit', style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double fillProportion = (inputValue / maxLiters).clamp(0.0, 1.0);

    return GestureDetector(
      onTap:
          widget.isActive ? _showInputDialog : null, // Disable tap if inactive
      child: Opacity(
        opacity: widget.isActive ? 1.0 : 0.5, // Dim if inactive
        child: Container(
          width: 30, // Icon-sized glass
          height: 60,
          decoration: BoxDecoration(
            color: Colors.transparent, // Transparent background
            borderRadius: BorderRadius.circular(10), // Rounded glass edges
            border: Border.all(
              color: Colors.white, // Glass border
              width: 2,
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withOpacity(0.2), // Subtle glass gradient
                Colors.white.withOpacity(0.5),
              ],
            ),
          ),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Water fill
              FractionallySizedBox(
                heightFactor: fillProportion,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.lightBlueAccent.withOpacity(0.8),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                ),
              ),
              // Text showing current water level
              Positioned(
                bottom: 5,
                child: Text(
                  '${inputValue.toStringAsFixed(1)}L',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
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
      ),
    );
  }
}
