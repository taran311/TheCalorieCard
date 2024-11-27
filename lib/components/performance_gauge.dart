// PerformanceGauge and PerformanceGaugePainter are unchanged and included.
import 'dart:math';

import 'package:flutter/material.dart';

class PerformanceGauge extends StatelessWidget {
  final double value; // Value between 0 and 100

  const PerformanceGauge({Key? key, required this.value}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(50, 25), // Match widget size with others
      painter: PerformanceGaugePainter(value),
    );
  }
}

class PerformanceGaugePainter extends CustomPainter {
  final double value; // Value between 0 and 100

  PerformanceGaugePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height;
    final radius = size.width / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;

    // Red section
    paint.color = Colors.red;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
      pi,
      pi / 3,
      false,
      paint,
    );

    // Yellow section
    paint.color = Colors.yellow;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
      pi + (pi / 3),
      pi / 3,
      false,
      paint,
    );

    // Green section
    paint.color = Colors.green;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
      pi + (2 * pi / 3),
      pi / 3,
      false,
      paint,
    );

    // Draw the needle
    final angle = pi + (value / 100) * pi;
    final needleX = centerX + (radius - 5) * cos(angle); // Adjust needle length
    final needleY = centerY + (radius - 5) * sin(angle);

    final needlePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2; // Needle thickness

    canvas.drawLine(
        Offset(centerX, centerY), Offset(needleX, needleY), needlePaint);

    // Draw the needle pivot (center circle)
    final pivotPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
        Offset(centerX, centerY), 3, pivotPaint); // Small circle at the base
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
