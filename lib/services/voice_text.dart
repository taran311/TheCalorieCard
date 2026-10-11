/// Tidies what speech recognition hears into the shape the Add food box
/// expects: one food per comma.
///
/// People say "two eggs and a slice of toast and a flat white", so "and",
/// "then", "plus" and "also" between foods become commas, but dishes that
/// have "and" in their name ("fish and chips", "salt and vinegar") are
/// left alone.
class VoiceText {
  VoiceText._();

  /// Dishes and flavours that contain "and" (lower case).
  static const keepTogether = [
    'fish and chips',
    'salt and vinegar',
    'cheese and onion',
    'mac and cheese',
    'macaroni and cheese',
    'bread and butter',
    'sweet and sour',
    'bangers and mash',
    'ham and cheese',
    'cheese and ham',
    'chicken and mushroom',
    'steak and kidney',
    'steak and ale',
    'gin and tonic',
    'rum and coke',
    'strawberries and cream',
    'peaches and cream',
    'cookies and cream',
    'peanut butter and jelly',
    'peanut butter and jam',
    'chilli and lime',
    'sweet chilli and lime',
    'salt and pepper',
    'tomato and basil',
    'leek and potato',
    'pea and ham',
    'cheese and tomato',
    'egg and cress',
    'bacon and egg',
    'sausage and egg',
    'chicken and bacon',
    'sweet and salty',
    'oats and honey',
    'fruit and nut',
  ];

  static final _joiner =
      RegExp(r'\s*(?:,\s*)?\b(?:and then|and also|and|then|plus|also)\b\s*',
          caseSensitive: false);

  /// "two eggs and toast then a coffee" → "two eggs, toast, a coffee".
  static String foodsFromSpeech(String spoken) {
    var text = spoken.trim();
    if (text.isEmpty) return text;

    // Protect "fish and chips" etc. with a placeholder that can't be split.
    final kept = <String>[];
    for (final dish in keepTogether) {
      final pattern = RegExp(r'\b' + RegExp.escape(dish) + r'\b',
          caseSensitive: false);
      text = text.replaceAllMapped(pattern, (m) {
        kept.add(m[0]!);
        return '\u0000${kept.length - 1}\u0000';
      });
    }

    text = text.replaceAll(_joiner, ', ');
    // Tidy: no doubled, leading or trailing commas.
    text = text
        .replaceAll(RegExp(r'(\s*,\s*)+'), ', ')
        .replaceAll(RegExp(r'^[,\s]+|[,\s.]+$'), '');

    return text.replaceAllMapped(
        RegExp('\u0000(\\d+)\u0000'), (m) => kept[int.parse(m[1]!)]);
  }

  /// A friendly message for a browser speech error code, or null when
  /// there's nothing to say (stopped on purpose).
  static String? errorMessage(String? code) => switch (code) {
        null || 'aborted' => null,
        'not-allowed' || 'service-not-allowed' =>
          'Allow microphone access in your browser to use voice.',
        'no-speech' => "Didn't hear anything. Tap the mic and try again.",
        'audio-capture' => 'No microphone found.',
        'network' => 'Voice needs an internet connection.',
        _ => 'Voice stopped. Tap the mic to try again.',
      };
}
