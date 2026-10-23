import 'package:flutter/material.dart';

/// The calorie currency symbol: a C drawn like the rounded edge of a card,
/// with a short stroke above and below, the way $ has. Calories are the
/// card's money, so balances read like money: ⊂1,840.
///
/// It isn't a character in any font, so it's drawn. Screen readers skip
/// it: put "calories" in the text's semantics label instead.
class CalorieSymbol extends StatelessWidget {
  /// The symbol's height, strokes included. About 1.2× the font size
  /// makes the C as tall as the digits beside it.
  final double size;
  final Color? color;

  const CalorieSymbol({super.key, this.size = 20, this.color});

  /// How wide the symbol is for a given height.
  static const widthRatio = 0.70;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    return ExcludeSemantics(
      child: SizedBox(
        width: size * widthRatio,
        height: size,
        child: CustomPaint(painter: _SymbolPainter(c)),
      ),
    );
  }
}

class _SymbolPainter extends CustomPainter {
  final Color color;
  _SymbolPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Designed in a 100×100 box; the drawn part runs from x 12 to 82.
    // The C's stroke matches extra-bold digits at this size.
    final s = size.height / 100;
    canvas.save();
    canvas.scale(s);
    canvas.translate(-12, 0);
    final card = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // The C: a card's rounded left edge, open on the right.
    final c = Path()
      ..moveTo(74, 20)
      ..lineTo(44, 20)
      ..arcToPoint(const Offset(22, 42),
          radius: const Radius.circular(22), clockwise: false)
      ..lineTo(22, 58)
      ..arcToPoint(const Offset(44, 80),
          radius: const Radius.circular(22), clockwise: false)
      ..lineTo(74, 80);
    canvas.drawPath(c, card);
    // The two short strokes, like a currency sign's.
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(48, 7), const Offset(48, 14), stroke);
    canvas.drawLine(const Offset(48, 86), const Offset(48, 93), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.color != color;
}
