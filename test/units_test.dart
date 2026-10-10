import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/goal_maths.dart';
import 'package:namer_app/services/profile_limits.dart';
import 'package:namer_app/services/units.dart';

void main() {
  group('UnitPrefs', () {
    test('defaults: US is pounds, UK and others are metric', () {
      expect(UnitPrefs.forCountry('US'), UnitPrefs.imperialPounds);
      expect(UnitPrefs.forCountry('us'), UnitPrefs.imperialPounds);
      expect(UnitPrefs.forCountry('GB'), UnitPrefs.metric);
      expect(UnitPrefs.forCountry('FR'), UnitPrefs.metric);
      expect(UnitPrefs.forCountry(null), UnitPrefs.metric);
    });

    test('reads and writes the profile fields', () {
      for (final u in UnitPrefs.choices) {
        final f = u.toFields();
        expect(UnitPrefs.fromFields(f['units'], f['weight_unit']), u);
      }
      expect(UnitPrefs.metric.toFields(),
          {'units': 'metric', 'weight_unit': 'kg'});
      expect(UnitPrefs.imperialStones.toFields(),
          {'units': 'imperial', 'weight_unit': 'st'});
    });

    test('nothing saved falls back to the country', () {
      expect(UnitPrefs.fromProfile({}, countryCode: 'US'),
          UnitPrefs.imperialPounds);
      expect(UnitPrefs.fromProfile(null, countryCode: 'GB'), UnitPrefs.metric);
      // Imperial with no weight unit: stones outside the US.
      expect(UnitPrefs.fromFields('imperial', null, countryCode: 'GB'),
          UnitPrefs.imperialStones);
      expect(UnitPrefs.fromFields('imperial', null, countryCode: 'US'),
          UnitPrefs.imperialPounds);
    });
  });

  group('conversions', () {
    test('pounds and kilograms', () {
      expect(Units.lbToKg(1), closeTo(0.45359237, 1e-9));
      expect(Units.kgToLb(Units.lbToKg(160)), closeTo(160, 1e-9));
    });

    test('stones and pounds round-trip through stored kg', () {
      final kg = Units.storeKg(Units.stLbToKg(11, 4));
      final back = Units.kgToStLb(kg);
      expect(back.st, 11);
      expect(back.lb, closeTo(4, 0.05));
    });

    test('13.96 lb rounds up to a whole stone', () {
      final kg = Units.stLbToKg(10, 13.96);
      final v = Units.kgToStLb(kg);
      expect(v.st, 11);
      expect(v.lb, 0);
      expect(Units.formatWeight(kg, UnitPrefs.imperialStones), '11 st 0 lb');
    });

    test('feet and inches', () {
      expect(Units.feetInchesToCm(5, 10), closeTo(177.8, 1e-9));
      final fi = Units.cmToFeetInches(180);
      expect(fi.ft, 5);
      expect(fi.inches, 11);
      // 5 ft 10 in survives being stored to 1 decimal place.
      final back = Units.cmToFeetInches(Units.storeCm(177.8));
      expect(back.ft, 5);
      expect(back.inches, 10);
    });
  });

  group('parsing and formatting', () {
    test('parseNumber accepts decimals with a point or comma', () {
      expect(Units.parseNumber('72.5'), 72.5);
      expect(Units.parseNumber(' 72,5 '), 72.5);
      expect(Units.parseNumber('30'), 30);
      expect(Units.parseNumber(''), isNull);
      expect(Units.parseNumber('abc'), isNull);
      expect(Units.parseNumber('.'), isNull);
    });

    test('formatNumber drops trailing zeros', () {
      expect(Units.formatNumber(72.0), '72');
      expect(Units.formatNumber(72.46), '72.5');
      expect(Units.formatNumber(72.04), '72');
      expect(Units.formatNumber(1.25, maxPlaces: 2), '1.25');
    });

    test('formatWeight in each unit', () {
      expect(Units.formatWeight(72.5, UnitPrefs.metric), '72.5 kg');
      expect(Units.formatWeight(Units.lbToKg(160), UnitPrefs.imperialPounds),
          '160 lb');
      expect(
          Units.formatWeight(
              Units.stLbToKg(11, 6), UnitPrefs.imperialStones),
          '11 st 6 lb');
    });

    test('formatWeightChange has a sign', () {
      expect(Units.formatWeightChange(-1.2, UnitPrefs.metric), '−1.2 kg');
      expect(Units.formatWeightChange(0.5, UnitPrefs.metric), '+0.5 kg');
      expect(Units.formatWeightChange(Units.lbToKg(-3), UnitPrefs.imperialStones),
          '−3 lb');
      expect(
          Units.formatWeightChange(
              Units.lbToKg(-16), UnitPrefs.imperialStones),
          '−1 st 2 lb');
    });

    test('formatHeight', () {
      expect(Units.formatHeight(180, UnitPrefs.metric), '180 cm');
      expect(Units.formatHeight(180, UnitPrefs.imperialStones), '5 ft 11 in');
    });

    test('range messages stay inside the limits', () {
      expect(Units.weightRangeMessage(UnitPrefs.metric),
          'Enter a weight between 30 and 350 kg');
      expect(Units.heightRangeMessage(UnitPrefs.metric),
          'Enter a height between 100 and 250 cm');
      expect(Units.heightRangeMessage(UnitPrefs.imperialPounds),
          'Enter a height between 3 ft 4 in and 8 ft 2 in');
      expect(Units.weightRangeMessage(UnitPrefs.imperialPounds),
          'Enter a weight between 67 and 771 lb');
      expect(Units.weightRangeMessage(UnitPrefs.imperialStones),
          'Enter a weight between 4 st 11 lb and 55 st 1 lb');
    });
  });

  group('ProfileLimits', () {
    test('ages, heights and weights at the edges', () {
      expect(ProfileLimits.ageOk(13), isTrue);
      expect(ProfileLimits.ageOk(12), isFalse);
      expect(ProfileLimits.ageOk(120), isTrue);
      expect(ProfileLimits.ageOk(null), isFalse);
      expect(ProfileLimits.heightOk(100), isTrue);
      expect(ProfileLimits.heightOk(99.9), isFalse);
      expect(ProfileLimits.weightOk(72.5), isTrue);
      expect(ProfileLimits.weightOk(350.1), isFalse);
    });
  });

  group('goal maths', () {
    test('lose never goes below the safe minimum', () {
      // A small, inactive woman: 15% under maintenance would be ~1,080.
      final rest = restingCalories(
          age: 60, heightCm: 150, weightKg: 50, male: false)!;
      final maintenance = maintenanceCalories(
          age: 60,
          heightCm: 150,
          weightKg: 50,
          male: false,
          exerciseLevel: 0)!;
      final floor = safeMinimumCalories(male: false, resting: rest);
      expect(floor, 1200);
      expect(suggestedCalorieGoal(maintenance, 'lose', floor: floor), 1200);
    });

    test('men have a 1,500 kcal floor, and resting calories can be higher',
        () {
      expect(safeMinimumCalories(male: true), 1500);
      expect(safeMinimumCalories(male: true, resting: 1800), 1800);
    });

    test('lose is 15% under maintenance when that is safe', () {
      expect(suggestedCalorieGoal(3000, 'lose', floor: 1500), 2550);
      expect(suggestedCalorieGoal(3000, 'maintain'), 3000);
      expect(suggestedCalorieGoal(3000, 'gain'), 3450);
    });

    test('scaling macros keeps the split', () {
      const current =
          Macros(calories: 2000, protein: 200, carbs: 150, fat: 67);
      final scaled = macrosScaledTo(current, 1600);
      expect(scaled.calories, 1600);
      expect(scaled.protein / scaled.carbs, closeTo(200 / 150, 0.02));
      expect(
          caloriesFromMacros(scaled.protein, scaled.carbs, scaled.fat),
          closeTo(1600, 15));
    });

    test('no macros to scale: the default split', () {
      final scaled = macrosScaledTo(Macros.zero, 2000);
      expect(scaled.protein, 150);
      expect(scaled.carbs, 200);
      expect(scaled.fat, 67);
    });

    test("Coach's lose target is raised to the floor", () {
      final t = withSafeLoseTarget({
        'lose': {'calories': 1000, 'protein_g': 100, 'carbs_g': 75, 'fat_g': 33},
        'maintain': {'calories': 1400},
      }, 1200);
      expect(t['lose']['calories'], 1200);
      expect(t['lose']['protein_g'], greaterThan(100));
      expect(t['maintain']['calories'], 1400);
      final untouched = withSafeLoseTarget({
        'lose': {'calories': 1800},
      }, 1200);
      expect(untouched['lose']['calories'], 1800);
    });
  });
}
