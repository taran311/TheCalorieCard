import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/pages/add_food_page.dart';
import 'package:namer_app/pages/add_recipe_page.dart';
import 'package:namer_app/pages/login_or_register_page.dart';
import 'package:namer_app/pages/menu_page.dart';
import 'package:namer_app/pages/recipes_page.dart';
import 'package:namer_app/pages/user_settings_page.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/services/achievement_service.dart';

class HomePage extends StatefulWidget {
  final bool addFoodAnimation;
  final bool hideNav;
  final bool readOnly;
  final String? userIdOverride;
  final String? bannerTitle;
  final bool showBanner;

  const HomePage(
      {Key? key,
      this.addFoodAnimation = false,
      this.hideNav = false,
      this.readOnly = false,
      this.userIdOverride,
      this.bannerTitle,
      this.showBanner = false})
      : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _SelectExistingRecipePage extends StatefulWidget {
  const _SelectExistingRecipePage();

  @override
  State<_SelectExistingRecipePage> createState() =>
      _SelectExistingRecipePageState();
}

class _SelectExistingRecipePageState extends State<_SelectExistingRecipePage> {
  int? _editingRecipeIndex;
  final TextEditingController _portionController = TextEditingController();

  @override
  void dispose() {
    _portionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Recipe')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('recipes')
            .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No recipes yet.'));
          }

          final recipes = snapshot.data!.docs;
          // Sort by created_at descending (client-side)
          recipes.sort((a, b) {
            final timeA = a['created_at'] as Timestamp?;
            final timeB = b['created_at'] as Timestamp?;
            if (timeA == null || timeB == null) return 0;
            return timeB.compareTo(timeA);
          });

          return ListView.builder(
            itemCount: recipes.length,
            itemBuilder: (context, index) {
              final recipe = recipes[index];
              final calories = recipe['total_calories'] as num? ?? 0;
              final protein =
                  (recipe['total_protein'] as num?)?.toDouble() ?? 0;
              final carbs = (recipe['total_carbs'] as num?)?.toDouble() ?? 0;
              final fat = (recipe['total_fat'] as num?)?.toDouble() ?? 0;
              final servingSize =
                  recipe['serving_size'] as String? ?? 'Per 1 Serving';
              final isEditing = _editingRecipeIndex == index;

              // Parse serving size to determine unit and value
              final isGrams = servingSize.contains('g') &&
                  !servingSize.toLowerCase().contains('serving');
              final servingMatch =
                  RegExp(r'(\d+(?:\.\d+)?)').firstMatch(servingSize);
              final originalServingValue = servingMatch != null
                  ? double.parse(servingMatch.group(1)!)
                  : 1.0;
              final unit = isGrams
                  ? 'g'
                  : 'Serving${originalServingValue != 1 ? 's' : ''}';

              return Column(
                children: [
                  ListTile(
                    title: Text(recipe['name'] ?? 'Recipe'),
                    subtitle: Text(
                        '${calories.toStringAsFixed(0)} kcal ($servingSize)'),
                    trailing: const Icon(Icons.add_circle_outline,
                        color: Color(0xFF6366F1)),
                    onTap: () {
                      setState(() {
                        _editingRecipeIndex = index;
                        _portionController.text = originalServingValue
                            .toStringAsFixed(isGrams ? 0 : 1);
                      });
                    },
                  ),
                  if (isEditing)
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.indigo.shade300, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'per ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(
                                width: 70,
                                child: TextField(
                                  controller: _portionController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  onSubmitted: (_) => setState(() {}),
                                  onTapOutside: (_) {
                                    FocusScope.of(context).unfocus();
                                    setState(() {});
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                unit,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Builder(
                            builder: (context) {
                              final newPortion =
                                  double.tryParse(_portionController.text) ??
                                      originalServingValue;
                              final ratio = newPortion / originalServingValue;
                              final adjustedCalories =
                                  (calories * ratio).toInt();
                              final adjustedProtein = protein * ratio;
                              final adjustedCarbs = carbs * ratio;
                              final adjustedFat = fat * ratio;

                              return Column(
                                children: [
                                  // Calories - Prominent display
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.orange.shade400,
                                          Colors.orange.shade600,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.orange.withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.local_fire_department,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '$adjustedCalories',
                                          style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'kcal',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // Macros - Grid layout
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10, horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade100,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.blue.shade300,
                                              width: 1,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                'Protein',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue.shade800,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${adjustedProtein.toStringAsFixed(1)}g',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue.shade900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10, horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade100,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.green.shade300,
                                              width: 1,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                'Carbs',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.green.shade800,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${adjustedCarbs.toStringAsFixed(1)}g',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green.shade900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10, horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.shade100,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.purple.shade300,
                                              width: 1,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                'Fat',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.purple.shade800,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${adjustedFat.toStringAsFixed(1)}g',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.purple.shade900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _editingRecipeIndex = null;
                                          });
                                        },
                                        child: const Text('Cancel'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () {
                                          final multiplier = ratio;
                                          Navigator.pop(context, {
                                            'recipeId': recipe.id,
                                            'multiplier': multiplier,
                                          });
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF6366F1),
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Add'),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  String get _activeUserId =>
      widget.userIdOverride ?? FirebaseAuth.instance.currentUser!.uid;
  List<QueryDocumentSnapshot> _foodDocs = [];
  final List<String> _tabs = ['Brekkie', 'Lunch', 'Dinner', 'Snacks'];
  int _creditCardRefreshKey = 0;
  bool _isLoading = true;
  bool _deleteMode = false;
  bool _isDayFinished = false;
  bool _isUpdatingDailyLog = false;
  double _cardDragDx = 0;
  DateTime _selectedLogDate = DateTime.now();
  Map<String, dynamic>? _selectedDailyLog;
  bool _isDailyLogLoading = false;

  // Category totals tracking
  bool _showMacrosTotal = false;
  int _totalCalories = 0;
  double _totalProtein = 0.0;
  double _totalCarbs = 0.0;
  double _totalFat = 0.0;
  String? _lastFetchedCategory;

  // Individual food item macro visibility tracking
  Map<String, bool> _foodMacrosVisibility = {};

  // Food reaction tracking
  Map<String, List<Map<String, dynamic>>> _foodReactions = {};
  Map<String, bool> _showEmojiPicker = {};
  Map<String, bool> _showReactions = {};
  String? _reactionConfirmationFoodId;
  String? _reactionConfirmationEmoji;
  String? _reactionConfirmationUsername;
  AnimationController? _reactionFadeController;
  Animation<double>? _reactionFadeAnimation;

  // Card animations
  AnimationController? _jiggleAnimationController;
  Animation<double>? _jiggleAnimation;
  AnimationController? _cardDragResetController;
  double _dragEndDx = 0;
  bool _isResettingCard = false;
  bool _pendingSwipePrompt = false;
  bool _isDeletingItem = false;

  String _roundMacro(dynamic value) {
    final numVal =
        (value is num) ? value.toDouble() : double.tryParse('$value') ?? 0.0;
    return numVal.toStringAsFixed(1).endsWith('.5')
        ? numVal.ceil().toString()
        : numVal.round().toString();
  }

  @override
  void initState() {
    super.initState();
    _jiggleAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _reactionFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _reactionFadeAnimation = CurvedAnimation(
      parent: _reactionFadeController!,
      curve: Curves.easeInOut,
    );

    _jiggleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: -0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.05, end: 0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: -0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.05, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _jiggleAnimationController!,
      curve: Curves.easeInOut,
    ));

    _cardDragResetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _initializeHome();
  }

  @override
  void dispose() {
    _jiggleAnimationController?.dispose();
    _cardDragResetController?.dispose();
    _reactionFadeController?.dispose();
    super.dispose();
  }

  Future<void> _resetCardPosition({required bool promptAfterReset}) async {
    if (_cardDragResetController == null) return;
    _pendingSwipePrompt = promptAfterReset;
    _dragEndDx = _cardDragDx;
    _isResettingCard = true;
    _cardDragResetController!.reset();
    await _cardDragResetController!.forward();
    if (!mounted) return;
    setState(() {
      _isResettingCard = false;
      _cardDragDx = 0;
    });
    if (_pendingSwipePrompt) {
      _pendingSwipePrompt = false;
      await _handleCardSwipe();
    }
  }

  Future<void> _initializeHome() async {
    await populateFoodItems();
    await _fetchDailyLogForDate(_selectedLogDate);
    // Fetch category totals on initial load
    final categoryService =
        Provider.of<CategoryService>(context, listen: false);
    await _fetchCategoryTotals(categoryService.selectedCategory);
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool get _isSelectedDateToday => _isSameDay(_selectedLogDate, DateTime.now());

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _fetchDailyLogForDate(DateTime date) async {
    try {
      setState(() {
        _isDailyLogLoading = true;
      });
      final userId = _activeUserId;
      final key = _dateKey(date);
      final docRef = FirebaseFirestore.instance
          .collection('daily_logs')
          .doc('${userId}_$key');
      final doc = await docRef.get();
      if (!mounted) return;
      final data = doc.data();
      setState(() {
        _selectedDailyLog = data;
      });
      await _loadDailyLogStatusForSelectedDate(data);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedDailyLog = null;
        _isDayFinished = false;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isDailyLogLoading = false;
      });
    }
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _loadDailyLogStatusForSelectedDate(
      Map<String, dynamic>? data) async {
    final finished = data?['finished'] as bool? ?? false;
    if (!mounted) return;
    setState(() {
      _isDayFinished = finished;
      if (_isDayFinished) {
        _deleteMode = false;
      }
    });
  }

  Future<void> _setDailyLogFinished(DateTime date, bool finished) async {
    try {
      final userId = _activeUserId;
      final key = _dateKey(date);
      final docRef = FirebaseFirestore.instance
          .collection('daily_logs')
          .doc('${userId}_$key');
      await docRef.set({
        'user_id': userId,
        'date_key': key,
        'date': Timestamp.fromDate(date),
        'finished': finished,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore
    }
  }

  Future<void> _upsertDailyLogForDate(DateTime date) async {
    if (_isUpdatingDailyLog) return;
    setState(() {
      _isUpdatingDailyLog = true;
    });

    try {
      final userId = _activeUserId;

      final firestore = FirebaseFirestore.instance;
      final key = _dateKey(date);

      final foodSnapshot = await firestore
          .collection('user_food')
          .where('user_id', isEqualTo: userId)
          .get();

      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      DateTime? _extractDocDate(QueryDocumentSnapshot doc) {
        final data = doc.data() as Map<String, dynamic>;
        final timeAdded = data['time_added'];
        final createdAt = data['created_at'];

        if (timeAdded is Timestamp) return timeAdded.toDate();
        if (timeAdded is DateTime) return timeAdded;
        if (createdAt is Timestamp) return createdAt.toDate();
        if (createdAt is DateTime) return createdAt;
        return null;
      }

      final filteredDocs = foodSnapshot.docs.where((doc) {
        final docDate = _extractDocDate(doc);
        if (docDate == null) return false;
        return !docDate.isBefore(startOfDay) && docDate.isBefore(endOfDay);
      }).toList();

      final foodEntries = filteredDocs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();

      double totalCalories = 0;
      double totalProtein = 0;
      double totalCarbs = 0;
      double totalFat = 0;

      for (final entry in foodEntries) {
        totalCalories += (entry['food_calories'] as num?)?.toDouble() ?? 0;
        totalProtein += (entry['food_protein'] as num?)?.toDouble() ?? 0;
        totalCarbs += (entry['food_carbs'] as num?)?.toDouble() ?? 0;
        totalFat += (entry['food_fat'] as num?)?.toDouble() ?? 0;
      }

      final userDataSnapshot = await firestore
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();

      final userData = userDataSnapshot.docs.isNotEmpty
          ? (userDataSnapshot.docs.first.data() as Map<String, dynamic>)
          : <String, dynamic>{};

      final docRef = firestore.collection('daily_logs').doc('${userId}_$key');
      final existingDoc = await docRef.get();
      final existingFinished =
          (existingDoc.data()?['finished'] as bool?) ?? false;
      await docRef.set({
        'user_id': userId,
        'date_key': key,
        'date': Timestamp.fromDate(date),
        'food_entries': foodEntries,
        'totals': {
          'calories': totalCalories,
          'protein': totalProtein,
          'carbs': totalCarbs,
          'fat': totalFat,
        },
        'balances': {
          'calories': (userData['calories'] as num?)?.toDouble(),
          'protein_balance': (userData['protein_balance'] as num?)?.toDouble(),
          'carbs_balance': (userData['carbs_balance'] as num?)?.toDouble(),
          'fats_balance': (userData['fats_balance'] as num?)?.toDouble(),
        },
        'goals': {
          'protein_goal': (userData['protein_goal'] as num?)?.toDouble(),
          'carbs_goal': (userData['carbs_goal'] as num?)?.toDouble(),
          'fats_goal': (userData['fats_goal'] as num?)?.toDouble(),
        },
        'finished': existingFinished,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingDailyLog = false;
        });
      }
    }
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _handleCardSwipe() async {
    if (_isUpdatingDailyLog) return;
    if (!_isSelectedDateToday || widget.readOnly) return;
    if (_isDayFinished) {
      final confirm = await _showConfirmDialog(
        title: 'Continue logging',
        message: 'Are you sure you wish to continue logging for today?',
      );
      if (!confirm) return;
      setState(() {
        _isDayFinished = false;
      });
      await _setDailyLogFinished(_selectedLogDate, false);
      await _fetchDailyLogForDate(_selectedLogDate);
      return;
    }

    final confirm = await _showConfirmDialog(
      title: 'Finish logging',
      message: 'Are you sure you wish to finish logging for today?',
    );
    if (!confirm) return;

    setState(() {
      _isDayFinished = true;
      _deleteMode = false;
    });
    await _upsertDailyLogForDate(_selectedLogDate);
    await _setDailyLogFinished(_selectedLogDate, true);
    await _fetchDailyLogForDate(_selectedLogDate);
    await AchievementService.updateAchievementsForUser(_activeUserId);
  }

  Future<void> populateFoodItems() async {
    try {
      final categoryService =
          Provider.of<CategoryService>(context, listen: false);
      final selectedDate = _selectedLogDate;
      final startOfDay =
          DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      DateTime? _extractDocDate(QueryDocumentSnapshot doc) {
        final data = doc.data() as Map<String, dynamic>;
        final timeAdded = data['time_added'];
        final createdAt = data['created_at'];

        if (timeAdded is Timestamp) return timeAdded.toDate();
        if (timeAdded is DateTime) return timeAdded;
        if (createdAt is Timestamp) return createdAt.toDate();
        if (createdAt is DateTime) return createdAt;
        return null;
      }

      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_food')
          .where('user_id', isEqualTo: _activeUserId)
          .get(const GetOptions(source: Source.server));

      if (querySnapshot.docs.isNotEmpty) {
        final filteredDocs = querySnapshot.docs.where((doc) {
          final categoryMatches = (doc['foodCategory'] ?? 'Brekkie') ==
              categoryService.selectedCategory;
          if (!categoryMatches) return false;
          final docDate = _extractDocDate(doc);
          if (docDate == null) return false;
          return !docDate.isBefore(startOfDay) && docDate.isBefore(endOfDay);
        }).toList();

        if (mounted) {
          setState(() {
            _foodDocs = filteredDocs;
            // Reset individual food macro visibility when category changes
            _foodMacrosVisibility.clear();
            for (var doc in filteredDocs) {
              _foodMacrosVisibility[doc.id] = false;
            }
          });
          // Fetch reactions for all food items
          await _fetchReactionsForFoodItems();
        }
      } else {
        if (mounted) {
          setState(() {
            _foodDocs = [];
            _foodMacrosVisibility.clear();
          });
        }
      }
    } catch (e) {
      print('Error populating food items: $e');
      if (mounted) {
        setState(() {
          _foodDocs = [];
          _foodMacrosVisibility.clear();
        });
      }
    }
  }

  Future<void> _fetchReactionsForFoodItems() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      for (var doc in _foodDocs) {
        final reactionsSnapshot = await FirebaseFirestore.instance
            .collection('food_reactions')
            .where('food_item_id', isEqualTo: doc.id)
            .get();

        final reactions =
            await Future.wait(reactionsSnapshot.docs.map((reactionDoc) async {
          final userId = reactionDoc['user_id'];
          // Fetch user email/username
          String username = 'Unknown';
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();
            username = userDoc.data()?['email']?.split('@')[0] ?? 'Unknown';
          } catch (e) {
            print('Error fetching user data: $e');
          }

          return {
            'id': reactionDoc.id,
            'emoji': reactionDoc['emoji'],
            'user_id': userId,
            'username': username,
          };
        }));

        if (mounted) {
          setState(() {
            _foodReactions[doc.id] = reactions;
          });
        }
      }
    } catch (e) {
      print('Error fetching reactions: $e');
    }
  }

  Future<void> _addReaction(String foodItemId, String emoji) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      // Get current user's email for display
      final currentUserEmail = FirebaseAuth.instance.currentUser?.email ?? '';
      final username = currentUserEmail.split('@')[0];

      // Check if user already reacted to this food item
      final existingReaction = await FirebaseFirestore.instance
          .collection('food_reactions')
          .where('food_item_id', isEqualTo: foodItemId)
          .where('user_id', isEqualTo: currentUserId)
          .limit(1)
          .get();

      if (existingReaction.docs.isNotEmpty) {
        // Update existing reaction
        await existingReaction.docs.first.reference.update({
          'emoji': emoji,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new reaction
        await FirebaseFirestore.instance.collection('food_reactions').add({
          'food_item_id': foodItemId,
          'owner_id': _activeUserId,
          'user_id': currentUserId,
          'emoji': emoji,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      // Refresh reactions
      await _fetchReactionsForFoodItems();

      if (mounted) {
        setState(() {
          _showEmojiPicker[foodItemId] = false;
          // Show confirmation animation
          _reactionConfirmationFoodId = foodItemId;
          _reactionConfirmationEmoji = emoji;
          _reactionConfirmationUsername = username;
        });

        // Fade in animation
        _reactionFadeController?.forward(from: 0.0);

        // Wait 2 seconds then fade out
        await Future.delayed(const Duration(seconds: 2));
        await _reactionFadeController?.reverse();

        if (mounted) {
          setState(() {
            _reactionConfirmationFoodId = null;
            _reactionConfirmationEmoji = null;
            _reactionConfirmationUsername = null;
          });
        }
      }
    } catch (e) {
      print('Error adding reaction: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding reaction: $e')),
        );
      }
    }
  }

  void _handleFoodItemTap(String foodItemId) {
    if (widget.readOnly) {
      // Show emoji picker
      setState(() {
        _showEmojiPicker[foodItemId] = !(_showEmojiPicker[foodItemId] ?? false);
      });
    } else {
      // Toggle reactions display
      setState(() {
        _showReactions[foodItemId] = !(_showReactions[foodItemId] ?? false);
      });
    }
  }

  Future<void> deleteFood() async {
    try {
      QuerySnapshot userFoodSnapshot = await FirebaseFirestore.instance
          .collection('user_food')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();

      num caloriesToReAdd = 0;
      double proteinToReAdd = 0;
      double carbsToReAdd = 0;
      double fatsToReAdd = 0;

      for (var doc in userFoodSnapshot.docs) {
        caloriesToReAdd += doc['food_calories'];
        proteinToReAdd += (doc['food_protein'] as num?)?.toDouble() ?? 0.0;
        carbsToReAdd += (doc['food_carbs'] as num?)?.toDouble() ?? 0.0;
        fatsToReAdd += (doc['food_fat'] as num?)?.toDouble() ?? 0.0;
        batch.delete(doc.reference);
      }

      await batch.commit();

      QuerySnapshot userDataSnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();

      final docRef = FirebaseFirestore.instance
          .collection('user_data')
          .doc(userDataSnapshot.docs.first.id);

      final updatedCalories =
          userDataSnapshot.docs.first['calories'] + caloriesToReAdd;

      await docRef.update({
        'calories': updatedCalories,
        'protein_balance':
            ((userDataSnapshot.docs.first['protein_balance'] as num?)
                        ?.toDouble() ??
                    (userDataSnapshot.docs.first['protein_goal'] as num?)
                        ?.toDouble() ??
                    0.0) +
                proteinToReAdd,
        'carbs_balance': ((userDataSnapshot.docs.first['carbs_balance'] as num?)
                    ?.toDouble() ??
                (userDataSnapshot.docs.first['carbs_goal'] as num?)
                    ?.toDouble() ??
                0.0) +
            carbsToReAdd,
        'fats_balance': ((userDataSnapshot.docs.first['fats_balance'] as num?)
                    ?.toDouble() ??
                (userDataSnapshot.docs.first['fats_goal'] as num?)
                    ?.toDouble() ??
                0.0) +
            fatsToReAdd,
      });

      // Reset category totals
      final categoryService =
          Provider.of<CategoryService>(context, listen: false);
      await _resetCategoryTotals(categoryService.selectedCategory);

      // Refresh the list of food items
      await populateFoodItems();

      if (_isSelectedDateToday) {
        await _upsertDailyLogForDate(_selectedLogDate);
        await _fetchDailyLogForDate(_selectedLogDate);
      }

      // Trigger CreditCard refresh
      setState(() {
        _creditCardRefreshKey++;
      });
    } catch (e) {
      print('Error deleting food items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting food: $e')),
        );
      }
    }
  }

  Future<void> signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginOrRegisterPage()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  Future<void> navigateToProfilePage() async {
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => UserSettingsPage()),
      );
      if (!mounted) return;
      setState(() {
        _creditCardRefreshKey++;
      });
    }
  }

  Future<void> _deleteFoodItem(String docId) async {
    if (_isDeletingItem) return; // Prevent multiple deletions

    setState(() {
      _isDeletingItem = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final categoryService =
          Provider.of<CategoryService>(context, listen: false);
      final currentCategory = categoryService.selectedCategory;

      // Get the food item data before deleting it
      final foodDocSnapshot = await firestore
          .collection('user_food')
          .doc(docId)
          .get(const GetOptions(source: Source.server));

      if (!foodDocSnapshot.exists) {
        throw Exception('Food item not found');
      }

      final foodData = foodDocSnapshot.data() as Map<String, dynamic>;
      final calories = (foodData['food_calories'] as num?)?.toDouble() ?? 0;
      final protein = (foodData['food_protein'] as num?)?.toDouble() ?? 0;
      final carbs = (foodData['food_carbs'] as num?)?.toDouble() ?? 0;
      final fat = (foodData['food_fat'] as num?)?.toDouble() ?? 0;

      // Delete the food item
      await firestore.collection('user_food').doc(docId).delete();

      // Update user balances (add back the calories/macros since we're removing consumption)
      final userDataSnapshot = await firestore
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();

      if (userDataSnapshot.docs.isNotEmpty) {
        final doc = userDataSnapshot.docs.first;
        final docRef = doc.reference;
        final data = doc.data();

        final currentCalories = data['calories'];
        double newCalories;
        if (currentCalories is int) {
          newCalories = currentCalories.toDouble() + calories;
        } else if (currentCalories is double) {
          newCalories = currentCalories + calories;
        } else if (currentCalories is String) {
          newCalories = (double.tryParse(currentCalories) ?? 0) + calories;
        } else {
          newCalories = 0 + calories;
        }

        double proteinBal = (data['protein_balance'] as num?)?.toDouble() ??
            (data['protein_goal'] as num?)?.toDouble() ??
            0.0;
        double carbsBal = (data['carbs_balance'] as num?)?.toDouble() ??
            (data['carbs_goal'] as num?)?.toDouble() ??
            0.0;
        double fatsBal = (data['fats_balance'] as num?)?.toDouble() ??
            (data['fats_goal'] as num?)?.toDouble() ??
            0.0;

        proteinBal += protein;
        carbsBal += carbs;
        fatsBal += fat;

        await docRef.update({
          'calories': newCalories,
          'protein_balance': proteinBal,
          'carbs_balance': carbsBal,
          'fats_balance': fatsBal,
        });
      }

      // Update category totals
      final categoryTotalDocRef = firestore
          .collection('category_totals')
          .doc('${userId}_$currentCategory');
      final categoryTotalSnapshot = await categoryTotalDocRef
          .get(const GetOptions(source: Source.server));

      if (categoryTotalSnapshot.exists) {
        await categoryTotalDocRef.update({
          'total_calories':
              (categoryTotalSnapshot['total_calories'] as num? ?? 0) - calories,
          'total_protein':
              (categoryTotalSnapshot['total_protein'] as num? ?? 0) - protein,
          'total_carbs':
              (categoryTotalSnapshot['total_carbs'] as num? ?? 0) - carbs,
          'total_fat': (categoryTotalSnapshot['total_fat'] as num? ?? 0) - fat,
        });
      }

      // Refresh the UI
      await populateFoodItems();
      await _fetchCategoryTotals(currentCategory);

      if (_isSelectedDateToday) {
        await _upsertDailyLogForDate(_selectedLogDate);
        await _fetchDailyLogForDate(_selectedLogDate);
      }

      if (mounted) {
        setState(() {
          _creditCardRefreshKey++;
          _isDeletingItem = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Food item removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeletingItem = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting food item: $e')),
        );
      }
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final categoryService =
            Provider.of<CategoryService>(context, listen: false);
        final currentCategory = categoryService.selectedCategory;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.local_dining),
                title: const Text('Add Food Item'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AddFoodPage()),
                  );
                  await populateFoodItems();
                  if (_isSelectedDateToday) {
                    await _upsertDailyLogForDate(_selectedLogDate);
                    await _fetchDailyLogForDate(_selectedLogDate);
                  }
                  setState(() => _creditCardRefreshKey++);
                },
              ),
              ListTile(
                leading: const Icon(Icons.restaurant_menu),
                title: const Text('Add New Recipe'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddRecipePage(
                        addToHome: true,
                        homeCategory: currentCategory,
                      ),
                    ),
                  );
                  await populateFoodItems();
                  if (_isSelectedDateToday) {
                    await _upsertDailyLogForDate(_selectedLogDate);
                    await _fetchDailyLogForDate(_selectedLogDate);
                  }
                  setState(() => _creditCardRefreshKey++);
                },
              ),
              ListTile(
                leading: const Icon(Icons.library_books),
                title: const Text('Add Existing Recipe'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _SelectExistingRecipePage(),
                    ),
                  );
                  if (result != null && result is Map<String, dynamic>) {
                    final recipeId = result['recipeId'] as String;
                    final multiplier = result['multiplier'] as double;
                    await _addRecipeToHome(recipeId, currentCategory,
                        multiplier: multiplier);
                    await populateFoodItems();
                    if (_isSelectedDateToday) {
                      await _upsertDailyLogForDate(_selectedLogDate);
                      await _fetchDailyLogForDate(_selectedLogDate);
                    }
                    setState(() => _creditCardRefreshKey++);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addRecipeToHome(String recipeId, String category,
      {double multiplier = 1.0}) async {
    final firestore = FirebaseFirestore.instance;
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final recipeDoc = await firestore.collection('recipes').doc(recipeId).get();
    if (!recipeDoc.exists) return;
    final data = recipeDoc.data()!;

    // Get serving size from recipe, default to "1 Serving" if not present
    final servingSize = data['serving_size'] as String? ?? 'Per 1 Serving';

    // Apply multiplier to calculate adjusted values
    final baseCalories = (data['total_calories'] as num?)?.toDouble() ?? 0;
    final baseProtein = (data['total_protein'] as num?)?.toDouble() ?? 0;
    final baseCarbs = (data['total_carbs'] as num?)?.toDouble() ?? 0;
    final baseFat = (data['total_fat'] as num?)?.toDouble() ?? 0;

    final adjustedCalories = baseCalories * multiplier;
    final adjustedProtein = baseProtein * multiplier;
    final adjustedCarbs = baseCarbs * multiplier;
    final adjustedFat = baseFat * multiplier;

    // Calculate adjusted portion display
    final servingMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(servingSize);
    final originalValue =
        servingMatch != null ? double.parse(servingMatch.group(1)!) : 1.0;
    final newValue = originalValue * multiplier;
    final isGrams = servingSize.contains('g') &&
        !servingSize.toLowerCase().contains('serving');
    final adjustedPortion = isGrams
        ? '${newValue.toStringAsFixed(0)} g'
        : 'Per ${newValue.toStringAsFixed(1)} Serving${newValue != 1 ? 's' : ''}';

    await firestore.collection('user_food').add({
      'user_id': userId,
      'food_description': 'Recipe: ${data['name'] ?? ''}',
      'food_calories': adjustedCalories,
      'food_protein': adjustedProtein,
      'food_carbs': adjustedCarbs,
      'food_fat': adjustedFat,
      'food_portion': adjustedPortion,
      'foodCategory': category,
      'recipe_id': recipeId,
      'is_recipe': true,
      'time_added': DateTime.now(),
      'created_at': FieldValue.serverTimestamp(),
    });

    // Apply to user balances (subtract when adding)
    await _applyRecipeToUserBalances(
      calories: adjustedCalories,
      protein: adjustedProtein,
      carbs: adjustedCarbs,
      fat: adjustedFat,
    );

    // Update category totals
    final docRef =
        firestore.collection('category_totals').doc('${userId}_$category');
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      await docRef.update({
        'total_calories':
            (docSnapshot['total_calories'] as num? ?? 0) + adjustedCalories,
        'total_protein':
            (docSnapshot['total_protein'] as num? ?? 0) + adjustedProtein,
        'total_carbs':
            (docSnapshot['total_carbs'] as num? ?? 0) + adjustedCarbs,
        'total_fat': (docSnapshot['total_fat'] as num? ?? 0) + adjustedFat,
      });
    } else {
      await docRef.set({
        'total_calories': adjustedCalories,
        'total_protein': adjustedProtein,
        'total_carbs': adjustedCarbs,
        'total_fat': adjustedFat,
      });
    }

    // Refresh displayed totals
    await _fetchCategoryTotals(category);
    setState(() {
      _creditCardRefreshKey++;
    });
  }

  Future<void> _applyRecipeToUserBalances({
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
  }) async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final userDataSnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();

      if (userDataSnapshot.docs.isEmpty) return;

      final doc = userDataSnapshot.docs.first;
      final docRef = doc.reference;
      final data = doc.data();

      final currentCalories = data['calories'];
      double newCalories;
      if (currentCalories is int) {
        newCalories = currentCalories.toDouble() - calories;
      } else if (currentCalories is double) {
        newCalories = currentCalories - calories;
      } else if (currentCalories is String) {
        newCalories = (double.tryParse(currentCalories) ?? 0) - calories;
      } else {
        newCalories = 0 - calories;
      }

      double proteinBal = (data['protein_balance'] as num?)?.toDouble() ??
          (data['protein_goal'] as num?)?.toDouble() ??
          0.0;
      double carbsBal = (data['carbs_balance'] as num?)?.toDouble() ??
          (data['carbs_goal'] as num?)?.toDouble() ??
          0.0;
      double fatsBal = (data['fats_balance'] as num?)?.toDouble() ??
          (data['fats_goal'] as num?)?.toDouble() ??
          0.0;

      proteinBal -= protein;
      carbsBal -= carbs;
      fatsBal -= fat;

      await docRef.update({
        'calories': newCalories,
        'protein_balance': proteinBal,
        'carbs_balance': carbsBal,
        'fats_balance': fatsBal,
      });
    } catch (e) {
      print('Error applying recipe balances: $e');
    }
  }

  Future<void> _fetchCategoryTotals(String category) async {
    try {
      final userId = _activeUserId;

      // Calculate totals from actual food items instead of trusting stored totals
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final foodSnapshot = await FirebaseFirestore.instance
          .collection('user_food')
          .where('user_id', isEqualTo: userId)
          .get(const GetOptions(source: Source.server));

      double totalCalories = 0;
      double totalProtein = 0;
      double totalCarbs = 0;
      double totalFat = 0;

      for (final doc in foodSnapshot.docs) {
        final data = doc.data();

        // Check if food is in the selected category
        final foodCategory = data['foodCategory'] ?? 'Brekkie';
        if (foodCategory != category) continue;

        // Extract date from time_added or created_at
        DateTime? docDate;
        final timeAdded = data['time_added'];
        final createdAt = data['created_at'];

        if (timeAdded is Timestamp) {
          docDate = timeAdded.toDate();
        } else if (timeAdded is DateTime) {
          docDate = timeAdded;
        } else if (createdAt is Timestamp) {
          docDate = createdAt.toDate();
        } else if (createdAt is DateTime) {
          docDate = createdAt;
        }

        // Only include items from today
        if (docDate != null &&
            !docDate.isBefore(startOfDay) &&
            docDate.isBefore(endOfDay)) {
          totalCalories += (data['food_calories'] as num?)?.toDouble() ?? 0;
          totalProtein += (data['food_protein'] as num?)?.toDouble() ?? 0;
          totalCarbs += (data['food_carbs'] as num?)?.toDouble() ?? 0;
          totalFat += (data['food_fat'] as num?)?.toDouble() ?? 0;
        }
      }

      // Update the stored totals to match reality
      final docRef = FirebaseFirestore.instance
          .collection('category_totals')
          .doc('${userId}_$category');

      await docRef.set({
        'total_calories': totalCalories,
        'total_protein': totalProtein,
        'total_carbs': totalCarbs,
        'total_fat': totalFat,
      });

      if (mounted) {
        setState(() {
          _totalCalories = totalCalories.toInt();
          _totalProtein = totalProtein;
          _totalCarbs = totalCarbs;
          _totalFat = totalFat;
          _lastFetchedCategory = category;
        });
      }
    } catch (e) {
      print('Error fetching category totals: $e');
    }
  }

  Future<void> _resetCategoryTotals(String category) async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final docRef = FirebaseFirestore.instance
          .collection('category_totals')
          .doc('${userId}_$category');

      await docRef.set({
        'total_calories': 0,
        'total_protein': 0.0,
        'total_carbs': 0.0,
        'total_fat': 0.0,
      });

      if (mounted) {
        setState(() {
          _totalCalories = 0;
          _totalProtein = 0.0;
          _totalCarbs = 0.0;
          _totalFat = 0.0;
          _showMacrosTotal = false;
        });
      }
    } catch (e) {
      print('Error resetting category totals: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          color: Colors.white,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
        bottomNavigationBar: widget.hideNav
            ? null
            : Container(
                color: Colors.white,
                height: 56,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MenuPage(),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                  color: Colors.grey.shade200, width: 1),
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.person, size: 24),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                                color: Colors.grey.shade200, width: 1),
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.credit_card,
                              size: 24, color: Color(0xFF6366F1)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RecipesPage()),
                          );
                        },
                        child: Container(
                          child: const Center(
                            child: Icon(Icons.restaurant, size: 24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.indigo.shade50,
                  Colors.blue.shade50,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.showBanner) ...[
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      MediaQuery.of(context).padding.top + 8,
                      8,
                      8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            Navigator.of(context).maybePop();
                          },
                          icon: const Icon(Icons.arrow_back),
                          color: Colors.white,
                          splashRadius: 20,
                          tooltip: 'Back',
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              widget.bannerTitle ?? 'Card',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  const SizedBox(height: 16),
                ],
                Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _jiggleAnimationController!,
                      _cardDragResetController!,
                    ]),
                    builder: (context, child) {
                      final resetValue = _cardDragResetController?.value ?? 0.0;
                      final effectiveDx = _isResettingCard
                          ? _dragEndDx *
                              (1 - Curves.easeOut.transform(resetValue))
                          : _cardDragDx;
                      return Transform.translate(
                        offset: Offset(effectiveDx, 0),
                        child: Transform.rotate(
                          angle: _jiggleAnimation?.value ?? 0.0,
                          child: child,
                        ),
                      );
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: (_) {
                        _cardDragDx = 0;
                        _cardDragResetController?.stop();
                        _isResettingCard = false;
                      },
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _cardDragDx += details.delta.dx;
                        });
                      },
                      onHorizontalDragEnd: (_) {
                        final shouldPrompt = _cardDragDx.abs() > 40;
                        _resetCardPosition(promptAfterReset: shouldPrompt);
                      },
                      child: Stack(
                        children: [
                          _isSelectedDateToday
                              ? CreditCard(
                                  key: ValueKey(_creditCardRefreshKey),
                                  userIdOverride: widget.userIdOverride,
                                  cardUserNameOverride: widget.bannerTitle,
                                  validThruDate:
                                      '${_selectedLogDate.day}/${_selectedLogDate.month}/${_selectedLogDate.year}',
                                  onToggleMacros: (showMacros) {
                                    // Trigger jiggle when card is flipped
                                    _jiggleAnimationController?.forward(
                                        from: 0);
                                    setState(() {
                                      _showMacrosTotal = showMacros;
                                      for (var doc in _foodDocs) {
                                        _foodMacrosVisibility[doc.id] =
                                            showMacros;
                                      }
                                    });
                                  },
                                )
                              : CreditCard(
                                  key: ValueKey(
                                      '$_creditCardRefreshKey-${_selectedLogDate.toIso8601String()}'),
                                  skipFetch: true,
                                  caloriesOverride:
                                      (_selectedDailyLog?['balances']
                                                  ?['calories'] as num?)
                                              ?.toInt() ??
                                          0,
                                  proteinOverride:
                                      (_selectedDailyLog?['balances']
                                                  ?['protein_balance'] as num?)
                                              ?.toDouble() ??
                                          0,
                                  carbsOverride: (_selectedDailyLog?['balances']
                                              ?['carbs_balance'] as num?)
                                          ?.toDouble() ??
                                      0,
                                  fatsOverride: (_selectedDailyLog?['balances']
                                              ?['fats_balance'] as num?)
                                          ?.toDouble() ??
                                      0,
                                  userIdOverride: widget.userIdOverride,
                                  cardUserNameOverride: widget.bannerTitle,
                                  validThruDate:
                                      '${_selectedLogDate.day}/${_selectedLogDate.month}/${_selectedLogDate.year}',
                                  onToggleMacros: (showMacros) {
                                    _jiggleAnimationController?.forward(
                                        from: 0);
                                    setState(() {
                                      _showMacrosTotal = showMacros;
                                      for (var doc in _foodDocs) {
                                        _foodMacrosVisibility[doc.id] =
                                            showMacros;
                                      }
                                    });
                                  },
                                ),
                          if (_isDayFinished)
                            Positioned(
                              top: 10,
                              right: 12,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF10B981),
                                  size: 22,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedLogDate,
                        firstDate: DateTime(2020, 1, 1),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedLogDate = picked;
                          _deleteMode = false;
                        });
                        await populateFoodItems();
                        await _fetchDailyLogForDate(picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month,
                            color: Color(0xFF6366F1),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatDate(_selectedLogDate),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Tabs
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Consumer<CategoryService>(
                      builder: (context, categoryService, _) {
                        return Row(
                          children: _tabs.map((tab) {
                            bool isSelected =
                                categoryService.selectedCategory == tab;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () {
                                  categoryService.setSelectedCategory(tab);
                                  populateFoodItems();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF6366F1)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFF6366F1),
                                      width: isSelected ? 0 : 2,
                                    ),
                                  ),
                                  child: Text(
                                    tab,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFF6366F1),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.indigo.shade600,
                              Colors.blue.shade700,
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Category Totals Header
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _showMacrosTotal = !_showMacrosTotal;
                                    // When card is tapped, flip all food items to match card state
                                    for (var doc in _foodDocs) {
                                      _foodMacrosVisibility[doc.id] =
                                          _showMacrosTotal;
                                    }
                                  });
                                },
                                child: Consumer<CategoryService>(
                                  builder: (context, categoryService, _) {
                                    // Fetch totals when category changes
                                    if (_lastFetchedCategory !=
                                        categoryService.selectedCategory) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        _fetchCategoryTotals(
                                            categoryService.selectedCategory);
                                      });
                                    }

                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color:
                                                Colors.white.withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Total',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                if (!_showMacrosTotal)
                                                  Text(
                                                    '$_totalCalories kcal',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                    ),
                                                  )
                                                else
                                                  Text(
                                                    'Protein: ${_roundMacro(_totalProtein)}g | Carbs: ${_roundMacro(_totalCarbs)}g | Fat: ${_roundMacro(_totalFat)}g',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  _showMacrosTotal
                                                      ? Icons.fastfood
                                                      : Icons.show_chart,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Expanded(
                                child: Stack(
                                  children: [
                                    ListView.builder(
                                      itemCount: _foodDocs.length,
                                      itemBuilder: (context, index) {
                                        final doc = _foodDocs[index];
                                        return Container(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 6),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Colors.white.withOpacity(0.95),
                                                Colors.blue.shade50
                                                    .withOpacity(0.9),
                                              ],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.1),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: GestureDetector(
                                            onTap: () {
                                              _handleFoodItemTap(doc.id);
                                            },
                                            child: Column(
                                              children: [
                                                ListTile(
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  title: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        doc["food_description"],
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.black87,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                      if (doc["food_portion"] !=
                                                              null &&
                                                          (doc["food_portion"]
                                                                  as String)
                                                              .isNotEmpty)
                                                        Text(
                                                          '(${doc["food_portion"]})',
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey.shade600,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w400,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  trailing: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    children: [
                                                      if (_deleteMode &&
                                                          !_isDayFinished)
                                                        GestureDetector(
                                                          onTap: () async {
                                                            await _deleteFoodItem(
                                                                doc.id);
                                                          },
                                                          child: Icon(
                                                            Icons
                                                                .delete_outline,
                                                            color: Colors
                                                                .red.shade400,
                                                            size: 24,
                                                          ),
                                                        )
                                                      else
                                                        Container(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                            horizontal: 12,
                                                            vertical: (_foodMacrosVisibility[
                                                                        doc.id] ??
                                                                    _showMacrosTotal)
                                                                ? 1
                                                                : 4,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            gradient:
                                                                LinearGradient(
                                                              colors: [
                                                                Colors.orange
                                                                    .shade400,
                                                                Colors.orange
                                                                    .shade600,
                                                              ],
                                                            ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12),
                                                          ),
                                                          child: (_foodMacrosVisibility[
                                                                      doc.id] ??
                                                                  _showMacrosTotal)
                                                              ? Column(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Text(
                                                                      '${_roundMacro(doc["food_protein"])}g Protein',
                                                                      style:
                                                                          const TextStyle(
                                                                        color: Colors
                                                                            .white,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontSize:
                                                                            10,
                                                                        height:
                                                                            1.2,
                                                                      ),
                                                                    ),
                                                                    Text(
                                                                      '${_roundMacro(doc["food_carbs"])}g Carbs',
                                                                      style:
                                                                          const TextStyle(
                                                                        color: Colors
                                                                            .white,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontSize:
                                                                            10,
                                                                        height:
                                                                            1.2,
                                                                      ),
                                                                    ),
                                                                    Text(
                                                                      '${_roundMacro(doc["food_fat"])}g Fat',
                                                                      style:
                                                                          const TextStyle(
                                                                        color: Colors
                                                                            .white,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontSize:
                                                                            10,
                                                                        height:
                                                                            1.2,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                )
                                                              : Text(
                                                                  '${_roundMacro(doc["food_calories"])} kcal',
                                                                  style:
                                                                      const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        12,
                                                                  ),
                                                                ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                // Show emoji picker when in readOnly mode
                                                if (widget.readOnly &&
                                                    (_showEmojiPicker[doc.id] ??
                                                        false))
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            12),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.grey.shade100,
                                                      borderRadius:
                                                          const BorderRadius
                                                              .only(
                                                        bottomLeft:
                                                            Radius.circular(12),
                                                        bottomRight:
                                                            Radius.circular(12),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceEvenly,
                                                      children: [
                                                        GestureDetector(
                                                          onTap: () =>
                                                              _addReaction(
                                                                  doc.id, '🔥'),
                                                          child: const Text(
                                                              '🔥',
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      32)),
                                                        ),
                                                        GestureDetector(
                                                          onTap: () =>
                                                              _addReaction(
                                                                  doc.id, '😈'),
                                                          child: const Text(
                                                              '😈',
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      32)),
                                                        ),
                                                        GestureDetector(
                                                          onTap: () =>
                                                              _addReaction(
                                                                  doc.id, '💪'),
                                                          child: const Text(
                                                              '💪',
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      32)),
                                                        ),
                                                        GestureDetector(
                                                          onTap: () =>
                                                              _addReaction(
                                                                  doc.id, '❤️'),
                                                          child: const Text(
                                                              '❤️',
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      32)),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                // Show reaction confirmation when in readOnly mode after adding emoji
                                                if (widget.readOnly &&
                                                    _reactionConfirmationFoodId ==
                                                        doc.id &&
                                                    _reactionFadeAnimation !=
                                                        null)
                                                  FadeTransition(
                                                    opacity:
                                                        _reactionFadeAnimation!,
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 16,
                                                        vertical: 8,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors
                                                            .green.shade50,
                                                        borderRadius:
                                                            const BorderRadius
                                                                .only(
                                                          bottomLeft:
                                                              Radius.circular(
                                                                  12),
                                                          bottomRight:
                                                              Radius.circular(
                                                                  12),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              _reactionConfirmationUsername ??
                                                                  '',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .grey
                                                                    .shade700,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          ),
                                                          Text(
                                                            _reactionConfirmationEmoji ??
                                                                '',
                                                            style:
                                                                const TextStyle(
                                                                    fontSize:
                                                                        24),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                // Show reactions when owner taps food item
                                                if (!widget.readOnly &&
                                                    (_showReactions[doc.id] ??
                                                        false) &&
                                                    _foodReactions[doc.id] !=
                                                        null &&
                                                    _foodReactions[doc.id]!
                                                        .isNotEmpty)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 8,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.blue.shade50,
                                                      borderRadius:
                                                          const BorderRadius
                                                              .only(
                                                        bottomLeft:
                                                            Radius.circular(12),
                                                        bottomRight:
                                                            Radius.circular(12),
                                                      ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children:
                                                          _foodReactions[
                                                                  doc.id]!
                                                              .map(
                                                                  (reaction) =>
                                                                      Padding(
                                                                        padding:
                                                                            const EdgeInsets.symmetric(
                                                                          vertical:
                                                                              2,
                                                                        ),
                                                                        child:
                                                                            Row(
                                                                          children: [
                                                                            Expanded(
                                                                              child: Text(
                                                                                reaction['username'] ?? 'Unknown',
                                                                                style: TextStyle(
                                                                                  color: Colors.grey.shade700,
                                                                                  fontWeight: FontWeight.w500,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            Text(
                                                                              reaction['emoji'] ?? '',
                                                                              style: const TextStyle(fontSize: 20),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ))
                                                              .toList(),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    if (_isDeletingItem)
                                      Container(
                                        color: Colors.black.withOpacity(0.3),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.white),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (!widget.readOnly)
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: <Widget>[
                                    FloatingActionButton(
                                      onPressed: _isDayFinished
                                          ? null
                                          : () {
                                              setState(() {
                                                _deleteMode = !_deleteMode;
                                              });
                                            },
                                      heroTag: 'delete',
                                      backgroundColor: _isDayFinished
                                          ? Colors.grey.shade400
                                          : _deleteMode
                                              ? Colors.red.shade600
                                              : Colors.red.shade400,
                                      child: Icon(_deleteMode
                                          ? Icons.close
                                          : Icons.delete_outline),
                                    ),
                                    FloatingActionButton(
                                      onPressed: _isDayFinished
                                          ? null
                                          : _showAddOptions,
                                      heroTag: 'add',
                                      backgroundColor: _isDayFinished
                                          ? Colors.grey.shade400
                                          : Colors.green.shade400,
                                      child: const Icon(Icons.add),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.hideNav
          ? null
          : Container(
              color: Colors.white,
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MenuPage(),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                                color: Colors.grey.shade200, width: 1),
                          ),
                        ),
                        child: Center(
                          child: Icon(Icons.person, size: 24),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right:
                              BorderSide(color: Colors.grey.shade200, width: 1),
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.credit_card,
                            size: 24, color: Color(0xFF6366F1)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RecipesPage()),
                        );
                      },
                      child: Container(
                        child: const Center(
                          child: Icon(Icons.restaurant, size: 24),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
