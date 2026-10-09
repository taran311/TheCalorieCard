import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';

/// One stop on a spotlight tour: the widget to highlight and what to say.
class TourStep {
  /// Put this key on the widget to highlight. Steps whose widget isn't on
  /// screen are skipped.
  final GlobalKey target;
  final String title;
  final String body;

  /// Space between the widget and the highlight box.
  final double padding;

  /// Corner radius of the highlight box.
  final double radius;

  const TourStep({
    required this.target,
    required this.title,
    required this.body,
    this.padding = 8,
    this.radius = 16,
  });
}

/// Keys for the bottom bar / sidebar, so the home tour can point at them.
/// Each app shell has its own set (two shells can briefly overlap while
/// one replaces the other).
class ShellTourKeys {
  final coach = GlobalKey(debugLabel: 'tour-coach');
  final recipes = GlobalKey(debugLabel: 'tour-recipes');
  final friends = GlobalKey(debugLabel: 'tour-friends');
  final profile = GlobalKey(debugLabel: 'tour-profile');

  /// Whether the Card tab is the one showing (kept up to date by the shell),
  /// so the home tour never runs over another tab.
  bool cardTabShowing = true;
}

/// Shares a shell's [ShellTourKeys] with the pages inside it.
class ShellTourScope extends InheritedWidget {
  final ShellTourKeys keys;

  const ShellTourScope({super.key, required this.keys, required super.child});

  static ShellTourKeys? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellTourScope>()?.keys;

  @override
  bool updateShouldNotify(ShellTourScope oldWidget) => keys != oldWidget.keys;
}

/// Dims the screen, cuts a glowing box around one part at a time and
/// explains it, with Back / Next / Skip.
class SpotlightTour {
  SpotlightTour._();

  static final Set<String> _seenThisSession = {};
  static bool _running = false;

  /// Shows the tour [id] once per account (remembered on users/{uid}).
  /// [canStart] is checked again just before it appears, so it never pops
  /// up over the keyboard, a dialog or another tab.
  ///
  /// Returns false if it couldn't show yet (worth trying again later).
  static Future<bool> showOnce(
    BuildContext context, {
    required String id,
    required List<TourStep> steps,
    bool Function()? canStart,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true;
    final seenKey = '$uid:$id';
    if (_seenThisSession.contains(seenKey)) return true;
    if (_running) return false;
    _running = true;
    try {
      final doc = FirebaseFirestore.instance.collection('users').doc(uid);
      try {
        final seen = (await doc.get()).data()?['tours_seen'];
        if (seen is List && seen.contains(id)) {
          _seenThisSession.add(seenKey);
          return true;
        }
      } catch (_) {
        // Offline: show it; we'll try to remember afterwards.
      }
      if (!context.mounted) return false;
      if (canStart != null && !canStart()) return false;

      final shown = await show(context, steps: steps);
      if (!shown) return false;
      _seenThisSession.add(seenKey);
      try {
        await doc.set({
          'tours_seen': FieldValue.arrayUnion([id]),
        }, SetOptions(merge: true));
      } catch (_) {}
      return true;
    } finally {
      _running = false;
    }
  }

  /// Shows the tour now and completes when it's finished, skipped or closed
  /// with Back. Returns false if there was nothing on screen to show.
  static Future<bool> show(
    BuildContext context, {
    required List<TourStep> steps,
  }) async {
    final live = steps.where((s) => s.target.currentContext != null).toList();
    if (live.isEmpty) return false;
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    if (navigator == null) return false;

    // A see-through route, so system Back closes the tour cleanly.
    // It returns false only if nothing could be highlighted.
    final result = await navigator.push(PageRouteBuilder<bool>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => _SpotlightOverlay(steps: live),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
    return result ?? true;
  }
}

class _SpotlightOverlay extends StatefulWidget {
  final List<TourStep> steps;

  const _SpotlightOverlay({required this.steps});

  @override
  State<_SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<_SpotlightOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  int _index = 0;
  Rect? _from;
  Rect? _to;
  bool _busy = false;
  bool _finishing = false;
  bool _everShown = false;

  TourStep get _step => widget.steps[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(0));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Rect? _measure(TourStep step) {
    final box = step.target.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    // Measured against the tour's own overlay, which isn't always the
    // whole window (sign-up sits in a centred panel on wide screens).
    final ref = Navigator.maybeOf(context)?.overlay?.context.findRenderObject();
    final ancestor = ref is RenderBox && ref.attached ? ref : null;
    // Both corners, so scaled widgets (e.g. inside a FittedBox) measure right.
    final a = box.localToGlobal(Offset.zero, ancestor: ancestor);
    final b = box.localToGlobal(box.size.bottomRight(Offset.zero),
        ancestor: ancestor);
    return Rect.fromPoints(a, b).inflate(step.padding);
  }

  Future<void> _goTo(int i) async {
    if (_busy || _finishing) return;
    _busy = true;
    final step = i >= _index ? 1 : -1;
    try {
      var next = i;
      while (next >= 0 && next < widget.steps.length) {
        final ctx = widget.steps[next].target.currentContext;
        if (ctx != null) {
          try {
            await Scrollable.ensureVisible(
              ctx,
              alignment: 0.35,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          } catch (_) {}
          if (!mounted) return;
          final rect = _measure(widget.steps[next]);
          if (rect != null) {
            setState(() {
              _from = _current ?? rect;
              _to = rect;
              _index = next;
              _everShown = true;
            });
            await _move.forward(from: 0);
            return;
          }
        }
        // Gone from the screen since the tour began: skip it.
        next += step;
      }
      if (next >= widget.steps.length) _finish();
      // Off the start going back: stay where we are.
    } finally {
      _busy = false;
    }
  }

  /// Where the box is drawn: animating between steps, then following the
  /// target live (keyboard closing, scrolling, resizing).
  Rect? get _current {
    final from = _from, to = _to;
    if (to == null) return null;
    final live = _move.isAnimating || _busy ? to : (_measure(_step) ?? to);
    if (from == null) return live;
    return Rect.lerp(from, live, Curves.easeOutCubic.transform(_move.value));
  }

  void _finish() {
    if (_finishing || !mounted) return;
    _finishing = true;
    final route = ModalRoute.of(context);
    if (route == null) return;
    // Close this tour, never whatever might be on top of it.
    if (route.isCurrent) {
      Navigator.of(context).pop(_everShown);
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  void _next() {
    if (_busy) return;
    if (_index >= widget.steps.length - 1) {
      _finish();
    } else {
      _goTo(_index + 1);
    }
  }

  void _back() {
    if (!_busy && _index > 0) _goTo(_index - 1);
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final last = _index == widget.steps.length - 1;

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: Listenable.merge([_move, _pulse]),
        builder: (context, _) {
          final hole = _current;
          return Stack(
            children: [
              // Dimmed screen with a hole; tapping anywhere moves on.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _next,
                  child: CustomPaint(
                    painter: _SpotlightPainter(
                      hole: hole,
                      radius: _step.radius,
                      pulse: _pulse.value,
                    ),
                  ),
                ),
              ),
              if (hole != null)
                Positioned.fill(
                  child: CustomSingleChildLayout(
                    delegate: _CaptionLayout(hole: hole, safe: safe),
                    child: _Caption(
                      step: _step,
                      index: _index,
                      count: widget.steps.length,
                      last: last,
                      onNext: _next,
                      onBack: _index > 0 ? _back : null,
                      onSkip: _finish,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Puts the caption under the highlight if it fits, else above it, and
/// always inside the safe area.
class _CaptionLayout extends SingleChildLayoutDelegate {
  final Rect hole;
  final EdgeInsets safe;

  static const _gap = 14.0;
  static const _margin = 16.0;

  _CaptionLayout({required this.hole, required this.safe});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width =
        math.max(0.0, math.min(constraints.maxWidth - _margin * 2, 360.0));
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(
          0.0, constraints.maxHeight - safe.vertical - _margin * 2),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final left = (hole.center.dx - child.width / 2)
        .clamp(_margin, math.max(_margin, size.width - child.width - _margin))
        .toDouble();
    final minTop = safe.top + _margin;
    final maxTop =
        math.max(minTop, size.height - safe.bottom - _margin - child.height);

    final below = hole.bottom + _gap;
    final above = hole.top - _gap - child.height;
    final double top;
    if (below <= maxTop) {
      top = below;
    } else if (above >= minTop) {
      top = above;
    } else {
      // Neither fits fully: use whichever side has more room.
      final roomBelow = size.height - hole.bottom;
      top = roomBelow >= hole.top ? maxTop : minTop;
    }
    return Offset(left, top.clamp(minTop, maxTop).toDouble());
  }

  @override
  bool shouldRelayout(_CaptionLayout old) =>
      old.hole != hole || old.safe != safe;
}

class _Caption extends StatelessWidget {
  final TourStep step;
  final int index;
  final int count;
  final bool last;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  const _Caption({
    required this.step,
    required this.index,
    required this.count,
    required this.last,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Column(
            key: ValueKey(index),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 4),
                      width: i == index ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            i == index ? AppColors.primary : AppColors.gray300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '${index + 1} of $count',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                step.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  step.body,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppColors.gray600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (!last)
                    TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.muted),
                      child: const Text('Skip'),
                    ),
                  const Spacer(),
                  if (onBack != null)
                    TextButton(onPressed: onBack, child: const Text('Back')),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                    ),
                    child: Text(last ? 'Got it' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  final double radius;
  final double pulse;

  _SpotlightPainter({
    required this.hole,
    required this.radius,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.7);
    final h = hole;
    if (h == null) {
      canvas.drawRect(Offset.zero & size, dim);
      return;
    }
    final rrect = RRect.fromRectAndRadius(h, Radius.circular(radius));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(path, dim);

    // The "flash": a gold ring that breathes out from the box.
    final wave = Curves.easeOut.transform(pulse);
    final grow = 2 + 8 * wave;
    canvas.drawRRect(
      RRect.fromRectAndRadius(h.inflate(grow), Radius.circular(radius + grow)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFFBBF24).withValues(alpha: 0.9 * (1 - wave)),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.radius != radius || old.pulse != pulse;
}
