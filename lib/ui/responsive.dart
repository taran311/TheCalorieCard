import 'package:flutter/material.dart';

/// The app's one palette. Every screen picks colours from here so blues,
/// greys and macro colours match everywhere.
///
/// Families: indigo (brand), violet (brand accent), and semantic emerald
/// (good), amber (warning / carbs), red (over / delete), rose, sky. Greys
/// are cool-toned so they sit with the indigo.
class AppColors {
  AppColors._();

  // Brand indigo
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo300 = Color(0xFFA5B4FC);
  static const indigo400 = Color(0xFF818CF8);
  static const primary = Color(0xFF6366F1); // brand, headers, icons
  static const primaryDark = Color(0xFF4F46E5); // filled buttons (AA with white)
  static const indigo700 = Color(0xFF4338CA);
  static const indigo800 = Color(0xFF3730A3);
  static const indigo900 = Color(0xFF312E81);

  // Brand accent
  static const violet50 = Color(0xFFF5F3FF);
  static const violet100 = Color(0xFFEDE9FE);
  static const violet300 = Color(0xFFC4B5FD);
  static const violet400 = Color(0xFFA78BFA);
  static const violet = Color(0xFF8B5CF6);
  static const violet600 = Color(0xFF7C3AED);
  static const violet800 = Color(0xFF5B21B6);
  static const violet900 = Color(0xFF4C1D95);

  // Good / on budget
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald300 = Color(0xFF6EE7B7);
  static const emerald400 = Color(0xFF34D399);
  static const green = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald800 = Color(0xFF065F46);
  static const emerald900 = Color(0xFF064E3B);

  // Warning
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber300 = Color(0xFFFCD34D);
  static const amber400 = Color(0xFFFBBF24);
  static const amber = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);

  // Over budget / destructive
  static const red300 = Color(0xFFFCA5A5);
  static const red400 = Color(0xFFF87171);
  static const red = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);

  // Extra category accents
  static const rose400 = Color(0xFFFB7185);
  static const rose600 = Color(0xFFE11D48);
  static const sky = Color(0xFF0EA5E9);

  // Macros, used the same way on every screen.
  static const protein = Color(0xFFEF4444);
  static const carbs = Color(0xFFF59E0B);
  static const fat = Color(0xFF0EA5E9);

  // Cool greys
  static const canvas = Color(0xFFF3F4F8);
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const border = Color(0xFFE5E7EB);
  static const gray300 = Color(0xFFD1D5DB);
  static const gray400 = Color(0xFF9CA3AF);
  static const muted = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const gray800 = Color(0xFF1F2937);
  static const ink = Color(0xFF111827);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, violet],
  );
}

/// Screen-size buckets. Widths are logical pixels.
class Breakpoints {
  Breakpoints._();

  /// Below this: phone layout (bottom navigation, full-screen pages).
  static const double tablet = 700;

  /// At or above this: full desktop layout with a labelled sidebar.
  static const double desktop = 1024;

  /// At or above this: desktop layout plus the right-hand "Today" panel.
  static const double wide = 1320;

  /// Widest the main page column grows to on large screens.
  static const double contentMaxWidth = 720;
}

/// Counts how many app shells (signed-in layouts) are currently on screen.
///
/// The top-level frame uses this to decide whether to present the page
/// itself (sign-in, onboarding) or let the shell lay out the desktop UI.
class ShellPresence {
  ShellPresence._();

  static final ValueNotifier<int> mounted = ValueNotifier<int>(0);
}

/// Gives [child] a MediaQuery whose size matches the box it is drawn in.
///
/// Many pages size things from `MediaQuery.size` (built for phones). When we
/// draw them in a column on a big monitor, this keeps them from stretching
/// as if they owned the whole window.
class LocalMediaQuery extends StatelessWidget {
  final Widget child;

  const LocalMediaQuery({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
          child: child,
        );
      },
    );
  }
}
