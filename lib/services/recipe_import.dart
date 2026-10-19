import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/proxy_client.dart';

/// One ingredient line read from a recipe image.
@immutable
class ImportedLine {
  /// What we'll look up, e.g. "1000ml coconut milk".
  final String query;

  /// The line as it appeared in the image, e.g. "coco 1,000.0 ml".
  final String asWritten;

  /// Calories printed beside it in the image, if any. Only for comparing;
  /// never used unless the person chooses to.
  final int? shownKcal;

  /// The name was abbreviated or unclear, so the reading is a guess.
  final bool unclear;

  const ImportedLine({
    required this.query,
    required this.asWritten,
    this.shownKcal,
    this.unclear = false,
  });

  factory ImportedLine.fromJson(Map j) => ImportedLine(
        query: '${j['query'] ?? ''}'.trim(),
        asWritten: '${j['asWritten'] ?? j['query'] ?? ''}'.trim(),
        shownKcal: j['shownKcal'] is num ? (j['shownKcal'] as num).round() : null,
        unclear: j['unclear'] == true,
      );
}

/// What was read from the images.
@immutable
class RecipeImportResult {
  final String title;
  final double? servings;
  final List<ImportedLine> lines;

  const RecipeImportResult({
    this.title = '',
    this.servings,
    this.lines = const [],
  });
}

/// An ingredient ready to go into the recipe.
@immutable
class ImportedIngredient {
  final String name;
  final Macros macros;
  final String portion;

  const ImportedIngredient({
    required this.name,
    required this.macros,
    this.portion = '',
  });
}

/// How close our lookup is to the screenshot's calories.
enum ImportMatch {
  /// No calories in the screenshot for this line.
  none,

  /// Within 10%.
  close,

  /// 10–30% out.
  off,

  /// More than 30% out (or one side is 0).
  veryDifferent,
}

class RecipeImportException implements Exception {
  final String message;

  /// The server said this is a Premium feature.
  final bool premiumRequired;

  const RecipeImportException(this.message, {this.premiumRequired = false});

  @override
  String toString() => message;
}

/// Turning screenshots or photos of a recipe (another app, a website, a
/// cookbook) into ingredients. The image is only read for the food and
/// amount; calories come from our own lookup, with the screenshot's shown
/// alongside so they can be compared (and matched, if the person wants).
class RecipeImport {
  RecipeImport._();

  static const maxImages = 3;

  /// Reads the ingredients from [images] (bytes and mime type each).
  static Future<RecipeImportResult> read(
      List<({List<int> bytes, String mime})> images) async {
    final response = await ProxyClient.post('/recipe/from-image', {
      'images': [
        for (final im in images.take(maxImages))
          {'image': base64Encode(im.bytes), 'mime': im.mime},
      ],
    }).timeout(const Duration(seconds: 120));
    Map? j;
    try {
      final d = json.decode(response.body);
      if (d is Map) j = d;
    } catch (_) {}
    if (response.statusCode != 200) {
      throw RecipeImportException(
        (j?['error'] as String?) ?? "Couldn't read that image. Try another?",
        premiumRequired: j?['code'] == 'premium_required',
      );
    }
    final raw = j?['ingredients'];
    final servings = j?['servings'];
    return RecipeImportResult(
      title: '${j?['title'] ?? ''}'.trim(),
      servings: servings is num && servings > 0 ? servings.toDouble() : null,
      lines: [
        if (raw is List)
          for (final item in raw)
            if (item is Map && '${item['query'] ?? ''}'.trim().isNotEmpty)
              ImportedLine.fromJson(item),
      ],
    );
  }

  /// [ours] scaled so its calories are [target], keeping its protein,
  /// carbs and fat in the same proportions. With no calories of our own
  /// to scale from, just the calories (macros unknown, so 0).
  static Macros matchCalories(Macros ours, double target) {
    if (!target.isFinite || target < 0) return ours;
    if (ours.calories <= 0) return Macros(calories: target);
    return ours.scaled(target / ours.calories);
  }

  /// How far our [ours] calories are from the screenshot's [shown].
  static ImportMatch compare(double ours, int? shown) {
    if (shown == null) return ImportMatch.none;
    if (shown <= 0 || ours <= 0) {
      return (shown <= 0 && ours <= 0) ? ImportMatch.close : ImportMatch.veryDifferent;
    }
    final diff = (ours - shown).abs() / shown;
    if (diff <= 0.10) return ImportMatch.close;
    if (diff <= 0.30) return ImportMatch.off;
    return ImportMatch.veryDifferent;
  }

  /// Ours compared with the screenshot, as a signed whole percent
  /// ("+17%" means ours is 17% higher). Null without both numbers.
  static int? percentDifference(double ours, int? shown) {
    if (shown == null || shown <= 0) return null;
    return ((ours - shown) / shown * 100).round();
  }
}
