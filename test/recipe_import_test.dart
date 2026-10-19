import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/recipe_import.dart';

void main() {
  group('matchCalories', () {
    test('scales every macro to the screenshot calories', () {
      const ours = Macros(calories: 200, protein: 20, carbs: 10, fat: 8);
      final m = RecipeImport.matchCalories(ours, 300);
      expect(m.calories, closeTo(300, 1e-9));
      expect(m.protein, closeTo(30, 1e-9));
      expect(m.carbs, closeTo(15, 1e-9));
      expect(m.fat, closeTo(12, 1e-9));
    });

    test('keeps the macro split when scaling down', () {
      const ours = Macros(calories: 1000, protein: 50, carbs: 100, fat: 40);
      final m = RecipeImport.matchCalories(ours, 250);
      expect(m.protein / m.carbs, closeTo(0.5, 1e-9));
      expect(m.fat, closeTo(10, 1e-9));
    });

    test('with nothing of ours, just the calories', () {
      final m = RecipeImport.matchCalories(Macros.zero, 120);
      expect(m.calories, 120);
      expect(m.protein, 0);
    });

    test('ignores a nonsense target', () {
      const ours = Macros(calories: 100, protein: 5);
      expect(RecipeImport.matchCalories(ours, -5).calories, 100);
      expect(RecipeImport.matchCalories(ours, double.nan).calories, 100);
    });
  });

  group('compare', () {
    test('no screenshot calories', () {
      expect(RecipeImport.compare(100, null), ImportMatch.none);
    });
    test('within 10% is close', () {
      expect(RecipeImport.compare(108, 100), ImportMatch.close);
      expect(RecipeImport.compare(91, 100), ImportMatch.close);
    });
    test('10 to 30% is off', () {
      expect(RecipeImport.compare(120, 100), ImportMatch.off);
      expect(RecipeImport.compare(75, 100), ImportMatch.off);
    });
    test('over 30% is very different', () {
      expect(RecipeImport.compare(140, 100), ImportMatch.veryDifferent);
      expect(RecipeImport.compare(0, 100), ImportMatch.veryDifferent);
    });
    test('both zero is close', () {
      expect(RecipeImport.compare(0, 0), ImportMatch.close);
    });
  });

  test('percentDifference is signed and rounded', () {
    expect(RecipeImport.percentDifference(117, 100), 17);
    expect(RecipeImport.percentDifference(80, 100), -20);
    expect(RecipeImport.percentDifference(80, null), isNull);
  });

  test('ImportedLine reads the server JSON', () {
    final l = ImportedLine.fromJson({
      'query': ' 1000ml coconut milk ',
      'asWritten': 'coco 1,000.0 ml',
      'shownKcal': 199.6,
      'unclear': true,
    });
    expect(l.query, '1000ml coconut milk');
    expect(l.asWritten, 'coco 1,000.0 ml');
    expect(l.shownKcal, 200);
    expect(l.unclear, isTrue);

    final plain = ImportedLine.fromJson({'query': '1188g tofu'});
    expect(plain.asWritten, '1188g tofu');
    expect(plain.shownKcal, isNull);
    expect(plain.unclear, isFalse);
  });
}
