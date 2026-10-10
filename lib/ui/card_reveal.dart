import 'dart:async';

import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/spotlight_tour.dart';

/// The end of sign-up: the card "prints" while your goals are saved, then
/// your name and date appear, the balance counts up, and a two-step tour
/// shows the card and the balance. (Macros and the rest are covered in
/// Tutorials, so sign-up stays short.)
class CardRevealPage extends StatefulWidget {
  /// Saves the card. Runs while it prints; throws if saving fails.
  final Future<void> Function() save;

  /// Called from "Start using it".
  final VoidCallback onDone;

  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final String holder;
  final CardDesign design;

  const CardRevealPage({
    super.key,
    required this.save,
    required this.onDone,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.holder,
    this.design = CardDesign.midnight,
  });

  @override
  State<CardRevealPage> createState() => _CardRevealPageState();
}

enum _Stage { printing, ready, failed }

class _CardRevealPageState extends State<CardRevealPage>
    with TickerProviderStateMixin {
  static const _lines = [
    'Working out what you burn each day…',
    'Setting your protein, carbs and fat…',
    'Printing your card…',
  ];

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  final _tourKeys = CardTourKeys();
  final _cardKey = GlobalKey(debugLabel: 'reveal-card');

  _Stage _stage = _Stage.printing;
  int _line = 0;
  Timer? _lineTimer;
  bool _tourStarted = false;

  @override
  void initState() {
    super.initState();
    _slide.forward();
    _shimmer.repeat();
    _lineTimer = Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (!mounted) return;
      if (_line < _lines.length - 1) setState(() => _line++);
    });
    _print();
  }

  Future<void> _print() async {
    setState(() {
      _stage = _Stage.printing;
      _line = 0;
    });
    // Long enough to enjoy, never slower than the save itself.
    final minimum = Future.delayed(const Duration(milliseconds: 2300));
    try {
      await Future.wait([widget.save(), minimum]);
    } catch (_) {
      if (!mounted) return;
      _shimmer.stop();
      setState(() => _stage = _Stage.failed);
      return;
    }
    if (!mounted) return;
    _lineTimer?.cancel();
    _shimmer.stop();
    setState(() => _stage = _Stage.ready);
    // After the balance has counted up, explain the card.
    Future.delayed(const Duration(milliseconds: 1500), _startTour);
  }

  void _retry() {
    _shimmer.repeat();
    _lineTimer?.cancel();
    _lineTimer = Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (!mounted) return;
      if (_line < _lines.length - 1) setState(() => _line++);
    });
    _print();
  }

  bool _canTour() => mounted && _stage == _Stage.ready;

  void _startTour() {
    if (_tourStarted || !_canTour()) return;
    _tourStarted = true;
    SpotlightTour.showOnce(context, id: 'card_intro', canStart: _canTour, steps: [
      TourStep(
        target: _cardKey,
        title: 'This is your Calorie Card',
        body: 'Think of calories like money. Your card is topped up every '
            'day, and the food you log is spent from it.',
        padding: 6,
        radius: 24,
      ),
      TourStep(
        target: _tourKeys.balance,
        title: 'Your calorie balance',
        body: "What you've got left to spend today. If you go over, it "
            'turns red with a minus.',
        radius: 10,
      ),
    ]);
  }

  @override
  void dispose() {
    _lineTimer?.cancel();
    _slide.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  String get _today {
    final d = BalanceService.now();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}';
  }

  Widget _card() {
    final ready = _stage == _Stage.ready;
    return TweenAnimationBuilder<double>(
      // The balance counts up once the card is printed.
      tween: Tween(begin: 0, end: ready ? widget.calories.toDouble() : 0),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => CalorieCardFront(
        amount: value.round(),
        holder: ready ? widget.holder : '',
        validThru: ready ? _today : '--/--',
        design: widget.design,
        tourKeys: _tourKeys,
        macros: [
          CardMacro(
            name: 'Protein',
            remaining: ready ? widget.protein.toDouble() : 0,
            color: CalorieCardColors.protein,
          ),
          CardMacro(
            name: 'Carbs',
            remaining: ready ? widget.carbs.toDouble() : 0,
            color: CalorieCardColors.carbs,
          ),
          CardMacro(
            name: 'Fat',
            remaining: ready ? widget.fat.toDouble() : 0,
            color: CalorieCardColors.fat,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final ready = _stage == _Stage.ready;
    final failed = _stage == _Stage.failed;

    final card = AnimatedBuilder(
      animation: Listenable.merge([_slide, _shimmer]),
      builder: (context, child) {
        final t = reduceMotion
            ? 1.0
            : Curves.easeOutBack.transform(_slide.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: _slide.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 80 * (1 - t)),
            child: Stack(
              children: [
                child!,
                // A sheen sweeping across while it prints.
                if (!ready && !failed && !reduceMotion)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-2.2 + 3.4 * _shimmer.value, -1),
                              end: Alignment(-1.2 + 3.4 * _shimmer.value, 1),
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.22),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      child: KeyedSubtree(
        key: _cardKey,
        child: AspectRatio(aspectRatio: 1.7, child: _card()),
      ),
    );

    return PopScope(
      // No going back mid-print; after a failed save they can.
      canPop: failed,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          failed
                              ? "We couldn't print your card"
                              : ready
                                  ? 'Your card is ready'
                                  : 'Printing your card',
                          key: ValueKey(_stage),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          failed
                              ? 'Check your connection and try again.'
                              : ready
                                  ? 'Topped up with ${formatCardKcal(widget.calories)} '
                                      'kcal every morning.'
                                  : _lines[_line],
                          key: ValueKey('$_stage$_line'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      card,
                      const SizedBox(height: 32),
                      if (ready)
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primaryDark,
                            ),
                            onPressed: widget.onDone,
                            child: const Text(
                              'Start using it',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        )
                      else if (failed) ...[
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primaryDark,
                            ),
                            onPressed: _retry,
                            child: const Text(
                              'Try again',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Back to my details'),
                        ),
                      ] else
                        const Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
