import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/ui/calorie_card.dart';

/// The calorie card on the Card screen.
///
/// Front: what's left to spend. Tap to flip and see protein, carbs and fat.
/// Shows today's live balance, or a past day's balance via the overrides.
class CreditCard extends StatefulWidget {
  final int? initialCalories;
  final int? caloriesOverride;
  final double? proteinOverride;
  final double? carbsOverride;
  final double? fatsOverride;
  final ValueChanged<bool>? onToggleMacros;

  /// Use the overrides instead of the live balance (past days).
  final bool skipFetch;

  /// Day the balance belongs to, as d/m/yyyy.
  final String? validThruDate;
  final String? userIdOverride;
  final String? cardUserNameOverride;

  const CreditCard({
    super.key,
    this.initialCalories,
    this.caloriesOverride,
    this.proteinOverride,
    this.carbsOverride,
    this.fatsOverride,
    this.onToggleMacros,
    this.skipFetch = false,
    this.validThruDate,
    this.userIdOverride,
    this.cardUserNameOverride,
  });

  @override
  State<CreditCard> createState() => _CreditCardWidgetState();
}

class _CreditCardWidgetState extends State<CreditCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  bool _loading = true;
  int _calories = 0;
  double _protein = 0, _carbs = 0, _fats = 0;
  double? _proteinGoal, _carbsGoal, _fatsGoal;

  @override
  void initState() {
    super.initState();
    if (widget.skipFetch) {
      _calories = widget.caloriesOverride ?? widget.initialCalories ?? 0;
      _protein = widget.proteinOverride ?? 0;
      _carbs = widget.carbsOverride ?? 0;
      _fats = widget.fatsOverride ?? 0;
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  double? _num(dynamic v) => BalanceService.number(v);

  Future<void> _load() async {
    try {
      final userId =
          widget.userIdOverride ?? FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final doc = await BalanceService.userDataDoc(userId);
      if (!mounted) return;
      if (doc == null) {
        setState(() => _loading = false);
        return;
      }
      final data = doc.data() ?? {};

      // A balance saved on an earlier day hasn't been reset yet (e.g. a
      // friend who hasn't opened the app today). Show today's real
      // balance: goals minus what's been logged today.
      Macros? live;
      final goals = BalanceService.goalsFrom(data);
      if (!widget.skipFetch &&
          goals != null &&
          data['balance_date'] != BalanceService.dateKey(BalanceService.now())) {
        live = goals - await BalanceService.todaysTotals(userId);
        if (!mounted) return;
      }

      setState(() {
        _proteinGoal = _num(data['protein_goal']);
        _carbsGoal = _num(data['carbs_goal']);
        _fatsGoal = _num(data['fats_goal']);
        if (!widget.skipFetch) {
          _calories = live?.calories.round() ??
              _num(data['calories'])?.round() ??
              widget.initialCalories ??
              (BalanceService.calorieGoalFrom(data)?.round() ?? 0);
          _protein = live?.protein ??
              _num(data['protein_balance']) ??
              _proteinGoal ??
              0;
          _carbs = live?.carbs ?? _num(data['carbs_balance']) ?? _carbsGoal ?? 0;
          _fats = live?.fat ?? _num(data['fats_balance']) ?? _fatsGoal ?? 0;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle() {
    final showMacros = _flip.value < 0.5;
    if (showMacros) {
      _flip.forward();
    } else {
      _flip.reverse();
    }
    widget.onToggleMacros?.call(showMacros);
  }

  bool get _isToday {
    final d = widget.validThruDate;
    if (d == null) return true;
    final now = BalanceService.now();
    return d == '${now.day}/${now.month}/${now.year}';
  }

  /// 09/10 style date for the card's "valid thru" spot.
  String _validThru() {
    final parts = (widget.validThruDate ?? '').split('/');
    DateTime d = DateTime.now();
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        d = DateTime(year, month, day);
      }
    }
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  /// "9 Oct" style date for the back of the card.
  String _shortDate() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final parts = (widget.validThruDate ?? '').split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (day != null && month != null && month >= 1 && month <= 12) {
        return '$day ${months[month - 1]}';
      }
    }
    final now = DateTime.now();
    return '${now.day} ${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    // Past days are passed in directly; read them fresh each build.
    final calories = widget.skipFetch && widget.caloriesOverride != null
        ? widget.caloriesOverride!
        : _calories;
    final protein = widget.skipFetch && widget.proteinOverride != null
        ? widget.proteinOverride!
        : _protein;
    final carbs = widget.skipFetch && widget.carbsOverride != null
        ? widget.carbsOverride!
        : _carbs;
    final fats = widget.skipFetch && widget.fatsOverride != null
        ? widget.fatsOverride!
        : _fats;

    final holderSource = widget.cardUserNameOverride ??
        FirebaseAuth.instance.currentUser?.email ??
        '';
    final holder = holderSource.contains('@')
        ? cardholderFromEmail(holderSource)
        : holderSource;

    final label = calories < 0
        ? (_isToday ? 'Over budget today' : 'Over budget')
        : (_isToday ? 'Left to spend today' : 'Left that day');

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth - 32, 380.0);
        // Real-card proportions, with a floor so name, pills and date
        // always fit on narrow phones.
        final height = math.max(width / 1.7, 190.0);

        Widget sized(Widget child) =>
            SizedBox(width: width, height: height, child: child);

        if (_loading) return sized(const CalorieCardSkeleton());

        final macros = [
          CardMacro(
            name: 'Protein',
            remaining: protein,
            goal: _proteinGoal,
            color: CalorieCardColors.protein,
          ),
          CardMacro(
            name: 'Carbs',
            remaining: carbs,
            goal: _carbsGoal,
            color: CalorieCardColors.carbs,
          ),
          CardMacro(
            name: 'Fat',
            remaining: fats,
            goal: _fatsGoal,
            color: CalorieCardColors.fat,
          ),
        ];
        final front = CalorieCardFront(
          amount: calories,
          macros: macros,
          holder: holder,
          validThru: _validThru(),
        );
        final back = CalorieCardBack(footnote: _shortDate(), macros: macros);

        return Semantics(
          button: true,
          label: 'Calorie card. $label: ${formatCardKcal(calories)} kcal. '
              'Tap to see macros.',
          child: GestureDetector(
            onTap: _toggle,
            child: AnimatedBuilder(
              animation: _flip,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_flip.value);
                final angle = t * math.pi;
                final showBack = t > 0.5;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(angle),
                  child: showBack
                      ? Transform(
                          // Un-mirror the back face.
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(math.pi),
                          child: sized(back),
                        )
                      : sized(front),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
