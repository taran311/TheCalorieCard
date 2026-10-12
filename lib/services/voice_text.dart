/// Tidies what speech recognition hears into the shape the Add food box
/// expects: one food per comma.
///
/// People say "two eggs and a slice of toast and a flat white", so "and",
/// "then", "plus" and "also" between foods become commas, but dishes that
/// have "and" in their name ("fish and chips", "salt and vinegar") are
/// left alone. Reading out a list without "and" ("50g of onions 50g of
/// tomatoes 30g of cabbage") is split where each new amount starts.
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

    // Amounts with "and" in them ("one and a half", "two hundred and
    // fifty") aren't two foods either.
    // Marked with \u0001 so the amount splitter reads it as a number.
    text = text.replaceAllMapped(_numberAnd, (m) {
      kept.add(m[0]!);
      return '\u0001${kept.length - 1}\u0001';
    });

    text = text.replaceAll(_joiner, ', ');
    text = text.split(',').map(_splitAtAmounts).join(', ');
    // Tidy: no doubled, leading or trailing commas.
    text = text
        .replaceAll(RegExp(r'(\s*,\s*)+'), ', ')
        .replaceAll(RegExp(r'^[,\s]+|[,\s.]+$'), '');

    return text.replaceAllMapped(
        RegExp('[\u0000\u0001](\\d+)[\u0000\u0001]'),
        (m) => kept[int.parse(m[1]!)]);
  }

  static final _numberAnd = RegExp(
      r'\b(?:and (?:a|one) (?:half|quarter)|and three quarters|hundred and)\b',
      caseSensitive: false);

  static const _numberWords = {
    'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
    'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
    'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty', 'forty',
    'fifty', 'sixty', 'seventy', 'eighty', 'ninety', 'hundred', 'thousand',
    'half', 'dozen',
  };

  /// Units and containers: part of an amount, not the food.
  static const _units = {
    'g', 'gram', 'grams', 'gramme', 'grammes', 'kg', 'kilo', 'kilos',
    'kilogram', 'kilograms', 'ml', 'millilitre', 'millilitres',
    'milliliter', 'milliliters', 'l', 'litre', 'litres', 'liter', 'liters',
    'cl', 'oz', 'ounce', 'ounces', 'lb', 'lbs', 'pound', 'pounds',
    'tbsp', 'tablespoon', 'tablespoons', 'tsp', 'teaspoon', 'teaspoons',
    'cup', 'cups', 'mug', 'mugs', 'slice', 'slices', 'piece', 'pieces',
    'handful', 'handfuls', 'pinch', 'tin', 'tins', 'can', 'cans', 'pack',
    'packs', 'packet', 'packets', 'bag', 'bags', 'bowl', 'bowls', 'glass',
    'glasses', 'pint', 'pints', 'clove', 'cloves', 'scoop', 'scoops',
    'bar', 'bars', 'portion', 'portions', 'serving', 'servings', 'bottle',
    'bottles', 'shot', 'shots', 'splash', 'knob', 'large', 'small',
    'medium',
  };

  /// Small words that belong to whatever's around them.
  static const _filler = {'of', 'a', 'an', 'the', 'x'};

  /// "with 2 eggs" or "on a plate": an amount after these isn't a new food.
  static const _linkers = {
    'with', 'without', 'of', 'on', 'in', 'into', 'for', 'from', 'to',
    'over', 'under', 'like', 'per',
  };

  static final _numberToken =
      RegExp(r'^\d+(?:[.,]\d+)?(?:g|kg|ml|l|cl|oz|lb|lbs)?$', caseSensitive: false);

  static bool _isNumber(String w) =>
      _numberToken.hasMatch(w) ||
      _numberWords.contains(w.toLowerCase()) ||
      w.startsWith('\u0001');

  /// One spoken stretch → foods, split where a new amount starts once the
  /// current food has been named: "50g of onions 50g of tomatoes" → "50g
  /// of onions, 50g of tomatoes".
  static String _splitAtAmounts(String part) {
    final words = part.trim().split(RegExp(r'\s+'));
    if (words.length < 3) return part.trim();
    final items = <List<String>>[[]];
    var named = false; // the current item has a food word in it
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final lower = w.toLowerCase();
      final prev = i > 0 ? words[i - 1].toLowerCase() : '';
      final next = i + 1 < words.length ? words[i + 1].toLowerCase() : '';
      final startsAmount = _isNumber(w) ||
          ((lower == 'a' || lower == 'an') &&
              (_units.contains(next) || !_filler.contains(next)));
      final prevIsAmount = _isNumber(prev) || prev == 'a' || prev == 'an';
      if (startsAmount &&
          named &&
          !prevIsAmount &&
          !_linkers.contains(prev)) {
        items.add([]);
        named = false;
      }
      items.last.add(w);
      if (!_isNumber(w) &&
          !_units.contains(lower) &&
          !_filler.contains(lower)) {
        named = true;
      }
    }
    return items
        .where((i) => i.isNotEmpty)
        .map((i) => i.join(' '))
        .join(', ');
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
