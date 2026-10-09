import 'package:flutter/material.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/responsive.dart';

/// Wraps the whole app (via MaterialApp.builder).
///
/// * Phones: pages fill the screen, exactly as on a native app.
/// * Signed in on a bigger screen: the shell draws its own desktop layout,
///   so this does nothing.
/// * Signed out / onboarding on a bigger screen: shows the page in a
///   phone-width panel next to a brand panel, instead of stretching a
///   phone form across a monitor.
class AdaptiveFrame extends StatelessWidget {
  final Widget child;

  const AdaptiveFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ShellPresence.mounted,
      builder: (context, shells, _) {
        final width = MediaQuery.sizeOf(context).width;
        // Framed = signed-out / onboarding pages on a big screen.
        final framed = width >= Breakpoints.tablet && shells == 0;
        final heroWidth = framed && width >= Breakpoints.desktop
            ? width / 2
            : 0.0;

        // The widget structure below never changes shape, only its
        // settings. Changing shape would rebuild the app's navigator and
        // throw away the pages the user has open.
        // Material (not a plain ColoredBox) gives the brand panel proper
        // text styling; without it Flutter shows yellow debug underlines.
        return Material(
          color: framed ? AppColors.canvas : Colors.white,
          child: Row(
            children: [
              SizedBox(
                key: const ValueKey('brand-panel'),
                width: heroWidth,
                child: heroWidth > 0 ? const _BrandPanel() : null,
              ),
              Expanded(
                key: const ValueKey('app-panel'),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: framed ? 24 : 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: framed
                          ? const BoxConstraints(maxWidth: 460, maxHeight: 900)
                          : const BoxConstraints(),
                      child: Material(
                        elevation: framed ? 12 : 0,
                        shadowColor: Colors.black26,
                        borderRadius:
                            BorderRadius.circular(framed ? 28 : 0),
                        clipBehavior: Clip.antiAlias,
                        child: LocalMediaQuery(child: child),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
      child: Center(
        child: SingleChildScrollView(
         child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.credit_card,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'The Calorie Card',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              const Text(
                'Spend calories\nlike currency.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Your daily budget lives on a card. Describe what you ate in '
                'plain words and watch the balance update.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 17,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              const _MiniCard(),
              const SizedBox(height: 40),
              const _Benefit(
                icon: Icons.auto_awesome,
                text: 'Type "2 eggs and toast". We work out the numbers.',
              ),
              const _Benefit(
                icon: Icons.account_balance_wallet_outlined,
                text: 'A fresh balance every morning: calories, protein, '
                    'carbs and fat.',
              ),
              const _Benefit(
                icon: Icons.emoji_events_outlined,
                text: 'Compete with friends on streaks and logging.',
              ),
            ],
          ),
         ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Benefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small decorative card so the brand panel shows the core idea.
/// Same component as the live card on the Card screen.
class _MiniCard extends StatelessWidget {
  const _MiniCard();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 340,
      height: 200,
      child: CalorieCardFront(
        amount: 1840,
        holder: 'Alex Morgan',
        validThru: '09/10',
        macros: [
          CardMacro(name: 'Protein', remaining: 112, color: CalorieCardColors.protein),
          CardMacro(name: 'Carbs', remaining: 180, color: CalorieCardColors.carbs),
          CardMacro(name: 'Fat', remaining: 54, color: CalorieCardColors.fat),
        ],
      ),
    );
  }
}
