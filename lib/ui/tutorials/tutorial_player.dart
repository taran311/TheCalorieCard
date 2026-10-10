import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/tutorials/tutorial_mock.dart';

/// What the pretend finger does on a step.
enum TAct { none, tap, type, swipe }

/// One step of a tutorial: a caption, and optionally an action the pretend
/// finger performs on [target], after which [apply] changes the practice
/// state (and [then] a moment later, e.g. a reply arriving).
class TStep {
  final String title;
  final String body;

  /// Id of the practice widget to point at. "tabs#1/4" means the 2nd of 4
  /// equal slices of "tabs" (one meal tab).
  final String? target;
  final TAct act;

  /// Text typed for [TAct.type].
  final String text;
  final void Function(TutorialState s, String typed)? onType;
  final void Function(TutorialState s)? apply;
  final void Function(TutorialState s)? then;
  final Duration thenAfter;

  /// What to highlight once the step has played (defaults to nothing).
  final String? focus;

  const TStep({
    required this.title,
    required this.body,
    this.target,
    this.act = TAct.none,
    this.text = '',
    this.onType,
    this.apply,
    this.then,
    this.thenAfter = const Duration(milliseconds: 1600),
    this.focus,
  });

  /// Applies the whole step instantly (used to rebuild earlier steps).
  void complete(TutorialState s) {
    if (act == TAct.type && onType != null) onType!(s, text);
    apply?.call(s);
    then?.call(s);
  }
}

class Tutorial {
  final String id;
  final String emoji;
  final String title;
  final String subtitle;
  final void Function(TutorialState s)? setup;
  final List<TStep> steps;

  const Tutorial({
    required this.id,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.steps,
    this.setup,
  });
}

/// Plays a [Tutorial] on a practice copy of the app.
///
/// Safe by design: the practice app only ever changes a [TutorialState]
/// held in this widget's memory. Nothing is read from or written to the
/// user's real data, so leaving early, going back, or the app being closed
/// mid-way can't change anything.
class TutorialPlayer extends StatefulWidget {
  final Tutorial tutorial;

  const TutorialPlayer({super.key, required this.tutorial});

  /// Opens [tutorial] full screen. Completes with true if it was finished.
  static Future<bool> open(BuildContext context, Tutorial tutorial) async {
    final done = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TutorialPlayer(tutorial: tutorial),
      ),
    );
    return done ?? false;
  }

  @override
  State<TutorialPlayer> createState() => _TutorialPlayerState();
}

class _TutorialPlayerState extends State<TutorialPlayer>
    with SingleTickerProviderStateMixin {
  final _stage = GlobalKey(debugLabel: 'tutorial-stage');
  final Map<String, GlobalKey> _keys = {};
  final _scroll = ScrollController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  late TutorialState _s = _stateBefore(0);
  int _i = 0;
  int _token = 0;
  bool _done = false;
  String? _highlight;
  Offset? _finger;
  bool _pressing = false;

  Tutorial get _t => widget.tutorial;
  TStep get _step => _t.steps[_i];
  bool get _last => _i == _t.steps.length - 1;

  GlobalKey _k(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'tutorial-$id'));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play(0));
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
    _token++;
    _pulse.dispose();
    _scroll.dispose();
    super.dispose();
  }

  TutorialState _stateBefore(int i) {
    final s = TutorialState();
    _t.setup?.call(s);
    for (var j = 0; j < i && j < _t.steps.length; j++) {
      _t.steps[j].complete(s);
    }
    return s;
  }

  /// Waits [ms]; false if the step changed meanwhile (or we've closed).
  Future<bool> _wait(int ms, int token) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    return mounted && token == _token;
  }

  Future<void> _reveal(String? id) async {
    if (id == null) return;
    final ctx = _k(id.split('#').first).currentContext;
    if (ctx == null) return;
    try {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.4,
        duration: const Duration(milliseconds: 250),
      );
    } catch (_) {}
  }

  /// The box of [id] inside the stage, or null if it isn't showing.
  Rect? _rectOf(String? id) {
    if (id == null) return null;
    final parts = id.split('#');
    final box = _k(parts.first).currentContext?.findRenderObject();
    final stage = _stage.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        stage is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        !stage.attached) {
      return null;
    }
    final a = box.localToGlobal(Offset.zero, ancestor: stage);
    final b = box.localToGlobal(box.size.bottomRight(Offset.zero),
        ancestor: stage);
    var rect = Rect.fromPoints(a, b);
    // "tabs#1/4": one slice of a row.
    if (parts.length == 2) {
      final slice = parts[1].split('/');
      final index = int.tryParse(slice.first) ?? 0;
      final count = int.tryParse(slice.length > 1 ? slice[1] : '1') ?? 1;
      final w = rect.width / math.max(1, count);
      rect = Rect.fromLTWH(rect.left + w * index, rect.top, w, rect.height);
    }
    return rect;
  }

  Future<void> _play(int i) async {
    if (i < 0 || i >= _t.steps.length) return;
    final token = ++_token;
    setState(() {
      _i = i;
      _s = _stateBefore(i);
      _done = false;
      _highlight = _t.steps[i].target;
      _finger = null;
      _pressing = false;
    });
    final step = _t.steps[i];

    if (!await _wait(120, token)) return;
    await _reveal(step.target);
    if (!await _wait(80, token)) return;

    final rect = _rectOf(step.target);
    if (step.act != TAct.none && rect != null) {
      setState(() => _finger = step.act == TAct.swipe
          ? Offset(rect.right - 24, rect.center.dy)
          : rect.center);
      if (!await _wait(650, token)) return;

      switch (step.act) {
        case TAct.tap:
          setState(() => _pressing = true);
          if (!await _wait(180, token)) return;
          setState(() => _pressing = false);
        case TAct.type:
          setState(() => _pressing = true);
          if (!await _wait(150, token)) return;
          setState(() => _pressing = false);
          for (var c = 1; c <= step.text.length; c++) {
            if (!await _wait(32, token)) return;
            setState(() => step.onType?.call(_s, step.text.substring(0, c)));
          }
          if (!await _wait(250, token)) return;
        case TAct.swipe:
          setState(() {
            _pressing = true;
            _finger = Offset(rect.left + 24, rect.center.dy);
          });
          if (!await _wait(520, token)) return;
          setState(() => _pressing = false);
        case TAct.none:
          break;
      }
    }

    if (!mounted || token != _token) return;
    setState(() {
      step.apply?.call(_s);
      _highlight = step.focus;
      if (step.act == TAct.none) _highlight = step.focus ?? step.target;
    });

    if (step.then != null) {
      if (!await _wait(step.thenAfter.inMilliseconds, token)) return;
      setState(() => step.then!(_s));
    }

    if (!await _wait(60, token)) return;
    await _reveal(_highlight);
    if (!mounted || token != _token) return;
    setState(() {
      _done = true;
      _finger = null;
    });
  }

  void _next() {
    if (_last) {
      Navigator.of(context).pop(true);
    } else {
      _play(_i + 1);
    }
  }

  void _back() {
    if (_i > 0) _play(_i - 1);
  }

  @override
  Widget build(BuildContext context) {
    final steps = _t.steps.length;
    return PopScope(
      // The pretend app keeps its own state, so system Back just moves a
      // step back instead of closing half way. Use X to leave.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Leave tutorial',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    Expanded(
                      child: Text(
                        '${_t.emoji}  ${_t.title}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.amber100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Practice',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppText.amber800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildStage(),
                    ),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 452),
                  child: _buildCaption(steps),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gray300, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        key: _stage,
        children: [
          // Look but don't touch: taps go to the caption's buttons.
          Positioned.fill(
            child: IgnorePointer(
              child: MockApp(s: _s, k: _k, scroll: _scroll),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: _HighlightPainter(
                    hole: _rectOf(_highlight),
                    pulse: _pulse.value,
                  ),
                ),
              ),
            ),
          ),
          if (_finger != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
              left: _finger!.dx - 20,
              top: _finger!.dy - 20,
              child: IgnorePointer(
                child: AnimatedScale(
                  scale: _pressing ? 0.78 : 1,
                  duration: const Duration(milliseconds: 140),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.85),
                      border: Border.all(color: AppColors.primary, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // A gentle reminder that this is pretend.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3),
                color: AppColors.amber100.withValues(alpha: 0.92),
                child: Text(
                  'Practice mode · your real card is never touched',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppText.amber800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaption(int steps) {
    final step = _step;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
      decoration: AppDecor.card,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Column(
          key: ValueKey(_i),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var d = 0; d < steps; d++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: d == _i ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: d <= _i
                                ? AppColors.primary
                                : AppColors.gray300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${_i + 1} of $steps',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(width: 6),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              step.title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                step.body,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.gray600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (_i > 0)
                  TextButton(onPressed: _back, child: const Text('Back')),
                const Spacer(),
                if (!_done)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                FilledButton(
                  onPressed: _next,
                  child: Text(_last ? 'Finish' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightPainter extends CustomPainter {
  final Rect? hole;
  final double pulse;

  _HighlightPainter({required this.hole, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final h = hole;
    if (h == null) return;
    final r = h.inflate(5);
    final rrect = RRect.fromRectAndRadius(r, const Radius.circular(14));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(
        path, Paint()..color = Colors.black.withValues(alpha: 0.32));
    final wave = Curves.easeOut.transform(pulse);
    final grow = 2 + 7 * wave;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.inflate(grow), Radius.circular(14 + grow)),
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
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.hole != hole || old.pulse != pulse;
}
