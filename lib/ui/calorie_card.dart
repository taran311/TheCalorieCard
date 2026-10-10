import 'package:flutter/material.dart';

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
///   [chip]                       1,840 kcal
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

  const CalorieCardFront({
    super.key,
    required this.amount,
    this.label,
    this.macros = const [],
    this.holder,
    this.validThru,
    this.design = CardDesign.midnight,
    this.tourKeys,
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
            // Like a bank card: brand top-left, contactless top-right, the
            // chip under the brand with the balance alongside it.
            Row(
              children: [
                Expanded(child: _Wordmark()),
                Icon(
                  Icons.contactless_outlined,
                  color: Colors.white.withValues(alpha: 0.75),
                  size: 20,
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                _CardChip(color: design.chip),
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
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text:
                                    '${over ? '−' : ''}${formatCardKcal(amount)}'),
                            TextSpan(
                              text: ' kcal',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: (over
                                        ? CalorieCardColors.overBudget
                                        : Colors.white)
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                          ]),
                          key: tourKeys?.balance,
                          style: TextStyle(
                            color: over
                                ? CalorieCardColors.overBudget
                                : Colors.white,
                            fontSize: 34,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
    return Semantics(
      label: '${macro.name}: ${grams}g ${over ? 'over' : 'left'}',
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
          Text(
            '${over ? '−' : ''}${grams}g',
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

/// Back of the card: what's left of each macro.
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
                'Macros left',
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
          width: 74,
          child: Text(
            over
                ? '${macro.remaining.abs().round()}g over'
                : '${macro.remaining.round()}g',
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
