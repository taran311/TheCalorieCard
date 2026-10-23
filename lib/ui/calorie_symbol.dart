import 'package:flutter/material.dart';

/// The calorie currency symbol: a C drawn like the rounded edge of a card,
/// with a short stroke above and below, the way $ has. Calories are the
/// card's money, so balances read like money: ⊂1,840.
///
/// It isn't a character in any font, so it's drawn. Screen readers skip
/// it: put "calories" in the text's semantics label instead.
class CalorieSymbol extends StatelessWidget {
  /// The symbol's height (about a capital letter's height plus strokes).
  final double size;
  final Color? color;

  const CalorieSymbol({super.key, this.size = 20, this.color});

  /// How wide the symbol is for a given height.
  static const widthRatio = 0.64;

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
    // Designed in a 100×100 box; the drawn part runs from x 16 to 80.
    final s = size.height / 100;
    canvas.save();
    canvas.scale(s);
    canvas.translate(-16, 0);
    final card = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // The C: a card's rounded left edge, open on the right.
    final c = Path()
      ..moveTo(74, 22)
      ..lineTo(44, 22)
      ..arcToPoint(const Offset(22, 44),
          radius: const Radius.circular(22), clockwise: false)
      ..lineTo(22, 56)
      ..arcToPoint(const Offset(44, 78),
          radius: const Radius.circular(22), clockwise: false)
      ..lineTo(74, 78);
    canvas.drawPath(c, card);
    // The two short strokes, like a currency sign's.
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(48, 6), const Offset(48, 16), stroke);
    canvas.drawLine(const Offset(48, 84), const Offset(48, 94), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.color != color;
}
