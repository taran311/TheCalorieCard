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
  /// semicolons all separate items.
  static List<String> splitItems(String text) => text
      .split(RegExp(r'[,\n;]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

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
        onProgress?.call(done, queries.length);
      }
    }

    await Future.wait([
      for (var w = 0; w < concurrency && w < queries.length; w++) worker(),
    ]);
    return results;
  }
}
