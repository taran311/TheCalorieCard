// Tidying spoken food lists for the Add food box.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/voice_text.dart';

void main() {
  test('joins between foods become commas', () {
    expect(VoiceText.foodsFromSpeech('two eggs and a slice of toast and a flat white'),
        'two eggs, a slice of toast, a flat white');
    expect(VoiceText.foodsFromSpeech('porridge then a banana plus a coffee'),
        'porridge, a banana, a coffee');
    expect(VoiceText.foodsFromSpeech('chicken salad, and then a yoghurt.'),
        'chicken salad, a yoghurt');
  });

  test('dishes with "and" in the name stay together', () {
    expect(VoiceText.foodsFromSpeech('fish and chips and a can of coke'),
        'fish and chips, a can of coke');
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

  test('error messages', () {
    expect(VoiceText.errorMessage(null), isNull);
    expect(VoiceText.errorMessage('aborted'), isNull);
    expect(VoiceText.errorMessage('not-allowed'), contains('microphone'));
    expect(VoiceText.errorMessage('weird'), contains('try again'));
  });
}
