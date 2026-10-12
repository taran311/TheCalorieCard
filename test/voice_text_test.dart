// Tidying spoken food lists for the Add food box.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/voice_text.dart';

void main() {
  test('joins between foods become commas', () {
    expect(
        VoiceText.foodsFromSpeech(
            'two crumpets and a slice of toast and an oat latte'),
        'two crumpets, a slice of toast, an oat latte');
    expect(VoiceText.foodsFromSpeech('porridge then a banana plus a coffee'),
        'porridge, a banana, a coffee');
    expect(VoiceText.foodsFromSpeech('chickpea salad, and then a soya yoghurt.'),
        'chickpea salad, a soya yoghurt');
  });

  test('dishes with "and" in the name stay together', () {
    expect(VoiceText.foodsFromSpeech('rice and peas and a can of coke'),
        'rice and peas, a can of coke');
    expect(VoiceText.foodsFromSpeech('Salt and Vinegar crisps and an apple'),
        'Salt and Vinegar crisps, an apple');
    expect(VoiceText.foodsFromSpeech('a gin and tonic'), 'a gin and tonic');
  });

  test('words containing "and" are not split', () {
    expect(VoiceText.foodsFromSpeech('a sandwich and candy'),
        'a sandwich, candy');
    expect(VoiceText.foodsFromSpeech('brandy'), 'brandy');
  });

  test('empty and messy input', () {
    expect(VoiceText.foodsFromSpeech('   '), '');
    expect(VoiceText.foodsFromSpeech('and toast and'), 'toast');
  });

  test('a list read out without "and" splits at each amount', () {
    expect(VoiceText.foodsFromSpeech('50g of onions 50g of tomatoes 30g of cabbage'),
        '50g of onions, 50g of tomatoes, 30g of cabbage');
    expect(VoiceText.foodsFromSpeech('3 crumpets 2 slices of toast a coffee'),
        '3 crumpets, 2 slices of toast, a coffee');
    expect(
        VoiceText.foodsFromSpeech('two crumpets a slice of toast an oat latte'),
        'two crumpets, a slice of toast, an oat latte');
    expect(VoiceText.foodsFromSpeech('500ml oat milk 2 bananas'),
        '500ml oat milk, 2 bananas');
  });

  test('amounts themselves stay whole', () {
    expect(
        VoiceText.foodsFromSpeech(
            'one and a half cups of rice 200 grams of firm tofu'),
        'one and a half cups of rice, 200 grams of firm tofu');
    expect(
        VoiceText.foodsFromSpeech(
            'two hundred and fifty grams of pasta 2 tablespoons of olive oil'),
        'two hundred and fifty grams of pasta, 2 tablespoons of olive oil');
    expect(VoiceText.foodsFromSpeech('half a sandwich'), 'half a sandwich');
    expect(VoiceText.foodsFromSpeech('tofu with 2 crumpets'),
        'tofu with 2 crumpets');
    expect(VoiceText.foodsFromSpeech('toast with a bit of jam'),
        'toast with a bit of jam');
    expect(VoiceText.foodsFromSpeech('a can of 7up'), 'a can of 7up');
  });

  test('error messages', () {
    expect(VoiceText.errorMessage(null), isNull);
    expect(VoiceText.errorMessage('aborted'), isNull);
    expect(VoiceText.errorMessage('not-allowed'), contains('microphone'));
    expect(VoiceText.errorMessage('weird'), contains('try again'));
  });

  test('spots foods with no amount, for the accuracy tip', () {
    for (final f in [
      '150g pasta', '2 crumpets', 'a banana', 'an apple', 'bowl of cereal',
      'one slice toast', 'half an avocado', '330ml coke', 'large oat latte',
    ]) {
      expect(VoiceText.hasAmount(f), isTrue, reason: f);
    }
    for (final f in ['pasta', 'firm tofu', 'Tesco porridge oats']) {
      expect(VoiceText.hasAmount(f), isFalse, reason: f);
    }
  });
}
