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

/// The rounded, dark-indigo body of the card.
class CalorieCardShell extends StatelessWidget {
  final Widget child;

  const CalorieCardShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CalorieCardColors.top, CalorieCardColors.bottom],
        ),
        boxShadow: [
          BoxShadow(
            color: CalorieCardColors.bottom.withValues(alpha: 0.35),
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
///   BALANCE                      [chip]
///   1,840 kcal
///   (P 112g) (C 180g) (F 54g)
///   SAM JONES               VALID THRU 09/10
class CalorieCardFront extends StatelessWidget {
  /// The balance in kcal. Negative means overspent.
  final num amount;

  /// Small label top-left. Defaults to BALANCE (OVER BUDGET when negative).
  final String? label;

  /// Remaining macros shown as pills under the balance.
  final List<CardMacro> macros;

  /// Cardholder name, shown bottom-left in capitals like a real card.
  /// Empty shows a faded placeholder; null hides the line.
  final String? holder;

  /// Bottom-right "valid thru" value, e.g. 09/10 for the day shown.
  final String? validThru;

  const CalorieCardFront({
    super.key,
    required this.amount,
    this.label,
    this.macros = const [],
    this.holder,
    this.validThru,
  });

  @override
  Widget build(BuildContext context) {
    final over = amount < 0;
    final name = (holder ?? '').trim().toUpperCase();

    return CalorieCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label ?? (over ? 'OVER BUDGET' : 'BALANCE'),
                style: TextStyle(
                  color: over
                      ? CalorieCardColors.overBudget
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              Container(
                width: 38,
                height: 28,
                decoration: BoxDecoration(
                  color: CalorieCardColors.chip,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${over ? '−' : ''}${formatCardKcal(amount)} kcal',
              style: TextStyle(
                color: over ? CalorieCardColors.overBudget : Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (macros.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [for (final m in macros) MacroPill(macro: m)],
            ),
          ],
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: holder == null
                    ? const SizedBox.shrink()
                    : AnimatedSwitcher(
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
              if (validThru != null) ...[
                const SizedBox(width: 12),
                Column(
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

/// "P 112g" style pill, tinted with the macro's colour.
class MacroPill extends StatelessWidget {
  final CardMacro macro;

  const MacroPill({super.key, required this.macro});

  @override
  Widget build(BuildContext context) {
    final over = macro.remaining < 0;
    final color = over ? CalorieCardColors.overBudget : macro.color;
    final value = over
        ? '−${macro.remaining.abs().round()}g'
        : '${macro.remaining.round()}g';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${macro.short} $value',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
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

  const CalorieCardBack({super.key, required this.macros, this.footnote});

  @override
  Widget build(BuildContext context) {
    return CalorieCardShell(
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
  const CalorieCardSkeleton({super.key});

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
