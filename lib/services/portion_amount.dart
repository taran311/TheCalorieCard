/// Changing how much of a food you had in grams, ounces, ml or fl oz, not
/// only in portions ("×1.5").
///
/// A portion like "30 g", "1 bar (45g)" or "1 can (330ml)" says how much one
/// portion weighs, so "45 g" of it is simply 45 / 30 = 1.5 portions. All the
/// maths is a multiplier of the portion as it was looked up, so it works
/// with everything that already scales foods.
library;

enum AmountUnit { portions, g, oz, ml, flOz }

/// How much one portion is: [amount] grams, or ml when [volume].
class PortionSize {
  final double amount;
  final bool volume;

  const PortionSize(this.amount, {required this.volume});

  @override
  bool operator ==(Object other) =>
      other is PortionSize &&
      (other.amount - amount).abs() < 1e-9 &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(amount, volume);

  @override
  String toString() => 'PortionSize($amount ${volume ? 'ml' : 'g'})';
}

class PortionAmount {
  PortionAmount._();

  static const gramsPerOz = 28.3495;

  /// UK fluid ounce.
  static const mlPerFlOz = 28.4131;

  // "fl oz" before "oz", "kg" before "g", so the longer unit wins. The
  // unit has to end the word: "1 large" isn't 1 litre.
  static final _size = RegExp(
    r'(?:^|[^A-Za-z0-9.])(\d+(?:[.,]\d+)?)\s*'
    r'(kg|kilograms?|g|grams?|gr|ml|millilitres?|milliliters?|cl|'
    r'l|litres?|liters?|fl\.?\s*oz|oz|ounces?)(?![A-Za-z])',
    caseSensitive: false,
  );

  /// How much one portion is, or null if the portion doesn't say ("1
  /// medium", "1 slice"). Uses the last amount given, so "1 bar (45g)" is
  /// 45 g.
  static PortionSize? sizeOf(String portion) {
    if (portion.contains('×')) return null; // already a multiple
    final matches = _size.allMatches(portion).toList();
    if (matches.isEmpty) return null;
    final m = matches.last;
    final n = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    if (n == null || !n.isFinite || n <= 0) return null;
    final unit = m.group(2)!.toLowerCase().replaceAll(RegExp(r'[\s.]'), '');
    switch (unit) {
      case 'kg':
      case 'kilogram':
      case 'kilograms':
        return PortionSize(n * 1000, volume: false);
      case 'g':
      case 'gr':
      case 'gram':
      case 'grams':
        return PortionSize(n, volume: false);
      case 'oz':
      case 'ounce':
      case 'ounces':
        return PortionSize(n * gramsPerOz, volume: false);
      case 'floz':
        return PortionSize(n * mlPerFlOz, volume: true);
      case 'cl':
        return PortionSize(n * 10, volume: true);
      case 'l':
      case 'litre':
      case 'litres':
      case 'liter':
      case 'liters':
        return PortionSize(n * 1000, volume: true);
      default: // ml
        return PortionSize(n, volume: true);
    }
  }

  /// [text] with any weights and volumes taken out: "40g surreal" is
  /// " surreal".
  static String withoutAmounts(String text) => text.replaceAll(_size, ' ');

  /// How many weights and volumes [text] mentions.
  static int amountsIn(String text) => _size.allMatches(text).length;

  /// The units the amount can be typed in: portions (if [portions]), then
  /// the metric unit and ounces. Just portions when the size isn't known.
  static List<AmountUnit> unitsFor(PortionSize? size, {bool portions = true}) {
    if (size == null) return const [AmountUnit.portions];
    return [
      if (portions) AmountUnit.portions,
      ...(size.volume
          ? const [AmountUnit.ml, AmountUnit.flOz]
          : const [AmountUnit.g, AmountUnit.oz]),
    ];
  }

  /// Grams or ml in one of [unit].
  static double _base(AmountUnit unit) => switch (unit) {
        AmountUnit.oz => gramsPerOz,
        AmountUnit.flOz => mlPerFlOz,
        _ => 1,
      };

  /// The multiplier for [value] in [unit] ("45" g of a 30 g portion is
  /// 1.5). Null if it can't be worked out.
  static double? multiplierFor(
      double value, AmountUnit unit, PortionSize? size) {
    if (!value.isFinite || value <= 0) return null;
    if (unit == AmountUnit.portions) return value;
    if (size == null) return null;
    return value * _base(unit) / size.amount;
  }

  /// [multiplier] portions written in [unit] (the other way round).
  static double valueFor(
      double multiplier, AmountUnit unit, PortionSize? size) {
    if (unit == AmountUnit.portions || size == null) return multiplier;
    return multiplier * size.amount / _base(unit);
  }

  /// A tidy number for the box: whole grams and ml, ounces to 0.1.
  static String format(double value, AmountUnit unit) {
    final places = switch (unit) {
      AmountUnit.g || AmountUnit.ml => value >= 10 ? 0 : 1,
      AmountUnit.oz || AmountUnit.flOz => value >= 100 ? 0 : 1,
      AmountUnit.portions => 2,
    };
    final s = value.toStringAsFixed(places);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  static String label(AmountUnit unit) => switch (unit) {
        AmountUnit.portions => 'portions',
        AmountUnit.g => 'g',
        AmountUnit.oz => 'oz',
        AmountUnit.ml => 'ml',
        AmountUnit.flOz => 'fl oz',
      };

  static final _plain =
      RegExp(r'^\s*(\d+(?:\.\d+)?)(\s*)(g|ml)\s*$', caseSensitive: false);

  /// The label for [multiplier] of [basePortion]: a plain weight or volume
  /// is scaled ("30 g" × 1.5 is "45 g"); anything else is "1.5 × 1 bar
  /// (45g)".
  static String scaledLabel(String basePortion, double multiplier) {
    if ((multiplier - 1).abs() < 1e-9) return basePortion;
    final plain = _plain.firstMatch(basePortion);
    if (plain != null) {
      final n = double.parse(plain.group(1)!) * multiplier;
      return '${format(n, AmountUnit.g)}${plain.group(2)}'
          '${plain.group(3)!.toLowerCase()}';
    }
    final m = _formatMultiple(multiplier);
    return basePortion.isEmpty ? '$m×' : '$m × $basePortion';
  }

  static String _formatMultiple(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    final s = value.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}
