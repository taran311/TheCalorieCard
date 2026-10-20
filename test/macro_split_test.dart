// Tests for the ready-made macro splits (Balanced, High protein, Low carb,
// Keto) on Goals and profile.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/goal_maths.dart';

void main() {
  test('each split adds up to the whole', () {
    for (final s in MacroSplit.presets) {
      expect(s.protein + s.carbs + s.fat, closeTo(1, 0.0001), reason: s.id);
    }
  });

  test('grams for a calorie goal come back to about those calories', () {
    for (final s in MacroSplit.presets) {
      final m = s.macrosFor(1350);
      final kcal = caloriesFromMacros(m.protein, m.carbs, m.fat);
      expect(kcal, closeTo(1350, 10), reason: s.id);
      expect(m.fat, greaterThan(0), reason: s.id);
    }
  });

  test('keto is very low carb and high fat', () {
    final keto = MacroSplit.presets.firstWhere((s) => s.id == 'keto');
    final m = keto.macrosFor(2000);
    expect(m.carbs, 25);
    expect(m.fat, closeTo(156, 1));
    expect(m.protein, 125);
  });

  test('a split is recognised from its grams', () {
    for (final s in MacroSplit.presets) {
      final m = s.macrosFor(1800);
      expect(MacroSplit.matching(m.protein, m.carbs, m.fat)?.id, s.id);
    }
    // 160/160/80 on 2000 kcal is about 32/32/36: none of them.
    expect(MacroSplit.matching(160, 160, 80), isNull);
    expect(MacroSplit.matching(0, 0, 0), isNull);
  });
}
