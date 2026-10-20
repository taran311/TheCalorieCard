import 'dart:async';
import 'dart:convert';

import 'package:namer_app/services/food_country.dart';
import 'package:namer_app/services/proxy_client.dart';

/// Result of turning a line of text ("2 crumpets") into nutrition.
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

  /// A quick first answer (the AI's estimate) while the full lookup is
  /// still checking the label; see [FoodResolver.resolveAll].
  final bool preliminary;

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
    this.preliminary = false,
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

  /// Looks up one food. Throws on network/server errors. [refresh]: skip
  /// (and replace) any answer the server had saved for it.
  static Future<ResolvedFood> resolve(String query,
      {bool refresh = false}) async {
    await FoodCountry.ensureLoaded();
    final response = await ProxyClient.post('/food/resolve', {
      'food': query,
      'country': FoodCountry.code,
      if (refresh) 'refresh': true,
    }).timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('Lookup failed (${response.statusCode})');
    }
    return _fromJson(query, json.decode(response.body) as Map<String, dynamic>);
  }

  /// A quick first answer while [resolve] is still working: the AI's
  /// estimate, or the real answer if the food was looked up before (then
  /// not [ResolvedFood.preliminary]). Null if there isn't one yet.
  static Future<ResolvedFood?> estimate(String query) async {
    try {
      await FoodCountry.ensureLoaded();
      final response = await ProxyClient.post('/food/estimate', {
        'food': query,
        'country': FoodCountry.code,
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final j = json.decode(response.body) as Map<String, dynamic>;
      final r = _fromJson(query, j, preliminary: j['final'] != true);
      return r.calories > 0 ? r : null;
    } catch (_) {
      return null;
    }
  }

  static ResolvedFood _fromJson(String query, Map<String, dynamic> j,
      {bool preliminary = false}) {
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
      preliminary: preliminary,
    );
  }

  /// Full lookups started by [resolveAll], by query, until they finish
  /// (and a little after): so a food added with its estimate can get its
  /// real numbers once they're in, even after Add food has closed.
  static final Map<String, Future<ResolvedFood?>> inFlight = {};

  /// After this long without an answer, [resolveAll] asks for a quick
  /// estimate to show meanwhile.
  static const estimateAfter = Duration(milliseconds: 2500);

  /// Where a looked-up answer came from (not a person's own numbers).
  static const lookupSources = {
    'fatsecret', 'ai', 'web', 'label', 'tables', 'saved',
  };

  /// Off in tests (no server).
  static bool reportEnabled = true;

  /// Tells the server someone fixed the calories of a looked-up food
  /// ([calories] for exactly [food] as typed, one portion). Saved answers
  /// several people correct are looked up afresh. Fire-and-forget.
  static void reportFix(String food, double calories) {
    if (!reportEnabled) return;
    if (food.trim().isEmpty || !calories.isFinite || calories < 0) return;
    ProxyClient.post('/food/feedback', {
      'food': food,
      'calories': calories,
      'country': FoodCountry.code,
    })
        .timeout(const Duration(seconds: 20))
        .then((_) {}, onError: (_) {});
  }

  /// Looks up several foods at once (a few at a time, to stay well inside
  /// the server's rate limit of 30 a minute). Results keep the input
  /// order; failures are returned as null.
  ///
  /// With [onEstimate], a food still being looked up after [estimateAfter]
  /// gets a quick estimate first (shown while the label is checked); its
  /// real answer still arrives through [onResult].
  static Future<List<ResolvedFood?>> resolveAll(
    List<String> queries, {
    int concurrency = 5,
    Set<String> refresh = const {},
    void Function(int done, int total)? onProgress,
    void Function(int index, ResolvedFood? result)? onResult,
    void Function(int index, ResolvedFood estimate)? onEstimate,
  }) async {
    final results = List<ResolvedFood?>.filled(queries.length, null);
    final finished = List<bool>.filled(queries.length, false);
    final completers = [
      for (final _ in queries) Completer<ResolvedFood?>(),
    ];
    for (var i = 0; i < queries.length; i++) {
      inFlight[queries[i]] = completers[i].future;
    }
    var next = 0;
    var done = 0;

    Timer? estimates;
    if (onEstimate != null) {
      estimates = Timer(estimateAfter, () {
        for (var i = 0; i < queries.length; i++) {
          if (finished[i]) continue;
          final index = i;
          estimate(queries[i]).then((e) {
            // (Not preliminary when it had been looked up before: then
            // it's the real answer, arriving early.)
            if (e != null && !finished[index]) onEstimate(index, e);
          });
        }
      });
    }

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= queries.length) return;
        try {
          results[i] = await resolve(queries[i],
              refresh: refresh.contains(queries[i]));
        } catch (_) {
          results[i] = null;
        }
        finished[i] = true;
        completers[i].complete(results[i]);
        done++;
        onResult?.call(i, results[i]);
        onProgress?.call(done, queries.length);
      }
    }

    await Future.wait([
      for (var w = 0; w < concurrency && w < queries.length; w++) worker(),
    ]);
    estimates?.cancel();
    // Kept a little while for foods added with their estimate.
    Timer(const Duration(minutes: 2), () {
      for (var i = 0; i < queries.length; i++) {
        if (identical(inFlight[queries[i]], completers[i].future)) {
          inFlight.remove(queries[i]);
        }
      }
    });
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
  /// portions ("150g grilled tofu") ready for [resolveAll].
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
