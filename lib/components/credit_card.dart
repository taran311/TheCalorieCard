import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/components/calorie_currency_icon.dart';

class CreditCard extends StatefulWidget {
  final int? initialCalories;
  final int? caloriesOverride;
  final double? proteinOverride;
  final double? carbsOverride;
  final double? fatsOverride;
  final ValueChanged<bool>? onToggleMacros;
  final bool skipFetch;
  final VoidCallback? triggerFlash;
  final String? validThruDate;
  final String? userIdOverride;
  final String? cardUserNameOverride;

  const CreditCard({
    Key? key,
    this.initialCalories,
    this.caloriesOverride,
    this.proteinOverride,
    this.carbsOverride,
    this.fatsOverride,
    this.onToggleMacros,
    this.skipFetch = false,
    this.triggerFlash,
    this.validThruDate,
    this.userIdOverride,
    this.cardUserNameOverride,
  }) : super(key: key);

  @override
  State<CreditCard> createState() => _CreditCardWidgetState();
}

class _CreditCardWidgetState extends State<CreditCard>
    with TickerProviderStateMixin {
  int calories = 0;
  double proteinBalance = 0;
  double carbsBalance = 0;
  double fatsBalance = 0;
  bool _showMacros = false;
  bool isLoading = true;
  AnimationController? _flashController;
  Animation<double>? _flashAnimation;

  @override
  void initState() {
    super.initState();

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _flashAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _flashController!,
      curve: Curves.easeInOut,
    ));

    if (widget.skipFetch) {
      // Skip fetch entirely, just use overrides
      calories = widget.caloriesOverride ?? widget.initialCalories ?? 0;
      proteinBalance = widget.proteinOverride ?? 0;
      carbsBalance = widget.carbsOverride ?? 0;
      fatsBalance = widget.fatsOverride ?? 0;
      isLoading = false;
    } else {
      _fetchUserData(initialCalories: widget.initialCalories);
    }
  }

  @override
  void dispose() {
    _flashController?.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData({int? initialCalories}) async {
    try {
      final userId =
          widget.userIdOverride ?? FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();

      if (!mounted) return;

      if (snapshot.docs.isEmpty) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      final data = snapshot.docs.first.data();

      setState(() {
        calories = (data['calories'] as num?)?.toInt() ?? initialCalories ?? 0;
        proteinBalance = (data['protein_balance'] as num?)?.toDouble() ??
            (data['protein_goal'] as num?)?.toDouble() ??
            0;
        carbsBalance = (data['carbs_balance'] as num?)?.toDouble() ??
            (data['carbs_goal'] as num?)?.toDouble() ??
            0;
        fatsBalance = (data['fats_balance'] as num?)?.toDouble() ??
            (data['fats_goal'] as num?)?.toDouble() ??
            0;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.validThruDate ??
        '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Use widget props directly if skipFetch to avoid state updates
    final displayCalories = widget.skipFetch && widget.caloriesOverride != null
        ? widget.caloriesOverride!
        : calories;
    final displayProtein = widget.skipFetch && widget.proteinOverride != null
        ? widget.proteinOverride!
        : proteinBalance;
    final displayCarbs = widget.skipFetch && widget.carbsOverride != null
        ? widget.carbsOverride!
        : carbsBalance;
    final displayFats = widget.skipFetch && widget.fatsOverride != null
        ? widget.fatsOverride!
        : fatsBalance;

    return GestureDetector(
      onTap: () {
        _flashController?.forward(from: 0);
        final newState = !_showMacros;
        setState(() {
          _showMacros = newState;
        });
        widget.onToggleMacros?.call(newState);
      },
      child: Container(
        height: 155,
        width: 350,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6366F1),
              Color(0xFF4F46E5),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
            const BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 16,
                child: Text(
                  'TheCalorieCard',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 16,
                child: AnimatedBuilder(
                  animation:
                      _flashAnimation ?? const AlwaysStoppedAnimation(0.0),
                  builder: (context, child) {
                    final flashValue = _flashAnimation?.value ?? 0.0;
                    return Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withOpacity(flashValue * 0.8),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: child,
                    );
                  },
                  child: _showMacros
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Protein: ${displayProtein.toStringAsFixed(0)}g',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Carbs: ${displayCarbs.toStringAsFixed(0)}g',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Fats: ${displayFats.toStringAsFixed(0)}g',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Balance',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                CalorieCurrencyIcon(),
                                const SizedBox(width: 6),
                                Text(
                                  displayCalories.toString(),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Balance',
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.white.withOpacity(0.8),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              Positioned(
                top: 40,
                left: 16,
                child: Container(
                  width: 34,
                  height: 26,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.amber.shade300,
                        Colors.amber.shade600,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VALID THRU',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      today,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 16,
                right: 16,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    _getTruncatedName(widget.cardUserNameOverride ??
                        FirebaseAuth.instance.currentUser?.email ??
                        'User'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _getTruncatedName(String name) {
  if (name.length > 25) {
    return '${name.substring(0, 22)}...';
  }
  return name;
}
