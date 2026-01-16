import 'package:flutter/material.dart';

// Custom Widget for Calorie Currency Symbol
class CalorieCurrencyIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      width: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'C',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1,
            ),
          ),
          // Adjusted 'left' value to perfectly center the line
          Positioned(
            left: 5.25, // Fine-tuned to be between the earlier adjustments
            child: Container(
              width: 2,
              height: 18,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
