import 'package:namer_app/services/profile_limits.dart';

/// How someone likes to see their weight.
enum WeightUnit { kg, stLb, lb }

/// How someone likes to see their height.
enum HeightUnit { cm, ftIn }

/// Units for weight and height, picked separately (plenty of people weigh
/// in kg but give their height in feet). Everything is stored in kg and
/// cm, so the calorie maths never changes; this only affects what people
/// type and see.
///
/// Saved on the `user_data` profile as `weight_unit` ('kg' | 'st' | 'lb')
/// and `height_unit` ('cm' | 'ft'), plus the older `units` ('metric' |
/// 'imperial', following the weight) that earlier app versions read.
class UnitPrefs {
  final WeightUnit weight;
  final HeightUnit height;

  const UnitPrefs(this.weight, this.height);

  static const metric = UnitPrefs(WeightUnit.kg, HeightUnit.cm);
  static const imperialStones = UnitPrefs(WeightUnit.stLb, HeightUnit.ftIn);
  static const imperialPounds = UnitPrefs(WeightUnit.lb, HeightUnit.ftIn);

  /// Weight units offered, in the order shown.
  static const weightChoices = [WeightUnit.kg, WeightUnit.stLb, WeightUnit.lb];

  /// Height units offered, in the order shown.
  static const heightChoices = [HeightUnit.cm, HeightUnit.ftIn];

  /// Weight in kg (decides things like "0.5 kg a week").
  bool get isMetric => weight == WeightUnit.kg;

  UnitPrefs withWeight(WeightUnit w) => UnitPrefs(w, height);
  UnitPrefs withHeight(HeightUnit h) => UnitPrefs(weight, h);

  /// The older `units` field: follows the weight.
  String get unitsField => isMetric ? 'metric' : 'imperial';

  /// The `weight_unit` field.
  String get weightField => switch (weight) {
        WeightUnit.kg => 'kg',
        WeightUnit.stLb => 'st',
        WeightUnit.lb => 'lb',
      };

  /// The `height_unit` field.
  String get heightField => height == HeightUnit.cm ? 'cm' : 'ft';

  Map<String, dynamic> toFields() => {
        'units': unitsField,
        'weight_unit': weightField,
        'height_unit': heightField,
      };

  /// Picker labels.
  static String weightLabel(WeightUnit w) => switch (w) {
        WeightUnit.kg => 'kg',
        WeightUnit.stLb => 'st & lb',
        WeightUnit.lb => 'lb',
      };
  static String heightLabel(HeightUnit h) =>
      h == HeightUnit.cm ? 'cm' : 'ft & in';

  /// "Kilograms, feet and inches" for the profile.
  String get description {
    final w = switch (weight) {
      WeightUnit.kg => 'Kilograms',
      WeightUnit.stLb => 'Stones and pounds',
      WeightUnit.lb => 'Pounds',
    };
    return '$w, ${height == HeightUnit.cm ? 'centimetres' : 'feet and inches'}';
  }

  /// Reads the saved fields. Anything missing falls back to the older
  /// `units` field, then to the default for [countryCode].
  static UnitPrefs fromFields(Object? units, Object? weightUnit,
      {Object? heightUnit, String? countryCode}) {
    final local = forCountry(countryCode);
    final WeightUnit weight = switch (weightUnit) {
      'kg' => WeightUnit.kg,
      'st' => WeightUnit.stLb,
      'lb' => WeightUnit.lb,
      _ => units == 'metric'
          ? WeightUnit.kg
          : units == 'imperial'
              // Imperial without a weight unit: the local habit (stones
              // outside the US).
              ? (local.isMetric ? WeightUnit.stLb : local.weight)
              : local.weight,
    };
    // Before height had its own field, `units` covered both.
    final HeightUnit height = switch (heightUnit) {
      'cm' => HeightUnit.cm,
      'ft' => HeightUnit.ftIn,
      _ => units == 'metric'
          ? HeightUnit.cm
          : units == 'imperial'
              ? HeightUnit.ftIn
              : local.height,
    };
    return UnitPrefs(weight, height);
  }

  /// Reads `units` / `weight_unit` / `height_unit` from a `user_data`
  /// document.
  static UnitPrefs fromProfile(Map<String, dynamic>? data,
          {String? countryCode}) =>
      fromFields(data?['units'], data?['weight_unit'],
          heightUnit: data?['height_unit'], countryCode: countryCode);

  /// The default for a country (ISO code such as 'GB' or 'US').
  ///
  /// The US (and Liberia and Myanmar) use pounds and feet. Everywhere else,
  /// the UK included, starts on metric: the NHS, GPs and gyms weigh in kg,
  /// and anyone who thinks in stones is one tap away from switching.
  static UnitPrefs forCountry(String? countryCode) {
    final cc = (countryCode ?? '').toUpperCase();
    if (cc == 'US' || cc == 'LR' || cc == 'MM') return imperialPounds;
    return metric;
  }

  @override
  bool operator ==(Object other) =>
      other is UnitPrefs && other.weight == weight && other.height == height;

  @override
  int get hashCode => Object.hash(weight, height);

  @override
  String toString() => 'UnitPrefs($weightField, ${height.name})';
}

/// Conversion, parsing and formatting. Pure Dart, so it's easy to test.
class Units {
  Units._();

  static const double kgPerLb = 0.45359237;
  static const int lbPerStone = 14;
  static const double cmPerInch = 2.54;

  static double lbToKg(double lb) => lb * kgPerLb;
  static double kgToLb(double kg) => kg / kgPerLb;

  static double stLbToKg(double stones, double pounds) =>
      lbToKg(stones * lbPerStone + pounds);

  /// 72.5 kg -> 11 st 5.8 lb (pounds to one decimal place).
  static ({int st, double lb}) kgToStLb(double kg) {
    final total = roundTo(kgToLb(kg), 1);
    var st = (total / lbPerStone).floor();
    var lb = roundTo(total - st * lbPerStone, 1);
    if (lb >= lbPerStone) {
      st += 1;
      lb = roundTo(lb - lbPerStone, 1);
    }
    return (st: st, lb: lb);
  }

  static double feetInchesToCm(double feet, double inches) =>
      (feet * 12 + inches) * cmPerInch;

  /// 180 cm -> 5 ft 11 in (inches rounded to a whole number).
  static ({int ft, int inches}) cmToFeetInches(double cm) {
    final total = (cm / cmPerInch).round();
    return (ft: total ~/ 12, inches: total % 12);
  }

  static double roundTo(double value, int places) {
    var f = 1.0;
    for (var i = 0; i < places; i++) {
      f *= 10;
    }
    return (value * f).round() / f;
  }

  /// "72.5", "72,5" or " 72 " -> a number. Empty or nonsense -> null.
  static double? parseNumber(String text) {
    final t = text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    return v != null && v.isFinite ? v : null;
  }

  /// 72.0 -> "72", 72.46 -> "72.5" (up to [maxPlaces] decimals, no
  /// trailing zeros).
  static String formatNumber(double value, {int maxPlaces = 1}) {
    final r = roundTo(value, maxPlaces);
    if (r == r.roundToDouble()) return r.toStringAsFixed(0);
    var s = r.toStringAsFixed(maxPlaces);
    while (s.contains('.') && s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// "72.5 kg", "11 st 6 lb" or "159.8 lb".
  static String formatWeight(double kg, UnitPrefs units) {
    switch (units.weight) {
      case WeightUnit.kg:
        return '${formatNumber(kg)} kg';
      case WeightUnit.lb:
        return '${formatNumber(kgToLb(kg))} lb';
      case WeightUnit.stLb:
        final v = kgToStLb(kg);
        final lb = v.lb.round();
        // Rounding 13.6 lb up makes a whole stone.
        final st = lb >= lbPerStone ? v.st + 1 : v.st;
        final shownLb = lb >= lbPerStone ? 0 : lb;
        return '$st st $shownLb lb';
    }
  }

  /// A change such as "−1.2 kg", "+3 lb" or "−1 st 2 lb".
  static String formatWeightChange(double deltaKg, UnitPrefs units) {
    final sign = deltaKg < 0 ? '−' : (deltaKg > 0 ? '+' : '');
    final kg = deltaKg.abs();
    switch (units.weight) {
      case WeightUnit.kg:
        return '$sign${formatNumber(kg)} kg';
      case WeightUnit.lb:
        return '$sign${formatNumber(kgToLb(kg))} lb';
      case WeightUnit.stLb:
        final lb = kgToLb(kg);
        if (lb < lbPerStone) return '$sign${formatNumber(lb)} lb';
        final v = kgToStLb(kg);
        return '$sign${v.st} st ${v.lb.round()} lb';
    }
  }

  /// "0.4 kg" or "0.9 lb" for a weekly rate (stones people think in lb
  /// for small amounts).
  static String formatRate(double kgPerWeek, UnitPrefs units) {
    final kg = kgPerWeek.abs();
    if (units.isMetric) return '${formatNumber(kg)} kg';
    return '${formatNumber(kgToLb(kg))} lb';
  }

  /// "180 cm" or "5 ft 11 in".
  static String formatHeight(double cm, UnitPrefs units) {
    if (units.height == HeightUnit.cm) return '${cm.round()} cm';
    final v = cmToFeetInches(cm);
    return '${v.ft} ft ${v.inches} in';
  }

  /// The accepted weight range, in the person's units.
  static String weightRangeMessage(UnitPrefs units) {
    const minKg = ProfileLimits.minWeightKg;
    const maxKg = ProfileLimits.maxWeightKg;
    switch (units.weight) {
      case WeightUnit.kg:
        return 'Enter a weight between ${formatNumber(minKg)} and '
            '${formatNumber(maxKg)} kg';
      case WeightUnit.lb:
        return 'Enter a weight between ${kgToLb(minKg).ceil()} and '
            '${kgToLb(maxKg).floor()} lb';
      case WeightUnit.stLb:
        final lo = kgToLb(minKg).ceil();
        final hi = kgToLb(maxKg).floor();
        return 'Enter a weight between ${lo ~/ lbPerStone} st '
            '${lo % lbPerStone} lb and ${hi ~/ lbPerStone} st '
            '${hi % lbPerStone} lb';
    }
  }

  /// The accepted height range, in the person's units.
  static String heightRangeMessage(UnitPrefs units) {
    const minCm = ProfileLimits.minHeightCm;
    const maxCm = ProfileLimits.maxHeightCm;
    if (units.height == HeightUnit.cm) {
      return 'Enter a height between ${minCm.round()} and '
          '${maxCm.round()} cm';
    }
    final lo = (minCm / cmPerInch).ceil();
    final hi = (maxCm / cmPerInch).floor();
    return 'Enter a height between ${lo ~/ 12} ft ${lo % 12} in and '
        '${hi ~/ 12} ft ${hi % 12} in';
  }

  /// Weight as stored: kg to two decimal places (enough to turn back into
  /// the same stones and pounds).
  static double storeKg(double kg) => roundTo(kg, 2);

  /// Height as stored: cm to one decimal place (5 ft 10 in is 177.8 cm).
  static double storeCm(double cm) => roundTo(cm, 1);
}
