import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/ui/premium_sheet.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:namer_app/pages/barcode_scan_page.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/services/split_service.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/services/food_history.dart';
import 'package:namer_app/services/food_resolver.dart';
import 'package:namer_app/services/statement_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/achievement_service.dart';

/// A food being looked up: shown as a "pending transaction" until it
/// settles, and open for a calorie guess while it's pending.
class _PendingItem {
  final String query;
  double? guess;
  ResolvedFood? result;
  bool failed = false;
  int? score;

  _PendingItem(this.query);

  bool get settled => result != null || failed;
}

class AddFoodPage extends StatefulWidget {
  const AddFoodPage({Key? key}) : super(key: key);

  @override
  State<AddFoodPage> createState() => _AddFoodPageState();
}

class _AddFoodPageState extends State<AddFoodPage> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _ingredients = [];
  final List<Map<String, dynamic>> _calculatedItems = [];
  bool _calculating = false;
  bool _saving = false;

  /// Saving has taken a while (usually a poor connection).
  bool _slowSave = false;
  Timer? _slowSaveTimer;

  /// Foods being looked up right now (pending transactions).
  List<_PendingItem> _pending = [];
  bool _scanning = false;
  bool _readingPhoto = false;
  bool _tutorialMode = false;
  int _progressDone = 0;
  int _progressTotal = 0;

  /// The food box keeps focus after Enter or a suggestion, so several
  /// foods can be typed in a row.
  final FocusNode _foodFocus = FocusNode();

  /// Foods logged in the last few months, for one-tap re-adding and
  /// suggestions while typing (no lookup needed).
  FoodHistory _history = FoodHistory.empty;

  /// "Or add again" for [_rankedMeal], worked out once per meal.
  String? _rankedMeal;
  List<CardTransaction> _ranked = const [];

  bool get _hasInput =>
      _ingredients.isNotEmpty || _controller.text.trim().isNotEmpty;

  /// Foods the last look-up couldn't find (offered for a manual add).
  final Set<String> _failedLookups = {};

  /// The first food still in the list that couldn't be looked up.
  String? get _firstFailed {
    for (final i in _ingredients) {
      if (_failedLookups.contains(i)) return i;
    }
    return null;
  }

  /// Anything on the page the demo would wipe.
  bool get _hasAnything =>
      _hasInput || _calculatedItems.isNotEmpty || _pending.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Wake the lookup server while they type, so it's ready on Calculate.
    ProxyClient.warmUp();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final history = await FoodHistory.load(uid);
      if (mounted) {
        setState(() {
          _history = history;
          _rankedMeal = null; // re-rank with the new history
        });
      }
    } catch (_) {
      // Past foods are a convenience; ignore failures.
    }
  }

  /// Up to 10 past foods for [meal], most often had for it first.
  List<CardTransaction> _recentFor(String meal) {
    if (_rankedMeal != meal) {
      _rankedMeal = meal;
      _ranked = FoodHistory.rankForMeal(_history.foods, meal, limit: 10);
    }
    return _ranked;
  }

  /// Adds every complete item from the text box (anything followed by a
  /// comma, semicolon or new line). With [all], the unfinished last item
  /// is added too (used on Enter and before calculating).
  void _takeItemsFromInput({bool all = false}) {
    final value = _controller.text;
    final List<String> parts;
    final String rest;
    if (all) {
      parts = FoodResolver.splitItems(value);
      rest = '';
    } else {
      final taken = FoodResolver.takeFinished(value);
      parts = taken.done;
      rest = taken.rest;
    }
    if (parts.isEmpty && rest == value) {
      setState(() {}); // just refresh the buttons and suggestions
      return;
    }
    setState(() {
      _ingredients.addAll(parts);
      _controller.value = TextEditingValue(
        text: rest,
        selection: TextSelection.collapsed(offset: rest.length),
      );
    });
  }

  Map<String, dynamic> _itemFromResolved(ResolvedFood r) => {
        // Scanned items are looked up by digits; show the product's name.
        'name': r.source == 'barcode' ? r.name : r.query,
        'matched_name': r.name,
        'calories': r.calories,
        'protein': r.protein,
        'carbs': r.carbs,
        'fat': r.fat,
        'portion': r.portion,
        'source': r.source,
        'needs_review': r.needsReview,
        'multiplier': 1.0,
        'base': {
          'calories': r.calories,
          'protein': r.protein,
          'carbs': r.carbs,
          'fat': r.fat,
        },
      };

  void _addRecent(CardTransaction tx) {
    setState(() {
      _calculatedItems.add({
        'name': tx.description,
        'calories': tx.calories,
        'protein': tx.protein,
        'carbs': tx.carbs,
        'fat': tx.fat,
        'portion': tx.portion,
        'source': 'recent',
        'needs_review': false,
        'multiplier': 1.0,
        'base': {
          'calories': tx.calories,
          'protein': tx.protein,
          'carbs': tx.carbs,
          'fat': tx.fat,
        },
      });
    });
  }

  /// A suggestion from your history tapped while typing: added straight
  /// to the list with its exact numbers, and the half-typed name cleared.
  void _addSuggestion(CardTransaction tx) {
    _addRecent(tx);
    _controller.clear();
    setState(() {});
    _foodFocus.requestFocus();
  }

  /// Quick add: just the calories (and macros if known), no lookup.
  /// [name] pre-fills the sheet (e.g. a food that couldn't be looked up);
  /// once added, that item leaves the "Ready to look up" list.
  Future<void> _quickAdd({String? name}) async {
    final item = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QuickAddSheet(initialName: name),
    );
    if (item == null || !mounted) return;
    setState(() {
      _calculatedItems.add(item);
      if (name != null) _ingredients.remove(name);
    });
  }

  /// Scale an item, e.g. "I had two of those".
  void _setMultiplier(int idx, double multiplier) {
    final item = _calculatedItems[idx];
    final base = (item['base'] as Map?) ??
        {
          'calories': item['calories'],
          'protein': item['protein'],
          'carbs': item['carbs'],
          'fat': item['fat'],
        };
    double b(String k) => (base[k] as num?)?.toDouble() ?? 0;
    final basePortion =
        (item['base_portion'] ?? item['portion'] ?? '').toString();
    setState(() {
      _calculatedItems[idx] = {
        ...item,
        'base': base,
        'base_portion': basePortion,
        'portion': _scaledPortion(basePortion, multiplier),
        'multiplier': multiplier,
        'calories': b('calories') * multiplier,
        'protein': b('protein') * multiplier,
        'carbs': b('carbs') * multiplier,
        'fat': b('fat') * multiplier,
      };
    });
  }

  /// True for portions given per 100 g / 100 ml (common for scanned
  /// packs), where amounts in grams make more sense than "2×".
  static bool _isPer100(String portion) =>
      RegExp(r'^\s*100\s*(g|ml)\b', caseSensitive: false).hasMatch(portion);

  /// "118g" scaled by 2 is "2 × 118g"; "100 g" scaled by 2.5 is "250 g".
  static String _scaledPortion(String basePortion, double multiplier) {
    if (multiplier == 1) return basePortion;
    final unit = RegExp(r'^\s*100\s*(g|ml)\b', caseSensitive: false)
        .firstMatch(basePortion)
        ?.group(1);
    if (unit != null) return '${(100 * multiplier).round()} ${unit.toLowerCase()}';
    final m = FoodLog.formatAmount(multiplier);
    return basePortion.isEmpty ? '$m×' : '$m × $basePortion';
  }

  /// Sets an item's calories outright (fixing an estimate). The base is
  /// rescaled so changing the amount afterwards still works.
  void _setCalories(int idx, double kcal) {
    final item = _calculatedItems[idx];
    final multiplier = (item['multiplier'] as num?)?.toDouble() ?? 1.0;
    final base = Map<String, dynamic>.from((item['base'] as Map?) ??
        {
          'calories': item['calories'],
          'protein': item['protein'],
          'carbs': item['carbs'],
          'fat': item['fat'],
        });
    base['calories'] = multiplier > 0 ? kcal / multiplier : kcal;
    setState(() {
      _calculatedItems[idx] = {
        ...item,
        'base': base,
        'calories': kcal,
        // The person set the number, so it's no longer an estimate.
        'original_source': item['original_source'] ?? item['source'],
        'source': 'manual',
        'needs_review': false,
        'edited': true,
      };
    });
  }

  Future<void> _showAdjustSheet(int idx) async {
    final item = _calculatedItems[idx];
    final basePortion =
        (item['base_portion'] ?? item['portion'] ?? '').toString();
    final result = await showModalBottomSheet<_Adjustment>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AdjustSheet(
        name: item['name'].toString(),
        portion: (item['portion'] ?? '').toString(),
        basePortion: basePortion,
        multiplier: (item['multiplier'] as num?)?.toDouble() ?? 1.0,
        calories: (item['calories'] as num?)?.toDouble() ?? 0,
        // Estimates, and numbers the person typed in themselves.
        canEditCalories: item['source'] == 'ai' ||
            item['source'] == 'manual' ||
            item['needs_review'] == true ||
            item['edited'] == true,
      ),
    );
    if (result == null || !mounted || idx >= _calculatedItems.length) return;
    final m = result.multiplier;
    if (m != null) _setMultiplier(idx, m);
    final kcal = result.calories;
    if (kcal != null) _setCalories(idx, kcal);
  }

  Widget _buildResultCard(int idx, Map<String, dynamic> item) {
    final source = item['source'];
    final review = item['needs_review'] == true;
    final multiplier = (item['multiplier'] as num?)?.toDouble() ?? 1.0;
    final portion = (item['portion'] ?? '').toString();
    String g(String k) => ((item[k] as num?) ?? 0).round().toString();

    // [color] is a text colour (AppText / *Text getters), so badges stay
    // readable in dark mode too.
    Widget badge(String text, Color color, IconData icon) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 3),
              Flexible(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: review ? AppColors.amber300 : AppColors.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showAdjustSheet(idx),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      multiplier == 1.0
                          ? item['name'].toString()
                          : '${item['name']}  ×${multiplier == multiplier.roundToDouble() ? multiplier.toStringAsFixed(0) : multiplier}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (portion.isNotEmpty) portion,
                        '${g('protein')}g protein · ${g('carbs')}g carbs · ${g('fat')}g fat',
                      ].join('  ·  '),
                      style:
                          TextStyle(fontSize: 12, color: AppColors.gray600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (source == 'fatsecret')
                          badge('Database match', AppText.emerald700,
                              Icons.verified_outlined),
                        if (source == 'ai')
                          badge('AI estimate', AppText.primaryDark,
                              Icons.auto_awesome),
                        if (source == 'web')
                          badge('Label found online', AppText.emerald700,
                              Icons.public),
                        if (source == 'recent')
                          badge('From your history', AppColors.sky700,
                              Icons.history),
                        if (source == 'barcode')
                          badge('Scanned', AppText.emerald700,
                              Icons.qr_code_2),
                        if (source == 'manual')
                          badge(
                              item['edited'] == true
                                  ? 'Calories set by you'
                                  : 'Added by you',
                              AppText.indigo700,
                              Icons.edit_outlined),
                        if (item['guess_score'] is int)
                          badge(
                              '${item['guess_score']}% · guessed ${(item['guess'] as num).round()}',
                              AppText.violet600,
                              Icons.gps_fixed),
                        if (review)
                          badge('Check this', AppText.amber700,
                              Icons.warning_amber_rounded),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(item['calories'] as num).round()}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  Text('kcal',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.gray600)),
                ],
              ),
              IconButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _calculatedItems.removeAt(idx)),
                icon: const Icon(Icons.close),
                color: AppColors.muted,
                iconSize: 20,
                tooltip: 'Remove item',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Cached tutorial data for instant demo
  static const List<Map<String, dynamic>> _tutorialCachedResults = [
    {
      'name': 'Banana',
      'calories': 105.0,
      'protein': 1.3,
      'carbs': 27.0,
      'fat': 0.4,
      'portion': '118g',
    },
    {
      'name': '5 Strawberries',
      'calories': 16.0,
      'protein': 0.3,
      'carbs': 3.8,
      'fat': 0.2,
      'portion': '5 strawberries',
    },
    {
      'name': '50g Lindt Excellence Dark Chocolate Bar',
      'calories': 270.0,
      'protein': 3.5,
      'carbs': 27.5,
      'fat': 18.0,
      'portion': '50g',
    },
  ];

  @override
  void dispose() {
    _slowSaveTimer?.cancel();
    _foodFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  double get _totalCalories {
    return _calculatedItems.fold(
        0.0, (total, item) => total + (item['calories'] as num).toDouble());
  }

  double get _totalProtein {
    return _calculatedItems.fold(
        0.0, (total, item) => total + (item['protein'] as num).toDouble());
  }

  double get _totalCarbs {
    return _calculatedItems.fold(
        0.0, (total, item) => total + (item['carbs'] as num).toDouble());
  }

  double get _totalFat {
    return _calculatedItems.fold(
        0.0, (total, item) => total + (item['fat'] as num).toDouble());
  }

  Future<void> _runTutorial() async {
    // The demo clears the page, so it's only offered on an empty one
    // (the button is disabled otherwise); never wipe what they've typed.
    if (_hasAnything || _saving || _tutorialMode) return;
    _foodFocus.unfocus();
    setState(() {
      _tutorialMode = true;
      _ingredients.clear();
      _calculatedItems.clear();
    });

    // Step 1: Add tutorial ingredients with typing effect
    final tutorialIngredients = [
      'Banana',
      '5 Strawberries',
      '50g Lindt Excellence Dark Chocolate Bar'
    ];
    _controller.text = '';

    for (int i = 0; i < tutorialIngredients.length; i++) {
      final ingredient = tutorialIngredients[i];

      // Typing effect
      for (int j = 0; j <= ingredient.length; j++) {
        await Future.delayed(const Duration(milliseconds: 30));
        if (mounted) {
          setState(() {
            _controller.text = ingredient.substring(0, j);
          });
        }
      }

      await Future.delayed(const Duration(milliseconds: 300));

      // Add ingredient
      if (mounted) {
        setState(() {
          _ingredients.add(ingredient);
          _controller.clear();
        });
      }

      await Future.delayed(const Duration(milliseconds: 400));
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // Step 2: Show calculating state with cached results
    if (mounted) {
      setState(() {
        _calculating = true;
      });
    }

    await Future.delayed(const Duration(milliseconds: 800));

    // Step 3: Display cached calculated items
    if (mounted) {
      setState(() {
        _calculatedItems.addAll(_tutorialCachedResults);
        _ingredients.clear();
        _calculating = false;
      });
    }

    await Future.delayed(const Duration(milliseconds: 1500));

    // Step 4: Remove items one by one
    for (int i = _calculatedItems.length - 1; i >= 0; i--) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() {
          _calculatedItems.removeAt(i);
        });
      }
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // Step 5: End tutorial
    if (mounted) {
      setState(() {
        _tutorialMode = false;
        // Leave the page as empty as it was before the demo.
        _calculatedItems.clear();
        _ingredients.clear();
        _controller.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("That's it. Now try your own."),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _calculateWithAI() async {
    if (_calculating || _saving) return;
    _takeItemsFromInput(all: true);
    if (_ingredients.isEmpty) return;
    final queries = List<String>.from(_ingredients);

    setState(() {
      _calculating = true;
      _pending = [for (final q in queries) _PendingItem(q)];
      _ingredients.clear();
      _progressDone = 0;
      _progressTotal = queries.length;
    });

    // Several lookups at once; each one settles on screen as it arrives.
    await FoodResolver.resolveAll(
      queries,
      onResult: (i, r) {
        if (!mounted || i >= _pending.length) return;
        setState(() {
          final p = _pending[i];
          if (r == null) {
            p.failed = true;
          } else {
            p.result = r;
            final guess = p.guess;
            if (guess != null && r.calories > 0) {
              // Shown now; it only counts once the food is actually logged.
              p.score = CalorieSense.score(guess, r.calories);
            }
          }
        });
      },
      onProgress: (done, _) {
        if (mounted) setState(() => _progressDone = done);
      },
    );

    // A beat so the last item is seen settling before the list moves.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final failed = [
      for (final p in _pending)
        if (p.result == null) p.query
    ];
    setState(() {
      for (final p in _pending) {
        final r = p.result;
        if (r == null) continue;
        _calculatedItems.add({
          ..._itemFromResolved(r),
          if (p.guess != null) 'guess': p.guess,
          if (p.score != null) 'guess_score': p.score,
        });
      }
      // Anything that failed stays in the list so it can be retried
      // (alongside anything typed while the lookups ran).
      _ingredients.addAll(failed);
      _failedLookups
        ..clear()
        ..addAll(failed);
      _pending = [];
      _calculating = false;
    });

    if (failed.isNotEmpty) {
      final first = failed.first;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
              "Couldn't look up ${failed.length} item${failed.length == 1 ? '' : 's'}. "
              "${failed.length == 1 ? 'It\'s' : 'They\'re'} still in the list: "
              'tap Look up to retry, or add the calories yourself.'),
          action: SnackBarAction(
            label: 'Add calories manually',
            onPressed: () {
              if (mounted) _quickAdd(name: first);
            },
          ),
        ),
      );
    }
  }

  /// Counts the guesses for the food that was actually logged (guessing
  /// and then removing the item doesn't count).
  void _recordGuesses(Iterable<Map<String, dynamic>> logged) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    for (final item in logged) {
      final score = item['guess_score'];
      if (score is int) {
        // A missed score isn't worth interrupting logging for.
        CalorieSense.record(uid, score).catchError((_) {});
        if (score >= 95) AchievementService.bump(uid, 'bang_on');
      }
    }
  }

  /// "Guess the price": asks for a calorie guess while the item is pending.
  Future<void> _guess(_PendingItem item) async {
    var value = 300.0;
    final picked = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('How many calories do you reckon?',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(item.query,
                    style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    '${value.round()} kcal',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppText.primaryDark,
                    ),
                  ),
                ),
                Slider(
                  value: value,
                  min: 0,
                  max: 1500,
                  divisions: 150,
                  label: '${value.round()}',
                  onChanged: (v) => setSheet(() => value = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, value),
                    icon: const Icon(Icons.gps_fixed),
                    label: const Text('Lock in my guess'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Scores count towards your Calorie Sense on the hiscores.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (item.settled) {
      // The answer came back while the sheet was open.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Too late, that one came back while you guessed!')),
      );
      return;
    }
    setState(() => item.guess = picked.roundToDouble());
  }

  /// True on a phone-sized window. Uses the real window width: on desktop
  /// MediaQuery.size is narrowed to the page column.
  bool get _isPhone {
    final view = View.of(context);
    return view.physicalSize.width / view.devicePixelRatio <
        Breakpoints.tablet;
  }

  Future<void> _scanBarcode() async {
    // On phones, open above the bottom bar so the Coach button doesn't
    // cover the number field.
    final code = await Navigator.of(context, rootNavigator: _isPhone)
        .push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );
    if (code == null || code.isEmpty || !mounted) return;
    setState(() => _scanning = true);
    try {
      final r = await FoodResolver.fromBarcode(code);
      if (!mounted) return;
      if (r == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text("We couldn't find that product. Type it in instead.")),
        );
      } else {
        setState(() => _calculatedItems.add(_itemFromResolved(r)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't look that barcode up. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _photoOfMeal() async {
    if (!Premium.isPremium) {
      await showPremiumSheet(
        context,
        title: 'Photo logging is part of Premium',
        message: 'Snap your plate and the app works out what\'s on it, '
            'ready for you to check and log.',
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 72,
      );
      if (file == null || !mounted) return;
      setState(() => _readingPhoto = true);
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final mime = file.mimeType ??
          (name.endsWith('.png')
              ? 'image/png'
              : name.endsWith('.webp')
                  ? 'image/webp'
                  : 'image/jpeg');
      final foods = await FoodResolver.foodsInPhoto(bytes, mime);
      if (!mounted) return;
      setState(() => _readingPhoto = false);
      if (foods.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't spot any food in that photo.")),
        );
        return;
      }
      setState(() => _ingredients.addAll(foods));
      // Straight into the normal lookup, as pending transactions.
      await _calculateWithAI();
    } catch (e) {
      if (mounted) {
        setState(() => _readingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Couldn't read that photo. Try another, or type what you had.")),
        );
      }
    }
  }

  /// Split the bill: log your share and send friends a request for theirs.
  Future<void> _splitBill() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _calculatedItems.isEmpty || _saving) return;

    List<Friend> friends;
    try {
      friends = await FriendsService.load(uid);
    } catch (_) {
      friends = const [];
    }
    if (!mounted) return;
    if (friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some friends to split with first.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SplitSheet(
        friends: friends,
        items: List<Map<String, dynamic>>.from(_calculatedItems),
      ),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    setState(() => _saving = true);
    try {
      final meal =
          Provider.of<CategoryService>(context, listen: false).selectedCategory;
      final email = FirebaseAuth.instance.currentUser?.email;
      await SplitService.create(
        uid: uid,
        fromName: await FriendsService.nameFor(uid, email: email),
        items: _calculatedItems,
        friendIds: chosen,
        meal: meal,
      );
      _recordGuesses(_calculatedItems);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Added your share and sent ${chosen.length} request${chosen.length == 1 ? '' : 's'}.'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't split that. Please try again.")),
        );
      }
    }
  }

  Widget _buildPendingRow(_PendingItem p) {
    final r = p.result;
    final settled = p.settled;
    final guess = p.guess;
    final score = p.score;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: settled ? AppColors.surface : AppColors.indigo50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: p.failed
              ? AppColors.red300
              : settled
                  ? AppColors.emerald300
                  : AppColors.indigo100,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                if (r != null)
                  Text(
                    [r.name, if (r.portion.isNotEmpty) r.portion].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: AppColors.muted),
                  )
                else if (p.failed)
                  Text("Couldn't look this up",
                      style: TextStyle(fontSize: 12, color: AppText.red600))
                else
                  const _PendingPill(),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (r != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${r.calories.round()} kcal',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.ink)),
                if (score != null)
                  Text(
                    '🎯 $score% · ${CalorieSense.verdict(score)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppText.emerald600),
                  ),
              ],
            )
          else if (!settled && guess == null)
            TextButton.icon(
              onPressed: () => _guess(p),
              icon: const Icon(Icons.gps_fixed, size: 18),
              label: const Text('Guess'),
            )
          else if (guess != null)
            Text('Your guess: ${guess.round()}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppText.primaryDark)),
        ],
      ),
    );
  }

  Future<void> _saveItems() async {
    // _saving is set before the first await, so a double tap can't log
    // the same food twice.
    if (_calculatedItems.isEmpty || _saving || _calculating) return;

    final items = [
      for (final item in _calculatedItems) Map<String, dynamic>.from(item)
    ];
    final category =
        Provider.of<CategoryService>(context, listen: false).selectedCategory;
    setState(() {
      _saving = true;
      _slowSave = false;
    });

    // On a poor connection the write can take a long time to confirm.
    // Say so instead of spinning silently (it isn't lost: Firestore
    // finishes it when the connection comes back).
    _slowSaveTimer?.cancel();
    _slowSaveTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted || !_saving) return;
      setState(() => _slowSave = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Still saving… check your connection. It'll finish when "
              "you're back online."),
        ),
      );
    });

    try {
      // One write logs every item and charges the card for them.
      final logged = await FoodLog.logFoods(items: items, meal: category);
      _slowSaveTimer?.cancel();
      _recordGuesses(items);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        Navigator.pop(context, logged);
      }
    } catch (e) {
      _slowSaveTimer?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't save your food. Please try again.")),
        );
        setState(() {
          _saving = false;
          _slowSave = false;
        });
      }
    }
  }

  /// The one main button: look up what's been typed, then add it.
  Widget _buildMainButton(String meal) {
    final typed = _controller.text.trim().isEmpty
        ? 0
        : FoodResolver.splitItems(_controller.text).length;
    final toLookUp = _ingredients.length + typed;
    // Anything in "Ready to add" can be added; items still waiting in
    // "Ready to look up" don't block it.
    final canAdd = _calculatedItems.isNotEmpty;

    // The button is disabled (pale grey) while busy, so the spinner uses
    // the theme's primary colour rather than white, which wouldn't show.
    const spinner = SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    final VoidCallback? onPressed;
    final Widget icon;
    final String label;
    if (_saving) {
      onPressed = null;
      icon = spinner;
      label = _slowSave ? 'Still saving… check your connection' : 'Adding…';
    } else if (_calculating) {
      onPressed = null;
      icon = spinner;
      label = 'Looking up $_progressDone/$_progressTotal…';
    } else if (_hasInput) {
      final n = toLookUp < 1 ? 1 : toLookUp;
      onPressed = _calculateWithAI;
      icon = const Icon(Icons.auto_awesome, size: 20);
      label = 'Look up $n item${n == 1 ? '' : 's'}';
    } else if (canAdd) {
      onPressed = _saveItems;
      icon = const Icon(Icons.check_circle_outline, size: 20);
      label = 'Add ${_totalCalories.round()} kcal to $meal';
    } else {
      onPressed = null;
      icon = const Icon(Icons.add, size: 20);
      label = 'Add to $meal';
    }

    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      icon: icon,
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  /// Past foods matching what's being typed, for one-tap adding.
  List<Widget> _buildSuggestions() {
    if (_tutorialMode || _history.foods.isEmpty) return const [];
    final matches =
        FoodHistory.search(_history.foods, _controller.text, limit: 5);
    if (matches.isEmpty) return const [];
    return [
      const SizedBox(height: 6),
      Container(
        decoration: AppDecor.card,
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  "You've had before",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ),
              for (final tx in matches)
                InkWell(
                  onTap: _saving ? null : () => _addSuggestion(tx),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.history, size: 18, color: AppColors.muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tx.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                                if (tx.portion.trim().isNotEmpty)
                                  Text(
                                    tx.portion.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12, color: AppColors.muted),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${tx.calories.round()} kcal',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.add_circle_outline,
                              size: 20, color: AppText.primary),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  /// Scan barcode, Photo of meal and Quick add. Three across when there's
  /// room; on a phone, Quick add goes full width underneath.
  Widget _buildQuickActions() {
    final busy = _calculating || _saving || _tutorialMode;
    final scan = OutlinedButton.icon(
      onPressed: (busy || _scanning) ? null : _scanBarcode,
      icon: _scanning
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.qr_code_scanner),
      label: const Text('Scan barcode'),
    );
    final photo = OutlinedButton.icon(
      onPressed: (busy || _readingPhoto) ? null : _photoOfMeal,
      icon: _readingPhoto
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.photo_camera_outlined),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _readingPhoto ? 'Reading photo…' : 'Photo of meal',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!Premium.isPremium && !_readingPhoto) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'PREMIUM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;
        final quick = OutlinedButton.icon(
          onPressed: busy ? null : () => _quickAdd(),
          icon: const Icon(Icons.bolt),
          label: Text(wide ? 'Quick add' : 'Quick add calories'),
        );
        if (wide) {
          return Row(
            children: [
              Expanded(child: scan),
              const SizedBox(width: 8),
              Expanded(child: photo),
              const SizedBox(width: 8),
              Expanded(child: quick),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: scan),
                const SizedBox(width: 8),
                Expanded(child: photo),
              ],
            ),
            const SizedBox(height: 8),
            quick,
          ],
        );
      },
    );
  }

  /// "Or add again": the foods most often had for [meal]. A scrolling row
  /// on phones; on wider screens they wrap so all of them show.
  List<Widget> _buildRecents(String meal) {
    if (_tutorialMode) return const [];
    final recent = _recentFor(meal);
    if (recent.isEmpty) return const [];

    Widget chip(CardTransaction tx) {
      final label = [
        tx.description,
        if (tx.portion.trim().isNotEmpty) tx.portion.trim(),
        '${tx.calories.round()} kcal',
      ].join(' · ');
      return ActionChip(
        avatar: const Icon(Icons.add, size: 16),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        onPressed: _saving ? null : () => _addRecent(tx),
      );
    }

    return [
      Text(
        'Or add again',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.gray700,
        ),
      ),
      const SizedBox(height: 8),
      if (_isPhone)
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => Center(child: chip(recent[i])),
          ),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final tx in recent) chip(tx)],
        ),
      const SizedBox(height: 16),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final meal = Provider.of<CategoryService>(context).selectedCategory;
    // The demo clears the page, so it's only offered when there's nothing
    // to lose.
    final canDemo = !_tutorialMode && !_saving && !_hasAnything;
    return Scaffold(
      appBar: AppBar(
        title: Text('Add to $meal'),
        actions: [
          Tooltip(
            message: canDemo || _tutorialMode
                ? 'Show me how'
                : 'Show me how (clear your list first)',
            child: IconButton(
              onPressed: canDemo ? _runTutorial : null,
              icon: const Icon(Icons.help_outline),
            ),
          ),
        ],
      ),
      // The main button stays in reach however long the list gets.
      bottomNavigationBar: AbsorbPointer(
        absorbing: _tutorialMode,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMainButton(meal),
                  if (_calculatedItems.isNotEmpty &&
                      !_calculating &&
                      !_tutorialMode)
                    TextButton.icon(
                      onPressed: _saving ? null : _splitBill,
                      icon: const Icon(Icons.call_split),
                      label:
                          const Text('Shared it? Split the bill with friends'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _tutorialMode,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Type everything you had. We'll work out the calories.",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    focusNode: _foodFocus,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'What did you eat?',
                      hintText: 'e.g. 2 eggs, 1 slice toast, 330ml coke',
                      border: const OutlineInputBorder(),
                      helperText:
                          'Separate foods with commas, or press Enter after each',
                      helperMaxLines: 2,
                      suffixIcon: IconButton(
                        tooltip: 'Add to list',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _takeItemsFromInput(all: true),
                      ),
                    ),
                    onChanged: (_) => _takeItemsFromInput(),
                    onSubmitted: (_) => _takeItemsFromInput(all: true),
                    // Keep the keyboard up after Enter so the next food
                    // can be typed straight away.
                    onEditingComplete: () {},
                  ),
                  ..._buildSuggestions(),
                  const SizedBox(height: 10),
                  _buildQuickActions(),
                  const SizedBox(height: 16),
                  ..._buildRecents(meal),
                  if (_ingredients.isNotEmpty) ...[
                    Text(
                      'Ready to look up',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _ingredients.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final ingredient = entry.value;
                        return Chip(
                          label: Text(ingredient),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          deleteButtonTooltipMessage: 'Remove',
                          onDeleted: () {
                            setState(() => _ingredients.removeAt(idx));
                          },
                          backgroundColor: AppColors.emerald100,
                        );
                      }).toList(),
                    ),
                    if (_firstFailed != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _calculating || _saving
                              ? null
                              : () => _quickAdd(name: _firstFailed),
                          icon: const Icon(Icons.edit_note, size: 20),
                          label: Text(
                            'Add calories for "${_firstFailed!}" manually',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                  if (_pending.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.schedule,
                            size: 18, color: AppText.primaryDark),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Pending ($_progressDone/$_progressTotal settled) · '
                            'guess the calories while you wait',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppText.primaryDark),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final p in _pending) _buildPendingRow(p),
                  ],
                  if (_calculatedItems.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Ready to add',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _calculatedItems.length; i++)
                      _buildResultCard(i, _calculatedItems[i]),
                    Text(
                      'Tap an item to change how much you had.',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.gray600),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'Total: ${_totalCalories.round()} kcal\n'
                        '${_totalProtein.round()}g protein · '
                        '${_totalCarbs.round()}g carbs · '
                        '${_totalFat.round()}g fat',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.ink,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_tutorialMode)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.school,
                        color: Colors.white,
                        size: 32,
                      ),
                      SizedBox(width: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick demo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Watch how to use this page',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Pending" label that gently pulses, like an unsettled card payment.
class _PendingPill extends StatefulWidget {
  const _PendingPill();

  @override
  State<_PendingPill> createState() => _PendingPillState();
}

class _PendingPillState extends State<_PendingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.amber50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.amber300),
        ),
        child: Text(
          'Pending',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppText.amber700,
          ),
        ),
      ),
    );
  }
}

/// Pick who you shared with; shows your share as you pick.
class _SplitSheet extends StatefulWidget {
  final List<Friend> friends;
  final List<Map<String, dynamic>> items;

  const _SplitSheet({required this.friends, required this.items});

  @override
  State<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<_SplitSheet> {
  final Set<String> _chosen = {};

  @override
  Widget build(BuildContext context) {
    final people = _chosen.length + 1;
    // Exactly what each person will log (rounded per item).
    final share =
        SplitService.shareCalories(widget.items, people < 2 ? 2 : people)
            .round();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Split the bill',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                _chosen.isEmpty
                    ? 'Who did you share it with?'
                    : 'Split $people ways: everyone gets $share kcal',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in widget.friends)
                      CheckboxListTile(
                        value: _chosen.contains(f.id),
                        title: Text(f.name),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _chosen.add(f.id);
                          } else {
                            _chosen.remove(f.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _chosen.isEmpty
                      ? null
                      : () => Navigator.pop(context, _chosen.toList()),
                  icon: const Icon(Icons.call_split),
                  label: Text(_chosen.isEmpty
                      ? 'Pick friends'
                      : 'Add my $share kcal & send requests'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Numbers typed with a decimal point or a decimal comma ("1,5").
double? _parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

final _numberInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

/// What the adjust sheet changed: a new amount, new calories, or both.
class _Adjustment {
  final double? multiplier;
  final double? calories;

  const _Adjustment({this.multiplier, this.calories});
}

/// Change how much of a food you had (preset chips or an exact amount),
/// and fix the calories of an estimate.
class _AdjustSheet extends StatefulWidget {
  final String name;
  final String portion;
  final String basePortion;
  final double multiplier;
  final double calories;
  final bool canEditCalories;

  const _AdjustSheet({
    required this.name,
    required this.portion,
    required this.basePortion,
    required this.multiplier,
    required this.calories,
    required this.canEditCalories,
  });

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  late final bool _per100 = _AddFoodPageState._isPer100(widget.basePortion);

  /// "g" or "ml" for per-100 portions.
  late final String _unit = (RegExp(r'^\s*100\s*(g|ml)\b',
                  caseSensitive: false)
              .firstMatch(widget.basePortion)
              ?.group(1) ??
          'g')
      .toLowerCase();

  late final TextEditingController _amount = TextEditingController(
    text: FoodLog.formatAmount(
        _per100 ? 100 * widget.multiplier : widget.multiplier),
  );
  late final TextEditingController _kcal =
      TextEditingController(text: '${widget.calories.round()}');

  bool _editingCalories = false;
  String? _amountError;
  String? _kcalError;

  @override
  void dispose() {
    _amount.dispose();
    _kcal.dispose();
    super.dispose();
  }

  void _save() {
    double? multiplier;
    final amountText = _amount.text.trim();
    if (amountText.isNotEmpty) {
      final a = _parseNumber(amountText);
      final m = a == null ? null : (_per100 ? a / 100 : a);
      if (m == null || !m.isFinite || m <= 0) {
        setState(() => _amountError = 'Enter an amount more than 0');
        return;
      }
      if (m > 100) {
        setState(() => _amountError = "That's a lot. Check the amount?");
        return;
      }
      if ((m - widget.multiplier).abs() > 1e-9) multiplier = m;
    }

    double? calories;
    if (_editingCalories) {
      final k = _parseNumber(_kcal.text);
      if (k == null || !k.isFinite || k < 0 || k > 20000) {
        setState(() => _kcalError = 'Enter the calories, e.g. 250');
        return;
      }
      if (k.round() != widget.calories.round() || multiplier != null) {
        calories = k.roundToDouble();
      }
    }

    Navigator.pop(
      context,
      multiplier == null && calories == null
          ? null
          : _Adjustment(multiplier: multiplier, calories: calories),
    );
  }

  @override
  Widget build(BuildContext context) {
    final choices = _per100
        ? const [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0]
        : const [0.5, 1.0, 1.5, 2.0, 3.0];
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (widget.portion.isNotEmpty)
                Text('Portion: ${widget.portion}',
                    style: TextStyle(color: AppColors.gray600)),
              const SizedBox(height: 16),
              Text('How much did you have?',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in choices)
                    ChoiceChip(
                      label: Text(_per100
                          ? _AddFoodPageState._scaledPortion(
                              widget.basePortion, m)
                          : '${FoodLog.formatAmount(m)}×'),
                      selected: (widget.multiplier - m).abs() < 1e-9,
                      onSelected: (_) => Navigator.pop(
                          context, _Adjustment(multiplier: m)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _numberInput,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: _per100 ? 'Exact amount' : 'How many portions',
                  suffixText: _per100 ? _unit : '×',
                  helperText: _per100
                      ? 'In $_unit'
                      : widget.basePortion.isEmpty
                          ? '1 = as looked up'
                          : '1 = ${widget.basePortion}',
                  errorText: _amountError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_amountError != null) {
                    setState(() => _amountError = null);
                  }
                },
                onSubmitted: (_) => _save(),
              ),
              if (widget.canEditCalories) ...[
                const SizedBox(height: 12),
                if (!_editingCalories)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _editingCalories = true),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit calories'),
                    ),
                  )
                else
                  TextField(
                    controller: _kcal,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _numberInput,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Calories',
                      suffixText: 'kcal',
                      helperText: "It's an estimate. Know better? Fix it here.",
                      helperMaxLines: 2,
                      errorText: _kcalError,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_kcalError != null) {
                        setState(() => _kcalError = null);
                      }
                    },
                    onSubmitted: (_) => _save(),
                  ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick add: a name (optional) and the calories, with macros if known.
/// Pops with an item ready for the "Ready to add" list.
class _QuickAddSheet extends StatefulWidget {
  final String? initialName;

  const _QuickAddSheet({this.initialName});

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName ?? '');
  final TextEditingController _kcal = TextEditingController();
  final TextEditingController _protein = TextEditingController();
  final TextEditingController _carbs = TextEditingController();
  final TextEditingController _fat = TextEditingController();
  String? _kcalError;
  String? _macroError;

  @override
  void dispose() {
    _name.dispose();
    _kcal.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  /// An optional macro: empty is 0, anything else must be a number ≥ 0.
  double? _macro(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return 0;
    final v = _parseNumber(text);
    return v != null && v.isFinite && v >= 0 && v <= 2000 ? v : null;
  }

  void _add() {
    final kcal = _parseNumber(_kcal.text);
    if (kcal == null || !kcal.isFinite || kcal < 0 || kcal > 20000) {
      setState(() => _kcalError = 'Enter the calories, e.g. 250');
      return;
    }
    final protein = _macro(_protein);
    final carbs = _macro(_carbs);
    final fat = _macro(_fat);
    if (protein == null || carbs == null || fat == null) {
      setState(() => _macroError = 'Macros need to be numbers (or blank)');
      return;
    }
    final name = _name.text.trim();
    Navigator.pop(context, <String, dynamic>{
      'name': name.isEmpty ? 'Quick add' : name,
      'calories': kcal.roundToDouble(),
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'portion': '',
      'source': 'manual',
      'needs_review': false,
      'multiplier': 1.0,
      'base': {
        'calories': kcal.roundToDouble(),
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
      },
    });
  }

  Widget _macroField(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _numberInput,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: label,
            suffixText: 'g',
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (_macroError != null) setState(() => _macroError = null);
          },
          onSubmitted: (_) => _add(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final named = (widget.initialName ?? '').trim().isNotEmpty;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Quick add',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Know the calories? Add them straight to your list.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Name (optional)',
                  hintText: 'Quick add',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _kcal,
                // Straight to the number when the name is already known.
                autofocus: named,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _numberInput,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Calories',
                  suffixText: 'kcal',
                  errorText: _kcalError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_kcalError != null) setState(() => _kcalError = null);
                },
                onSubmitted: (_) => _add(),
              ),
              const SizedBox(height: 12),
              Text(
                'Protein, carbs and fat (optional)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.gray600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _macroField(_protein, 'Protein'),
                  const SizedBox(width: 8),
                  _macroField(_carbs, 'Carbs'),
                  const SizedBox(width: 8),
                  _macroField(_fat, 'Fat'),
                ],
              ),
              if (_macroError != null) ...[
                const SizedBox(height: 6),
                Text(_macroError!,
                    style: TextStyle(fontSize: 12, color: AppText.red600)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _add,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.add),
                label: const Text('Add to list'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
