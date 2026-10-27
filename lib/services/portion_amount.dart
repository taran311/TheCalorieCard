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

  /// [name] with its one weight or volume multiplied [by], keeping the unit
  /// as written: "20g sriracha mayo" by 0.75 is "15g sriracha mayo". Null
  /// when the name gives no amount, or more than one (we can't tell which
  /// to change), so it's left as it is.
  static String? rescaleName(String name, double by) {
    if (!by.isFinite || by <= 0) return null;
    final matches = _size.allMatches(name).toList();
    if (matches.length != 1) return null;
    final m = matches.single;
    final digits = m.group(1)!;
    final n = double.tryParse(digits.replaceAll(',', '.'));
    if (n == null || !n.isFinite || n <= 0) return null;
    final value = n * by;
    var text = value.toStringAsFixed(value >= 10 ? 0 : 1);
    if (text.contains('.')) {
      text = text
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    if (text == '0') return null;
    final start = m.start + m.group(0)!.indexOf(digits);
    return name.replaceRange(start, start + digits.length, text);
  }

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

  /// A count at the start of a name ("4 linda mccartney sausages"), not a
  /// weight ("40g surreal", "250 ml oat milk").
  static final leadingCount = RegExp(
    r'^(\s*)(\d+(?:[.,]\d+)?)(\s+)(?!(?:g|kg|ml|l|cl|oz|lbs?|grams?|ounces?)\b)(?=\S)',
    caseSensitive: false,
  );

  /// [name] with its leading count multiplied [by] ("4 sausages" by 0.5 is
  /// "2 sausages"). Null when the name doesn't start with a count.
  static String? recount(String name, double by) {
    if (!by.isFinite || by <= 0 || (by - 1).abs() < 1e-9) return null;
    final m = leadingCount.firstMatch(name);
    if (m == null) return null;
    final n = double.tryParse(m.group(2)!.replaceAll(',', '.'));
    if (n == null || n <= 0) return null;
    return withCount(name, n * by);
  }

  /// [name] with its leading count set to [count]. Null without one.
  static String? withCount(String name, double count) {
    final m = leadingCount.firstMatch(name);
    if (m == null || !count.isFinite || count <= 0) return null;
    final shown = format(count, AmountUnit.portions);
    if (shown == '0') return null;
    return '${m.group(1)}$shown${m.group(3)}${name.substring(m.end)}';
  }

  /// How a food reads in a list, tidied from what was saved, so old
  /// entries read well too:
  ///  * "2 × 1 sausage (45g)" is "2 sausages · 90 g"
  ///  * "1.67 × 30g serving (shelled pistachios)" is "50 g"
  ///  * "Per 0.5 Servings" is "0.5 servings"
  ///  * a name that counts ("4 linda mccartney sausages") follows the
  ///    amount ("2 linda mccartney sausages") and is all that's shown;
  ///    "1 yubi protein bar" over "1 bar (35g)" is just the name
  ///  * the amount is left out when the name already says it ("200ml
  ///    Alpro soya milk" over "200 ml")
  static ({String name, String portion}) tidy(String name, String portion) {
    var p = portion.trim();
    var n = name;

    String? totalOf(double m, PortionSize? size) => size == null
        ? null
        : '${format(m * size.amount, size.volume ? AmountUnit.ml : AmountUnit.g)} '
            '${size.volume ? 'ml' : 'g'}';

    final per = _perServings.firstMatch(p);
    if (per != null) {
      final v = double.parse(per.group(1)!);
      p = '${format(v, AmountUnit.portions)} serving${v == 1 ? '' : 's'}';
    }

    final mult = _multiple.firstMatch(p);
    if (mult != null) {
      final m = double.parse(mult.group(1)!);
      final base = mult.group(2)!;
      final total = totalOf(m, sizeOf(base));
      final unit = _oneOf.firstMatch(base)?.group(1)?.trim();
      final weighed = amountsIn(n) == 1 &&
          sizeOf(base) != null &&
          sizeOf(n) == sizeOf(base);
      if (weighed) {
        // "40g surreal" at 1.5 × 40g is "60g surreal".
        n = rescaleName(n, m) ?? n;
        p = '';
      } else if (unit != null && unit.isNotEmpty && _names(n, unit)) {
        // The name counts the same thing, so it says how many, and that's
        // the amount shown (the weight is still there to switch to when
        // changing it).
        n = _numberName(withCount(n, m) ?? n, unit, m);
        p = '';
      } else if (unit != null && unit.isNotEmpty) {
        final u = m > 1 ? _plural(_lowerUnit(unit)) : _lowerUnit(unit);
        p = ['${format(m, AmountUnit.portions)} $u', if (total != null) total]
            .join(' · ');
      } else if (total != null) {
        p = total;
      }
    } else {
      // "1 yubi protein bar" over "1 bar (35g)": the name says it.
      final unit = _oneOf.firstMatch(p)?.group(1)?.trim();
      if (unit != null && _names(n, unit)) p = '';
      // "20g sriracha mayo" over "15g": an older entry whose amount was
      // changed without its name. The amount underneath is what was
      // logged, so the name says that.
      final plain = sizeOf(p);
      final inName = amountsIn(n) == 1 ? sizeOf(n) : null;
      if (_plainWeight.hasMatch(p) &&
          plain != null &&
          inName != null &&
          plain.volume == inName.volume &&
          plain != inName) {
        n = rescaleName(n, plain.amount / inName.amount) ?? n;
      }
    }

    // "200ml Alpro soya milk" over "200 ml" says it twice.
    final nameSize = amountsIn(n) == 1 ? sizeOf(n) : null;
    if (nameSize != null && nameSize == sizeOf(p)) p = '';
    return (name: n, portion: p);
  }

  static final _plainWeight = RegExp(
      r'^\s*\d+(?:[.,]\d+)?\s*(?:g|grams?|ml|millilitres?)\s*$',
      caseSensitive: false);
  static final _multiple =
      RegExp(r'^\s*(\d+(?:\.\d+)?)\s*×\s*(.*?)\s*$');
  static final _oneOf = RegExp(r'^\s*1\s+([^()]+?)\s*(\(.*\))?\s*$');
  static final _perServings = RegExp(
      r'^\s*Per\s+(\d+(?:\.\d+)?)\s+Servings?\s*$',
      caseSensitive: false);

  /// Whether [name] starts with a count of [unit]s: "4 linda mccartney
  /// sausages" counts "sausage"; "2 crumpets" doesn't count "serving".
  static bool _names(String name, String unit) {
    if (!leadingCount.hasMatch(name)) return false;
    final last = unit.toLowerCase().split(RegExp(r'\s+')).last;
    final stem = last.length > 3 && last.endsWith('s')
        ? last.substring(0, last.length - 1)
        : last;
    return stem.length >= 3 && name.toLowerCase().contains(stem);
  }

  /// "1 yubi protein bar" at 2 is "2 yubi protein bars"; "4 sausages" at
  /// 1 is "1 sausage". Only when the name ends with the thing counted.
  static String _numberName(String name, String unit, double count) {
    final words = name.trimRight().split(' ');
    final last = words.last;
    final stem = _singular(unit.toLowerCase().split(RegExp(r'\s+')).last);
    if (_singular(last).toLowerCase() != stem) return name;
    words[words.length - 1] =
        count > 1 ? _pluralWord(_singular(last)) : _singular(last);
    return words.join(' ');
  }

  /// "Hash brown" reads "hash brown" mid-label; "MCCAIN" stays.
  static String _lowerUnit(String unit) =>
      RegExp(r'[A-Z]{2}').hasMatch(unit) || unit.isEmpty
          ? unit
          : '${unit[0].toLowerCase()}${unit.substring(1)}';

  static const _unitWords = {'g', 'kg', 'ml', 'l', 'oz', 'lb', 'tbsp', 'tsp', 'cl'};
  static const _sizeWords = {
    'medium', 'large', 'small', 'whole', 'half', 'regular', 'big', 'mini',
    'extra', 'jumbo',
  };

  /// "sausage" → "sausages", "glass" → "glasses", "slice of toast" →
  /// "slices of toast"; "tbsp" and "medium" stay.
  static String _plural(String unit) {
    final words = unit.split(' ');
    final low = [for (final w in words) w.toLowerCase()];
    final of = low.indexOf('of', 1);
    final i = of > 0 ? of - 1 : words.length - 1;
    words[i] = _pluralWord(words[i]);
    return words.join(' ');
  }

  static String _pluralWord(String w) {
    final low = w.toLowerCase();
    if (_unitWords.contains(low) ||
        _sizeWords.contains(low) ||
        !RegExp(r'^[a-z]+$').hasMatch(low)) {
      return w;
    }
    if (low.endsWith('s') && !low.endsWith('ss')) return w;
    if (RegExp(r'(x|z|ch|sh|ss)$').hasMatch(low)) return '${w}es';
    if (RegExp(r'[^aeiou]y$').hasMatch(low)) {
      return '${w.substring(0, w.length - 1)}ies';
    }
    return '${w}s';
  }

  static String _singular(String w) {
    final low = w.toLowerCase();
    if (low.length > 4 && low.endsWith('ies')) {
      return '${w.substring(0, w.length - 3)}y';
    }
    if (RegExp(r'(xes|zes|ches|shes|sses)$').hasMatch(low)) {
      return w.substring(0, w.length - 2);
    }
    if (low.length > 3 && low.endsWith('s') && !low.endsWith('ss')) {
      return w.substring(0, w.length - 1);
    }
    return w;
  }

  static String _formatMultiple(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    final s = value.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}
