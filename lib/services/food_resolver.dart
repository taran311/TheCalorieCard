import 'dart:convert';

import 'package:namer_app/services/proxy_client.dart';

/// Result of turning a line of text ("2 eggs") into nutrition.
class ResolvedFood {
  final String query;
  final String name;
  final String portion;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  /// "fatsecret" (database match) or "ai" (estimate).
  final String source;
  final double confidence;

  const ResolvedFood({
    required this.query,
    required this.name,
    required this.portion,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.source,
    required this.confidence,
  });

  bool get fromDatabase => source == 'fatsecret';

  /// Worth double-checking: an AI guess the model wasn't sure about, or
  /// zero calories (usually means the lookup failed).
  bool get needsReview => calories <= 0 || (!fromDatabase && confidence < 0.6);
}

class FoodResolver {
  FoodResolver._();

  /// Splits free text into separate foods: commas, new lines and
  /// semicolons all separate items. A comma between two digits is a
  /// decimal comma ("1,5 kg rice"), so it stays part of the food.
  static List<String> splitItems(String text) {
    final parts = <String>[];
    var start = 0;
    for (final i in [..._separators(text), text.length]) {
      final s = text.substring(start, i).trim();
      if (s.isNotEmpty) parts.add(s);
      start = i + 1;
    }
    return parts;
  }

  /// While someone is typing: the foods they've finished (followed by a
  /// separator) and the text they're still typing, untouched.
  ///
  /// A comma straight after a digit at the very end ("1,") might be the
  /// start of "1,5 kg", so it waits for the next character.
  static ({List<String> done, String rest}) takeFinished(String text) {
    final seps = _separators(text, waitOnTrailingDigitComma: true);
    if (seps.isEmpty) return (done: const <String>[], rest: text);
    final last = seps.last;
    return (
      done: splitItems(text.substring(0, last)),
      rest: text.substring(last + 1).trimLeft(),
    );
  }

  static bool _digit(int c) => c >= 0x30 && c <= 0x39;

  /// Positions of the characters that separate foods. Written by hand
  /// rather than with a look-behind regex, which older Safari can't run.
  static List<int> _separators(String text,
      {bool waitOnTrailingDigitComma = false}) {
    final out = <int>[];
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x0A || c == 0x3B) {
        // New line or semicolon.
        out.add(i);
        continue;
      }
      if (c != 0x2C) continue; // not a comma
      final digitBefore = i > 0 && _digit(text.codeUnitAt(i - 1));
      if (!digitBefore) {
        out.add(i);
      } else if (i + 1 < text.length) {
        if (!_digit(text.codeUnitAt(i + 1))) out.add(i);
      } else if (!waitOnTrailingDigitComma) {
        out.add(i);
      }
    }
    return out;
  }

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static String _fmt(dynamic v) {
    final d = _n(v);
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
  }

  /// Looks up one food. Throws on network/server errors.
  static Future<ResolvedFood> resolve(String query) async {
    final response = await ProxyClient.post('/food/resolve', {'food': query})
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('Lookup failed (${response.statusCode})');
    }
    final j = json.decode(response.body) as Map<String, dynamic>;

    final mode = j['mode'];
    String portion = '';
    if (mode == 'serving' && j['serving_description'] != null) {
      portion = j['serving_description'].toString();
    } else if (j['grams'] != null) {
      portion = '${_fmt(j['grams'])}g';
    } else if (j['ml'] != null) {
      portion = '${_fmt(j['ml'])}ml';
    }

    return ResolvedFood(
      query: query,
      name: (j['name'] ?? query).toString(),
      portion: portion,
      calories: _n(j['calories']),
      protein: _n(j['protein']),
      carbs: _n(j['carbs']),
      fat: _n(j['fat']),
      source: (j['source'] ?? 'ai').toString(),
      confidence: j['confidence'] is num ? _n(j['confidence']) : 0.7,
    );
  }

  /// Looks up several foods at once (a few at a time, to stay well inside
  /// the server's rate limit). Results keep the input order; failures are
  /// returned as null.
  static Future<List<ResolvedFood?>> resolveAll(
    List<String> queries, {
    int concurrency = 3,
    void Function(int done, int total)? onProgress,
    void Function(int index, ResolvedFood? result)? onResult,
  }) async {
    final results = List<ResolvedFood?>.filled(queries.length, null);
    var next = 0;
    var done = 0;

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= queries.length) return;
        try {
          results[i] = await resolve(queries[i]);
        } catch (_) {
          results[i] = null;
        }
        done++;
        onResult?.call(i, results[i]);
        onProgress?.call(done, queries.length);
      }
    }

    await Future.wait([
      for (var w = 0; w < concurrency && w < queries.length; w++) worker(),
    ]);
    return results;
  }

  /// Looks up a packaged food by its barcode. Returns null if the product
  /// isn't known; throws on network/server errors.
  static Future<ResolvedFood?> fromBarcode(String code) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    final response = await ProxyClient.get('/food/barcode',
            query: {'code': digits})
        .timeout(const Duration(seconds: 60));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('Barcode lookup failed (${response.statusCode})');
    }
    final j = json.decode(response.body) as Map<String, dynamic>;
    return ResolvedFood(
      query: digits,
      name: (j['name'] ?? 'Scanned product').toString(),
      portion: (j['portion'] ?? '').toString(),
      calories: _n(j['calories']),
      protein: _n(j['protein']),
      carbs: _n(j['carbs']),
      fat: _n(j['fat']),
      source: 'barcode',
      confidence: 1,
    );
  }

  /// Asks the AI what's in a meal photo. Returns food descriptions with
  /// portions ("150g grilled chicken breast") ready for [resolveAll].
  static Future<List<String>> foodsInPhoto(
      List<int> bytes, String mimeType) async {
    final response = await ProxyClient.post('/food/photo', {
      'image': base64Encode(bytes),
      'mime': mimeType,
    }).timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) {
      String message = "Couldn't read that photo";
      try {
        final err = json.decode(response.body);
        if (err is Map && err['error'] is String) message = err['error'];
      } catch (_) {}
      throw Exception(message);
    }
    final j = json.decode(response.body);
    final items = j is Map ? j['items'] : null;
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item.toString().trim().isNotEmpty) item.toString().trim()
    ];
  }
}
