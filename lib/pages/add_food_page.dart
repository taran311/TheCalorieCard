import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:namer_app/pages/barcode_scan_page.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/services/split_service.dart';
import 'package:namer_app/services/category_service.dart';
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
  bool _calculated = false;
  bool _saving = false;
  /// Foods being looked up right now (pending transactions).
  List<_PendingItem> _pending = [];
  bool _scanning = false;
  bool _readingPhoto = false;
  bool _tutorialMode = false;
  int _progressDone = 0;
  int _progressTotal = 0;

  /// Foods logged recently, for one-tap re-adding (no lookup needed).
  List<CardTransaction> _recent = const [];

  bool get _hasInput =>
      _ingredients.isNotEmpty || _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Wake the lookup server while they type, so it's ready on Calculate.
    ProxyClient.warmUp();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final statement = await StatementService.load(uid, days: 14);
      final seen = <String>{};
      final recent = <CardTransaction>[];
      for (final tx in statement.recent) {
        if (tx.description.startsWith('Recipe:')) continue;
        if (seen.add(tx.description.toLowerCase())) recent.add(tx);
        if (recent.length >= 10) break;
      }
      if (mounted) setState(() => _recent = recent);
    } catch (_) {
      // Recent foods are a convenience; ignore failures.
    }
  }

  /// Adds every complete item from the text box (anything followed by a
  /// comma, semicolon or new line). With [all], the unfinished last item
  /// is added too (used on Enter and before calculating).
  void _takeItemsFromInput({bool all = false}) {
    final value = _controller.text;
    final parts = FoodResolver.splitItems(value);
    final endsWithSeparator = RegExp(r'[,\n;]\s*$').hasMatch(value);
    var remainder = '';
    if (!all && !endsWithSeparator && parts.isNotEmpty) {
      remainder = parts.removeLast();
    }
    if (parts.isEmpty && remainder == value.trim()) {
      setState(() {}); // just refresh the buttons
      return;
    }
    setState(() {
      _ingredients.addAll(parts);
      _calculated = _calculatedItems.isNotEmpty;
      _controller.value = TextEditingValue(
        text: remainder,
        selection: TextSelection.collapsed(offset: remainder.length),
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
      _calculated = true;
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

  Future<void> _showAdjustSheet(int idx) async {
    final item = _calculatedItems[idx];
    final current = (item['multiplier'] as num?)?.toDouble() ?? 1.0;
    final basePortion =
        (item['base_portion'] ?? item['portion'] ?? '').toString();
    final per100 = _isPer100(basePortion);
    final choices = per100
        ? const [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0]
        : const [0.5, 1.0, 1.5, 2.0, 3.0];
    final picked = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['name'].toString(),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              if ((item['portion'] ?? '').toString().isNotEmpty)
                Text('Portion: ${item['portion']}',
                    style: TextStyle(color: AppColors.gray600)),
              const SizedBox(height: 16),
              const Text('How much did you have?',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in choices)
                    ChoiceChip(
                      label: Text(per100
                          ? _scaledPortion(basePortion, m)
                          : '${FoodLog.formatAmount(m)}×'),
                      selected: current == m,
                      onSelected: (_) => Navigator.pop(sheetContext, m),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) _setMultiplier(idx, picked);
  }

  Widget _buildResultCard(int idx, Map<String, dynamic> item) {
    final source = item['source'];
    final review = item['needs_review'] == true;
    final multiplier = (item['multiplier'] as num?)?.toDouble() ?? 1.0;
    final portion = (item['portion'] ?? '').toString();
    String g(String k) => ((item[k] as num?) ?? 0).round().toString();

    Widget badge(String text, Color color, IconData icon) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 3),
              Text(text,
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (portion.isNotEmpty) portion,
                        'P ${g('protein')}g · C ${g('carbs')}g · F ${g('fat')}g',
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
                          badge('Database match', AppColors.green,
                              Icons.verified_outlined),
                        if (source == 'ai')
                          badge('AI estimate', AppColors.primary,
                              Icons.auto_awesome),
                        if (source == 'recent')
                          badge('From your history', AppColors.sky,
                              Icons.history),
                        if (source == 'barcode')
                          badge('Scanned', AppColors.green,
                              Icons.qr_code_2),
                        if (item['guess_score'] is int)
                          badge(
                              '${item['guess_score']}% · guessed ${(item['guess'] as num).round()}',
                              AppColors.violet600,
                              Icons.gps_fixed),
                        if (review)
                          badge('Check this', AppColors.amber700,
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
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  Text('kcal',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.gray600)),
                ],
              ),
              IconButton(
                onPressed: () => setState(() {
                  _calculatedItems.removeAt(idx);
                  _calculated = _calculatedItems.isNotEmpty;
                }),
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
    setState(() {
      _tutorialMode = true;
      _ingredients.clear();
      _calculatedItems.clear();
      _calculated = false;
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
        _calculated = true;
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
        _calculated = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tutorial complete! Now try it yourself.'),
          backgroundColor: AppColors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _calculateWithAI() async {
    _takeItemsFromInput(all: true);
    if (_ingredients.isEmpty || _calculating) return;
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
      _pending = [];
      _calculating = false;
      _calculated = _calculatedItems.isNotEmpty;
    });

    if (failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "Couldn't look up ${failed.length} item${failed.length == 1 ? '' : 's'}. "
              "${failed.length == 1 ? 'It\'s' : 'They\'re'} still in the list; tap Calculate to retry."),
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
                    style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    '${value.round()} kcal',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
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
                const Text(
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

  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
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
        setState(() {
          _calculatedItems.add(_itemFromResolved(r));
          _calculated = true;
        });
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
          SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  /// Split the bill: log your share and send friends a request for theirs.
  Future<void> _splitBill() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _calculatedItems.isEmpty) return;

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
        fromName: FriendsService.displayName(email),
        items: _calculatedItems,
        friendIds: chosen,
        meal: meal,
      );
      _recordGuesses(_calculatedItems);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Logged your share and sent ${chosen.length} request${chosen.length == 1 ? '' : 's'}.'),
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
        color: settled ? Colors.white : AppColors.indigo50,
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
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                if (r != null)
                  Text(
                    [r.name, if (r.portion.isNotEmpty) r.portion].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted),
                  )
                else if (p.failed)
                  const Text("Couldn't look this up",
                      style: TextStyle(fontSize: 12, color: AppColors.red600))
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
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.ink)),
                if (score != null)
                  Text(
                    '🎯 $score% · ${CalorieSense.verdict(score)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.emerald600),
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
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark)),
        ],
      ),
    );
  }

  Future<void> _saveItems() async {
    if (_calculatedItems.isEmpty || _saving) return;

    setState(() {
      _saving = true;
    });

    try {
      final category =
          Provider.of<CategoryService>(context, listen: false).selectedCategory;

      // One write logs every item and charges the card for them.
      await FoodLog.logFoods(items: _calculatedItems, meal: category);
      _recordGuesses(_calculatedItems);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't save your food. Please try again.")),
        );
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Food Items'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _tutorialMode ? null : _runTutorial,
            icon: const Icon(Icons.help_outline, size: 36),
            tooltip: 'Tutorial',
            iconSize: 36,
          ),
        ],
      ),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _tutorialMode,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Add multiple food items at once',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_recent.isNotEmpty && !_tutorialMode) ...[
                    Text(
                      'Recent',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.gray700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recent.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final tx = _recent[i];
                          return ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(
                                '${tx.description} · ${tx.calories.round()}'),
                            onPressed: () => _addRecent(tx),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'What did you eat?',
                      hintText: 'e.g. 2 eggs, 1 slice toast, 330ml coke',
                      border: const OutlineInputBorder(),
                      helperText:
                          'Separate foods with commas, or press Enter after each',
                      suffixIcon: IconButton(
                        tooltip: 'Add to list',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _takeItemsFromInput(all: true),
                      ),
                    ),
                    onChanged: (_) => _takeItemsFromInput(),
                    onSubmitted: (_) => _takeItemsFromInput(all: true),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              (_calculating || _scanning || _tutorialMode)
                                  ? null
                                  : _scanBarcode,
                          icon: _scanning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan barcode'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              (_calculating || _readingPhoto || _tutorialMode)
                                  ? null
                                  : _photoOfMeal,
                          icon: _readingPhoto
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.photo_camera_outlined),
                          label: Text(_readingPhoto
                              ? 'Reading photo…'
                              : 'Photo of meal'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_ingredients.isNotEmpty) ...[
                    const Text(
                      'Items to calculate:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
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
                          onDeleted: () {
                            setState(() {
                              _ingredients.removeAt(idx);
                              _calculated = false;
                            });
                          },
                          backgroundColor: AppColors.emerald100,
                        );
                      }).toList(),
                    ),
                  ],
                  if (_pending.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.schedule,
                            size: 18, color: AppColors.primaryDark),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Pending ($_progressDone/$_progressTotal settled) · '
                            'guess the calories while you wait',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark),
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
                    const Text(
                      'Calculated items:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.green,
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
                        color: AppColors.amber50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.amber300),
                      ),
                      child: Text(
                        'Total: ${_totalCalories.round()} kcal  ·  P ${_totalProtein.round()}g  C ${_totalCarbs.round()}g  F ${_totalFat.round()}g',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.amber700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: (!_hasInput || _calculating)
                              ? null
                              : _calculateWithAI,
                          icon: _calculating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Icon(Icons.auto_awesome, size: 20),
                          label: Text(
                            _calculating
                                ? 'Looking up $_progressDone/$_progressTotal…'
                                : 'Calculate',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (!_calculated ||
                                  _saving ||
                                  _calculatedItems.isEmpty)
                              ? null
                              : _saveItems,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Icon(Icons.check_circle, size: 20),
                          label: Text(
                            _saving ? 'Saving...' : 'Save',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: (!_calculated ||
                                    _saving ||
                                    _calculatedItems.isEmpty)
                                ? AppColors.gray300
                                : AppColors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: (!_calculated ||
                                    _saving ||
                                    _calculatedItems.isEmpty)
                                ? 0
                                : 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_calculated &&
                      _calculatedItems.isNotEmpty &&
                      !_calculating &&
                      !_tutorialMode) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _saving ? null : _splitBill,
                      icon: const Icon(Icons.call_split),
                      label:
                          const Text('Shared it? Split the bill with friends'),
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
                            'Tutorial Mode',
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
        child: const Text(
          'Pending',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.amber700,
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
                style: const TextStyle(color: AppColors.muted),
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
                      : 'Log my $share kcal & send requests'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
