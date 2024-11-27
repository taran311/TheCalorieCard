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
          Positioned(
            left: 6,
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
