import 'package:flutter/material.dart';

/// The calorie card's look, shared by the sign-in preview and the live card
/// on the Card screen so they always match.
class CalorieCardColors {
  CalorieCardColors._();

  static const top = Color(0xFF312E81);
  static const bottom = Color(0xFF1E1B4B);
  static const chip = Color(0xFFFBBF24);
  static const overBudget = Color(0xFFFCA5A5);
  static const protein = Color(0xFFF87171);
  static const carbs = Color(0xFFFBBF24);
  static const fat = Color(0xFF60A5FA);
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
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CalorieCardColors.top, CalorieCardColors.bottom],
        ),
        boxShadow: [
          BoxShadow(
            color: CalorieCardColors.bottom.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Front of the card: chip, balance and cardholder.
class CalorieCardFront extends StatelessWidget {
  /// Small line above the amount, e.g. "Left to spend today".
  final String label;

  /// The balance in kcal. Negative means overspent.
  final num amount;

  /// Name on the card. Empty shows [holderPlaceholder] faded.
  final String holder;
  final String holderPlaceholder;

  /// Small text bottom-right, e.g. the date the balance is for.
  final String? footnote;

  /// Hint shown top-right (e.g. a flip icon) instead of the contactless mark.
  final Widget? cornerIcon;

  const CalorieCardFront({
    super.key,
    required this.label,
    required this.amount,
    required this.holder,
    this.holderPlaceholder = 'Your name here',
    this.footnote,
    this.cornerIcon,
  });

  @override
  Widget build(BuildContext context) {
    final over = amount < 0;
    final name = holder.trim();

    return CalorieCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 28,
                decoration: BoxDecoration(
                  color: CalorieCardColors.chip,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const Spacer(),
              cornerIcon ??
                  Icon(Icons.contactless_outlined,
                      color: Colors.white.withValues(alpha: 0.7), size: 24),
            ],
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              color: over
                  ? CalorieCardColors.overBudget
                  : Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${over ? '−' : ''}${formatCardKcal(amount)} kcal',
              style: TextStyle(
                color: over ? CalorieCardColors.overBudget : Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    name.isEmpty ? holderPlaceholder : name,
                    key: ValueKey(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white
                          .withValues(alpha: name.isEmpty ? 0.5 : 0.95),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              if (footnote != null) ...[
                const SizedBox(width: 12),
                Text(
                  footnote!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
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
    required this.goal,
    required this.color,
  });
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
