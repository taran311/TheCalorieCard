import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:namer_app/ui/calorie_symbol.dart';

/// The calorie card's look, shared by the sign-in preview and the live card
/// on the Card screen so they always match.
class CalorieCardColors {
  CalorieCardColors._();

  /// Midnight indigo: the brand hue taken dark, so the card reads as part
  /// of the app (not a neutral black slab) and still stands out on both
  /// the light canvas and the indigo headers.
  static const top = Color(0xFF2E2A78);
  static const bottom = Color(0xFF15133D);
  static const chip = Color(0xFFFBBF24);
  static const overBudget = Color(0xFFFCA5A5);

  // Same macro hues as AppColors, one step lighter for the dark card.
  static const protein = Color(0xFFF87171);
  static const carbs = Color(0xFFFBBF24);
  static const fat = Color(0xFF38BDF8);
}

/// A card finish. Midnight is everyone's; the others are unlocked by
/// achievements and show on your card when friends look at it too.
/// All are dark enough for the white text and pills to stay readable.
class CardDesign {
  final String id;
  final String name;
  final Color top;
  final Color bottom;
  final Color chip;

  /// How to unlock it, shown in the picker.
  final String requirement;

  /// Optional middle colour, for a three-tone finish.
  final Color? middle;

  /// Only while you're Premium. When Premium ends the card goes back to
  /// Midnight, and this comes back if you rejoin.
  final bool premium;

  const CardDesign({
    required this.id,
    required this.name,
    required this.top,
    required this.bottom,
    required this.chip,
    required this.requirement,
    this.middle,
    this.premium = false,
  });

  static const midnight = CardDesign(
    id: 'midnight',
    name: 'Midnight',
    top: CalorieCardColors.top,
    bottom: CalorieCardColors.bottom,
    chip: CalorieCardColors.chip,
    requirement: 'Everyone has this one',
  );
  static const emerald = CardDesign(
    id: 'emerald',
    name: 'Emerald',
    top: Color(0xFF047857),
    bottom: Color(0xFF022C22),
    chip: Color(0xFFFBBF24),
    requirement: 'Reach a 7-day streak',
  );
  static const sunset = CardDesign(
    id: 'sunset',
    name: 'Sunset',
    top: Color(0xFFB45309),
    bottom: Color(0xFF4C0519),
    chip: Color(0xFFFDE68A),
    requirement: 'Calorie Sense 75%+ over 10 guesses in a month',
  );
  static const metal = CardDesign(
    id: 'metal',
    name: 'Metal',
    top: Color(0xFF6B7280),
    bottom: Color(0xFF111827),
    chip: Color(0xFFE5E7EB),
    requirement: 'Reach a 30-day streak',
  );

  static const aurora = CardDesign(
    id: 'aurora',
    name: 'Aurora',
    top: Color(0xFF6D28D9),
    middle: Color(0xFF0E7490),
    bottom: Color(0xFF0B1B3A),
    chip: Color(0xFF5EEAD4),
    requirement: 'Premium members only',
    premium: true,
  );

  static const all = [midnight, emerald, sunset, metal, aurora];

  static CardDesign byId(dynamic id) =>
      all.firstWhere((d) => d.id == id, orElse: () => midnight);
}

/// Turns "sam.jones@gmail.com" into "Sam Jones" for the card.
String cardholderFromEmail(String email) {
  final local = email.split('@').first.trim();
  if (local.isEmpty) return '';
  return local
      .split(RegExp(r'[._\-+]+'))
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join(' ');
}

String formatCardKcal(num value) {
  // round() throws on NaN/infinity; never let a bad number crash the card.
  if (!value.isFinite) return '0';
  final n = value.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < n.length; i++) {
    if (i > 0 && (n.length - i) % 3 == 0) b.write(',');
    b.write(n[i]);
  }
  return b.toString();
}

/// The rounded, dark body of the card.
class CalorieCardShell extends StatelessWidget {
  final Widget child;
  final CardDesign design;

  const CalorieCardShell({
    super.key,
    required this.child,
    this.design = CardDesign.midnight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            design.top,
            if (design.middle != null) design.middle!,
            design.bottom,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: design.bottom.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Front of the card, laid out like a bank card:
///
///   TheCalorieCard                      )))
///                                 LEFT TODAY
///   [chip]                       ⊂1,840 (the calorie symbol)
///
///   ● PROTEIN   ● CARBS   ● FAT
///   112g        180g      54g
///   SAM JONES                VALID THRU 09/10
class CalorieCardFront extends StatelessWidget {
  /// The balance in kcal. Negative means overspent.
  final num amount;

  /// Small caption above the balance saying what the number is, e.g.
  /// "LEFT TODAY" (none by default, for previews).
  final String? label;

  /// Remaining macros shown as pills under the balance.
  final List<CardMacro> macros;

  /// Cardholder name, shown bottom-left in capitals like a real card.
  /// Empty shows a faded placeholder; null hides the line.
  final String? holder;

  /// Bottom-right "valid thru" value, e.g. 09/10 for the day shown.
  final String? validThru;

  final CardDesign design;

  /// Marks each part of the card for the first-time spotlight tour.
  final CardTourKeys? tourKeys;

  /// See [BalanceTicker.memoryKey].
  final String? balanceMemoryKey;

  /// The day's been closed: a small "CLOSED ✓" stamp sits by the date.
  final bool closed;

  const CalorieCardFront({
    super.key,
    required this.amount,
    this.label,
    this.macros = const [],
    this.holder,
    this.validThru,
    this.design = CardDesign.midnight,
    this.tourKeys,
    this.balanceMemoryKey,
    this.closed = false,
  });

  @override
  Widget build(BuildContext context) {
    final over = amount < 0;
    final name = (holder ?? '').trim().toUpperCase();

    // The card is a fixed-size picture: let text grow a little with the
    // system setting, but not so far that the bigger balance overflows.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: CalorieCardShell(
        design: design,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Like a banking app's card (Monzo's): brand top-left, the
            // balance top-right, the chip on its own underneath. No
            // contactless mark: it means nothing here.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: _Wordmark(),
                ),
                const SizedBox(width: 16),
                // The balance is the hero; the caption says what it means.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (label != null)
                        Text(
                          label!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: over
                                ? CalorieCardColors.overBudget
                                : Colors.white.withValues(alpha: 0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                      BalanceTicker(
                        amount: amount,
                        textKey: tourKeys?.balance,
                        memoryKey: balanceMemoryKey,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            _CardChip(color: design.chip),
            // Flexible gaps: roomy on big cards, still fits on small ones.
            const Spacer(flex: 2),
            // Macros where a card number would be, each with a small caption
            // (like "VALID THRU") so it's clear what each number is.
            if (macros.isNotEmpty)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < macros.length; i++) ...[
                      if (i > 0) const SizedBox(width: 22),
                      MacroNumber(
                        macro: macros[i],
                        contentKey: tourKeys?.macro(i),
                      ),
                    ],
                  ],
                ),
              ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: holder == null
                      ? const SizedBox.shrink()
                      : _tourMark(
                          tourKeys?.holder,
                          AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          // Keep the name on the left like a real card
                          // (the default layout centres it).
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [...previous, if (current != null) current],
                          ),
                          child: Text(
                            name.isEmpty ? 'YOUR NAME' : name,
                            key: ValueKey(name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white
                                  .withValues(alpha: name.isEmpty ? 0.4 : 0.9),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                        ),
                ),
                if (closed) ...[
                  const SizedBox(width: 10),
                  const _ClosedStamp(),
                ],
                if (validThru != null) ...[
                  const SizedBox(width: 12),
                  Column(
                    key: tourKeys?.validThru,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VALID THRU',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        validThru!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "TheCalorieCard" in the corner, like a bank's name on its card.
/// The card's balance, written like money with the calorie symbol
/// ([CalorieSymbol]) in front. When it changes (food added, something
/// removed) the number rolls from the old balance to the new one, and a
/// small "−412" floats up off the card, like a payment going through.
/// Still with reduce motion.
class BalanceTicker extends StatefulWidget {
  final num amount;
  final Key? textKey;

  /// The card is rebuilt from scratch after each change, so the last
  /// balance shown is remembered under this key (one per person and day)
  /// to roll from. Null (a past day): never animates, since nothing is
  /// being spent there.
  final String? memoryKey;

  const BalanceTicker(
      {super.key, required this.amount, this.textKey, this.memoryKey});

  static final Map<String, double> _memory = {};

  @override
  State<BalanceTicker> createState() => _BalanceTickerState();
}

class _BalanceTickerState extends State<BalanceTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _chip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  num _change = 0;

  /// Where the number rolls from on first show (the last balance seen).
  double? _from;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final key = widget.memoryKey;
    final before = key == null ? null : BalanceTicker._memory[key];
    final now = widget.amount.toDouble();
    if (before != null &&
        now.isFinite &&
        (now - before).abs() >= 1 &&
        !MediaQuery.of(context).disableAnimations) {
      _from = before;
      _change = now - before;
      _chip.forward(from: 0);
    }
    _remember();
  }

  void _remember() {
    final key = widget.memoryKey;
    if (key != null && widget.amount.isFinite) {
      BalanceTicker._memory[key] = widget.amount.toDouble();
    }
  }

  @override
  void didUpdateWidget(BalanceTicker old) {
    super.didUpdateWidget(old);
    final change = widget.amount - old.amount;
    // Only today's live card (the one with a memory key) animates: on a
    // past day the number changing just means that day's figures loaded,
    // not that anything was spent.
    if (widget.memoryKey != null &&
        widget.memoryKey == old.memoryKey &&
        change.abs() >= 1 &&
        widget.amount.isFinite &&
        old.amount.isFinite &&
        !MediaQuery.of(context).disableAnimations) {
      _change = change;
      _chip.forward(from: 0);
    }
    _remember();
  }

  @override
  void dispose() {
    _chip.dispose();
    super.dispose();
  }

  Widget _number(double value) {
    final over = value < 0;
    final color = over ? CalorieCardColors.overBudget : Colors.white;
    final style = TextStyle(
      color: color,
      fontSize: 34,
      height: 1.0,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Like a banking app's balance: the symbol smaller than the number and
    // level with its top, "−⊂412" when over (like "−£412").
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (over) ExcludeSemantics(child: Text('−', style: style)),
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 2),
            child: CalorieSymbol(size: 27, color: color),
          ),
          Text(
            formatCardKcal(value),
            key: widget.textKey,
            semanticsLabel:
                '${over ? 'minus ' : ''}${formatCardKcal(value)} calories',
            style: style,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final target = widget.amount.isFinite ? widget.amount.toDouble() : 0.0;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.centerRight,
      children: [
        // Only today's live card rolls; a past day (no memory key) just
        // shows its number, so switching days never looks like spending.
        if (widget.memoryKey == null)
          _number(target)
        else
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: _from ?? target, end: target),
            duration:
                still ? Duration.zero : const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => _number(value),
          ),
        // "−412 kcal" rising off the balance.
        Positioned(
          right: 0,
          top: -4,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _chip,
              builder: (context, _) {
                final t = _chip.value;
                if (t == 0 || t == 1) return const SizedBox.shrink();
                final spent = _change < 0;
                return Opacity(
                  opacity: (t < 0.2 ? t / 0.2 : 1 - (t - 0.2) / 0.8)
                      .clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -26 * Curves.easeOut.transform(t)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Builder(builder: (context) {
                        final color =
                            spent ? Colors.white : const Color(0xFF6EE7B7);
                        return Text.rich(
                          TextSpan(children: [
                            TextSpan(text: spent ? '−' : '+'),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 1),
                                child: CalorieSymbol(size: 14, color: color),
                              ),
                            ),
                            TextSpan(text: formatCardKcal(_change)),
                          ]),
                          semanticsLabel:
                              '${spent ? 'minus' : 'plus'} '
                              '${formatCardKcal(_change)} calories',
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        );
                      }),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: const Text(
        'TheCalorieCard',
        maxLines: 1,
        semanticsLabel: 'The Calorie Card',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// A payment-card chip: gold, with the contact lines.
class _CardChip extends StatelessWidget {
  final Color color;

  const _CardChip({required this.color});

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    final light = hsl
        .withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0))
        .toColor();
    final dark = hsl
        .withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0))
        .toColor();
    final line = Colors.black.withValues(alpha: 0.22);
    return Container(
      width: 40,
      height: 30,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, color, dark],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 9,
            child: Container(height: 1, color: line),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 9,
            child: Container(height: 1, color: line),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 14,
            child: Container(width: 1, color: line),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 14,
            child: Container(width: 1, color: line),
          ),
        ],
      ),
    );
  }
}

/// One macro written like part of a card number, with a small caption:
/// "● PROTEIN" over "112g". Over budget shows "−20g" in red.
class MacroNumber extends StatelessWidget {
  final CardMacro macro;

  /// Put on the caption + number, for the tour.
  final Key? contentKey;

  const MacroNumber({super.key, required this.macro, this.contentKey});

  @override
  Widget build(BuildContext context) {
    final over = macro.remaining < 0;
    final grams = macro.remaining.abs().round();
    // The same rule for all three, like the balance: "58g left", then
    // "10g over" in red.
    final word = over ? 'over' : 'left';
    return Semantics(
      label: '${macro.name}: ${grams}g $word',
      excludeSemantics: true,
      child: Column(
        key: contentKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: macro.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                macro.name.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // "58g left": the card shows what's left (eaten is on its back),
          // so it says so.
          Text.rich(
            TextSpan(
              // No minus: "over" already says it.
              text: '${grams}g',
              children: [
                TextSpan(
                  text: ' $word',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            style: TextStyle(
              color: over ? CalorieCardColors.overBudget : Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps [child] so the tour can highlight just its own width.
Widget _tourMark(Key? key, Widget child) => key == null
    ? child
    : Align(
        alignment: Alignment.centerLeft,
        child: KeyedSubtree(key: key, child: child),
      );

/// Keys for the parts of the card front, used by the spotlight tour.
class CardTourKeys {
  final balance = GlobalKey(debugLabel: 'tour-card-balance');
  final protein = GlobalKey(debugLabel: 'tour-card-protein');
  final carbs = GlobalKey(debugLabel: 'tour-card-carbs');
  final fat = GlobalKey(debugLabel: 'tour-card-fat');
  final holder = GlobalKey(debugLabel: 'tour-card-holder');
  final validThru = GlobalKey(debugLabel: 'tour-card-date');

  /// Macros are shown protein, carbs, fat.
  GlobalKey? macro(int i) => switch (i) {
        0 => protein,
        1 => carbs,
        2 => fat,
        _ => null,
      };
}

/// One macro's remaining balance for the back of the card.
class CardMacro {
  final String name;
  final double remaining;
  final double? goal;
  final Color color;

  const CardMacro({
    required this.name,
    required this.remaining,
    this.goal,
    required this.color,
  });

  /// "P", "C" or "F" for the pills.
  String get short => name.isEmpty ? '' : name[0].toUpperCase();
}

/// Back of the card: each macro eaten against its goal ("120 / 150g"),
/// with a bar for how much of it is used.
class CalorieCardBack extends StatelessWidget {
  final List<CardMacro> macros;
  final String? footnote;
  final CardDesign design;

  const CalorieCardBack({
    super.key,
    required this.macros,
    this.footnote,
    this.design = CardDesign.midnight,
  });

  @override
  Widget build(BuildContext context) {
    return CalorieCardShell(
      design: design,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Macros',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (footnote != null)
                Text(
                  footnote!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const Spacer(),
          for (final m in macros) ...[
            _MacroLine(macro: m),
            const SizedBox(height: 8),
          ],
          const Spacer(),
          Text(
            'Tap to flip back',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroLine extends StatelessWidget {
  final CardMacro macro;

  const _MacroLine({required this.macro});

  @override
  Widget build(BuildContext context) {
    final over = macro.remaining < 0;
    final goal = macro.goal;
    final used = goal == null || goal <= 0
        ? null
        : ((goal - macro.remaining) / goal).clamp(0.0, 1.0).toDouble();

    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            macro.name,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: used == null
              ? const SizedBox.shrink()
              : ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: used,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(
                      over ? CalorieCardColors.overBudget : macro.color,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 96,
          child: Text(
            // Eaten out of the goal, so the day's totals are clear (on a
            // past day too). Without a goal: what's left, as before.
            goal != null && goal > 0
                ? '${(goal - macro.remaining).round()} / ${goal.round()}g'
                : over
                    ? '${macro.remaining.abs().round()}g over'
                    : '${macro.remaining.round()}g left',
            maxLines: 1,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: over ? CalorieCardColors.overBudget : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Placeholder while the balance loads, the same size as the real card.
class CalorieCardSkeleton extends StatelessWidget {
  final CardDesign design;

  const CalorieCardSkeleton({super.key, this.design = CardDesign.midnight});

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return CalorieCardShell(
      design: design,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(38, 28),
          const Spacer(),
          bar(110, 10),
          const SizedBox(height: 8),
          bar(170, 26),
          const SizedBox(height: 12),
          bar(130, 12),
        ],
      ),
    );
  }
}

/// Laid over the card on a rest day, like a bank card that's been frozen:
/// a light icy frost and one 🏖️ "Rest day" tag. It's a state, not a
/// caption, so it's the one thing ever drawn over the card's face.
/// Purely visual: taps still reach the card (screen readers hear "Rest
/// day" from the card's own label).
class RestDayFrost extends StatelessWidget {
  const RestDayFrost({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55), width: 1.5),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFE0F2FE).withValues(alpha: 0.45),
                    const Color(0xFFBAE6FD).withValues(alpha: 0.25),
                    const Color(0xFFF0F9FF).withValues(alpha: 0.40),
                  ],
                ),
              ),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  // Fixed colours: the card looks the same in dark mode.
                  child: const Text(
                    '🏖️ Rest day',
                    maxLines: 1,
                    style: TextStyle(
                      color: Color(0xFF0C4A6E),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
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

/// "CLOSED ✓" on a closed day's card: a faint, tilted outline, like a
/// stamp on a paid bill, small enough to leave the numbers clear.
class _ClosedStamp extends StatelessWidget {
  const _ClosedStamp();

  @override
  Widget build(BuildContext context) {
    final ink = Colors.white.withValues(alpha: 0.85);
    return ExcludeSemantics(
      child: Transform.rotate(
        angle: -0.14,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: ink, width: 1.6),
          ),
          child: Text(
            'CLOSED ✓',
            style: TextStyle(
              color: ink,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
