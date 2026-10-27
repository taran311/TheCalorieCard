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

  group('rescaleName', () {
    test('changes the one amount in the name', () {
      expect(PortionAmount.rescaleName('20g sriracha mayo', 0.75),
          '15g sriracha mayo');
      expect(PortionAmount.rescaleName('alpro no sugars plain 100g', 2),
          'alpro no sugars plain 200g');
      expect(PortionAmount.rescaleName('tofoo tofu 280 g', 0.5),
          'tofoo tofu 140 g');
      expect(PortionAmount.rescaleName('250ml oat milk', 1.5), '375ml oat milk');
    });

    test('small amounts keep a decimal', () {
      expect(PortionAmount.rescaleName('1kg potatoes', 0.25), '0.3kg potatoes');
      expect(PortionAmount.rescaleName('2.5g salt', 2), '5g salt');
    });

    test('leaves names without exactly one amount alone', () {
      expect(PortionAmount.rescaleName('1 yubi protein bar', 2), isNull);
      expect(PortionAmount.rescaleName('100g oats and 200ml oat milk', 2),
          isNull);
      expect(PortionAmount.rescaleName('20g mayo', 0), isNull);
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
  group('PortionAmount.tidy', () {
    String show(String name, String portion) {
      final t = PortionAmount.tidy(name, portion);
      return t.portion.isEmpty ? t.name : '${t.name} | ${t.portion}';
    }

    test('a counted name follows the amount and says it all', () {
      expect(show('4 linda mccartney sausages', '2 × 1 sausage (45g)'),
          '2 linda mccartney sausages');
      expect(show('4 linda mccartney sausages', '1 × 1 sausage (45g)'),
          '1 linda mccartney sausage');
      expect(show('1 yubi protein bar', '2 × 1 bar (35g)'),
          '2 yubi protein bars');
      expect(show('1 yubi protein bar', '1 bar (35g)'), '1 yubi protein bar');
    });

    test('"N × 1 thing (weight)" reads as a count and the total', () {
      expect(show('McCain Crispy Hash Browns', '3 × 1 Hash brown (45 g)'),
          'McCain Crispy Hash Browns | 3 hash browns · 135 g');
      expect(show('oat milk', '2 × 1 glass (250ml)'),
          'oat milk | 2 glasses · 500 ml');
      expect(show('toast', '2 × 1 slice of toast'), 'toast | 2 slices of toast');
      expect(show('banana', '2 × 1 medium'), 'banana | 2 medium');
      expect(show('peanut butter', '1.5 × 1 tbsp (16g)'),
          'peanut butter | 1.5 tbsp · 24 g');
      expect(show('crisps', '0.5 × 1 bag (25g)'), 'crisps | 0.5 bag · 13 g');
    });

    test('a multiple of a weighed serving is just the weight', () {
      expect(
          show('Amazon Pistachios', '1.67 × 30g serving (shelled pistachios)'),
          'Amazon Pistachios | 50 g');
    });

    test('recipe servings and amounts the name already gives', () {
      expect(show('Recipe: tofu scramble', 'Per 0.5 Servings'),
          'Recipe: tofu scramble | 0.5 servings');
      expect(show('Recipe: tofu scramble', 'Per 1 Serving'),
          'Recipe: tofu scramble | 1 serving');
      expect(show('heinz baked beans 300g', '300 g'), 'heinz baked beans 300g');
      expect(show('200ml Alpro Soya Milk', '200 ml'), '200ml Alpro Soya Milk');
      expect(show('Recipe: chilli', '450 g'), 'Recipe: chilli | 450 g');
    });

    test("a count of something else isn't changed", () {
      // One serving is 2 crumpets: the name can't follow servings.
      expect(show('2 crumpets', '3 × 1 serving (2 crumpets)'),
          '2 crumpets | 3 servings');
      expect(show('40g surreal', '1.5 × 40g'), '60g surreal');
      // An old entry: amount changed to 15 g, name left at 20g.
      expect(show('20g sriracha mayo', '15g'), '15g sriracha mayo');
      expect(show('20g sriracha mayo', '0.75 × 20g'), '15g sriracha mayo');
      expect(show('200ml oat milk', '150 ml'), '150ml oat milk');
    });
  });
}
