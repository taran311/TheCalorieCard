import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/portion_amount.dart';
import 'package:namer_app/ui/amount_field.dart';

void main() {
  group('PortionAmount.sizeOf', () {
    test('reads the weight or volume of one portion', () {
      expect(PortionAmount.sizeOf('30 g'), const PortionSize(30, volume: false));
      expect(PortionAmount.sizeOf('30g'), const PortionSize(30, volume: false));
      expect(PortionAmount.sizeOf('1 bar (45g)'),
          const PortionSize(45, volume: false));
      expect(PortionAmount.sizeOf('1 can (330ml)'),
          const PortionSize(330, volume: true));
      expect(PortionAmount.sizeOf('1.5 l'), const PortionSize(1500, volume: true));
      expect(PortionAmount.sizeOf('1 kg'), const PortionSize(1000, volume: false));
      expect(PortionAmount.sizeOf('2 oz')!.amount, closeTo(56.7, 0.01));
      final floz = PortionAmount.sizeOf('8 fl oz')!;
      expect(floz.volume, isTrue);
      expect(floz.amount, closeTo(227.3, 0.1));
    });

    test("nothing to go on: just portions", () {
      expect(PortionAmount.sizeOf('1 medium'), isNull);
      expect(PortionAmount.sizeOf('1 large'), isNull); // not 1 litre
      expect(PortionAmount.sizeOf('1 slice'), isNull);
      expect(PortionAmount.sizeOf(''), isNull);
      expect(PortionAmount.sizeOf('2 × 30 g'), isNull);
      expect(PortionAmount.unitsFor(null), [AmountUnit.portions]);
    });
  });

  group('amounts in grams and ounces', () {
    const pistachios = PortionSize(30, volume: false);

    test('45 g of a 30 g portion is 1.5 portions', () {
      expect(PortionAmount.multiplierFor(45, AmountUnit.g, pistachios), 1.5);
      expect(PortionAmount.multiplierFor(2, AmountUnit.portions, pistachios), 2);
      expect(PortionAmount.multiplierFor(1, AmountUnit.oz, pistachios),
          closeTo(28.3495 / 30, 1e-9));
      expect(PortionAmount.multiplierFor(0, AmountUnit.g, pistachios), isNull);
    });

    test('and back again', () {
      expect(PortionAmount.valueFor(1.5, AmountUnit.g, pistachios), 45);
      expect(PortionAmount.format(
              PortionAmount.valueFor(1, AmountUnit.oz, pistachios),
              AmountUnit.oz),
          '1.1');
    });

    test('units offered', () {
      expect(PortionAmount.unitsFor(pistachios),
          [AmountUnit.portions, AmountUnit.g, AmountUnit.oz]);
      expect(PortionAmount.unitsFor(const PortionSize(330, volume: true)),
          [AmountUnit.portions, AmountUnit.ml, AmountUnit.flOz]);
      expect(PortionAmount.unitsFor(pistachios, portions: false),
          [AmountUnit.g, AmountUnit.oz]);
    });
  });

  group('PortionAmount.scaledLabel', () {
    test('a plain weight is scaled, anything else is a multiple', () {
      expect(PortionAmount.scaledLabel('30 g', 1.5), '45 g');
      expect(PortionAmount.scaledLabel('330ml', 2), '660ml');
      expect(PortionAmount.scaledLabel('1 slice', 2), '2 × 1 slice');
      expect(PortionAmount.scaledLabel('1 bar (45g)', 0.5), '0.5 × 1 bar (45g)');
      expect(PortionAmount.scaledLabel('30 g', 1), '30 g');
      expect(PortionAmount.scaledLabel('', 2), '2×');
    });
  });

  group('AmountInput', () {
    test('switching unit keeps the same amount', () {
      final input = AmountInput(basePortion: '30 g', multiplier: 1.5);
      expect(input.unit, AmountUnit.portions);
      expect(input.controller.text, '1.5');
      input.setUnit(AmountUnit.g);
      expect(input.controller.text, '45');
      expect(input.multiplier, 1.5);
      input.controller.text = '60';
      expect(input.multiplier, 2);
      expect(input.equivalent(2, '30 g'), '2 × 30 g');
      input.setUnit(AmountUnit.oz);
      expect(input.controller.text, '2.1');
      expect(input.equivalent(2, '30 g'), '60 g');
      input.dispose();
    });

    test('per 100 g starts in grams, with no portions', () {
      final input = AmountInput(
          basePortion: '100 g', multiplier: 2.5, allowPortions: false);
      expect(input.units, [AmountUnit.g, AmountUnit.oz]);
      expect(input.controller.text, '250');
      expect(input.multiplier, 2.5);
      input.dispose();
    });
  });
}
