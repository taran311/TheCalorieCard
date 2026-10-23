// The calorie currency symbol (⊂, U+E000): written before amounts from
// the card's budget, like £ before money, and drawn by the bundled
// CalorieSymbol font.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/ui/calorie_symbol.dart';

void main() {
  test('the symbol is U+E000', () {
    expect(calSym, '');
  });

  test('amounts read like money: ⊂1,840 and −⊂412', () {
    expect(cals(1840), '1,840');
    expect(cals(-412), '−412');
    expect(cals(0), '0');
  });

  test("Coach's text is shown with the symbol, not kcal", () {
    expect(calText("You've got 640 kcal left today."),
        "You've got 640 left today.");
    expect(calText('About 1,200kcal a day'), 'About 1,200 a day');
    // Words that only contain "kcal" are left alone.
    expect(calText('kcalories'), 'kcalories');
  });

  test('the font is bundled in all three weights', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final w in ['Regular', 'SemiBold', 'Bold']) {
      final path = 'assets/fonts/CalorieSymbol-$w.ttf';
      expect(File(path).existsSync(), isTrue, reason: path);
      expect(pubspec, contains(path));
    }
    expect(pubspec, contains('family: CalorieSymbol'));
  });
}
