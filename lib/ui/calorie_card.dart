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

  const CardDesign({
    required this.id,
    required this.name,
    required this.top,
    required this.bottom,
    required this.chip,
    required this.requirement,
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

  static const all = [midnight, emerald, sunset, metal];

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
          colors: [design.top, design.bottom],
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

/// Front of the card, laid out like a payment card:
///
///   1,840 kcal                     [chip]
///
///   ● PROTEIN    ● CARBS      ● FAT
///   112g left    180g left    54g left
///
///   SAM JONES               VALID THRU 09/10
class CalorieCardFront extends StatelessWidget {
  /// The balance in kcal. Negative means overspent.
  final num amount;

  /// Optional small caption above the balance (none by default).
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

    return CalorieCardShell(
      design: design,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(
              label!,
              style: TextStyle(
                color: over
                    ? CalorieCardColors.overBudget
                    : Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: 2),
          ],
          // Balance top-left, chip top-right.
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${over ? '−' : ''}${formatCardKcal(amount)} kcal',
                    key: tourKeys?.balance,
                    style: TextStyle(
                      color: over ? CalorieCardColors.overBudget : Colors.white,
                      fontSize: 22,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 36,
                height: 27,
                decoration: BoxDecoration(
                  color: design.chip,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
          // Flexible gaps: roomy on big cards, still fits on small ones.
          const Spacer(),
          if (macros.isNotEmpty)
            Row(
              children: [
                for (var i = 0; i < macros.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: MacroPill(
                      macro: macros[i],
                      contentKey: tourKeys?.macro(i),
                    ),
                  ),
                ],
              ],
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
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 8,
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

/// One macro on the front of the card: a small coloured label over what's
/// left, e.g. "● PROTEIN" / "112g left" (or "20g over").
class MacroPill extends StatelessWidget {
  final CardMacro macro;

  /// Put on the label + amount (not the whole column), for the tour.
  final Key? contentKey;

  const MacroPill({super.key, required this.macro, this.contentKey});

  @override
  Widget build(BuildContext context) {
    final over = macro.remaining < 0;
    final grams = macro.remaining.abs().round();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Column(
        key: contentKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: macro.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                macro.name.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '${grams}g',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text: over ? ' over' : ' left',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: over
                      ? CalorieCardColors.overBudget
                      : Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ]),
            maxLines: 1,
            style: TextStyle(
              color: over ? CalorieCardColors.overBudget : Colors.white,
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
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
                    color: Colors.white.withValues(alpha: 0.65),
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
              color: Colors.white.withValues(alpha: 0.5),
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
