import 'package:flutter/material.dart';

/// The app's one palette. Every screen picks colours from here so blues,
/// greys and macro colours match everywhere.
///
/// Families: indigo (brand), violet (brand accent), and semantic emerald
/// (good), amber (warning / carbs), red (over / delete), rose, sky. Greys
/// are cool-toned so they sit with the indigo.
class AppColors {
  AppColors._();

  /// True while the dark theme is showing (set by [ThemeController]).
  ///
  /// Greys and pale tints swap for dark versions; the brand and accent
  /// colours stay the same, so filled buttons and badges look identical.
  /// For accent-coloured text and icons, use [AppText], which lightens
  /// them enough to read on dark surfaces.
  static bool dark = false;

  static Color _pick(Color light, Color darkColor) => dark ? darkColor : light;

  // Brand indigo
  static Color get indigo50 =>
      _pick(const Color(0xFFEEF2FF), const Color(0xFF1F2247));
  static Color get indigo100 =>
      _pick(const Color(0xFFE0E7FF), const Color(0xFF292E5E));
  static const indigo300 = Color(0xFFA5B4FC);
  static const indigo400 = Color(0xFF818CF8);
  static const primary = Color(0xFF6366F1); // brand, headers, icons
  static const primaryDark = Color(0xFF4F46E5); // filled buttons (AA with white)
  static const indigo700 = Color(0xFF4338CA);
  static const indigo800 = Color(0xFF3730A3);
  static const indigo900 = Color(0xFF312E81);

  // Brand accent
  static Color get violet50 =>
      _pick(const Color(0xFFF5F3FF), const Color(0xFF261E45));
  static Color get violet100 =>
      _pick(const Color(0xFFEDE9FE), const Color(0xFF30265A));
  static const violet300 = Color(0xFFC4B5FD);
  static const violet400 = Color(0xFFA78BFA);
  static const violet = Color(0xFF8B5CF6);
  static const violet600 = Color(0xFF7C3AED);
  static const violet800 = Color(0xFF5B21B6);
  static const violet900 = Color(0xFF4C1D95);

  // Good / on budget
  static Color get emerald50 =>
      _pick(const Color(0xFFECFDF5), const Color(0xFF0E2A24));
  static Color get emerald100 =>
      _pick(const Color(0xFFD1FAE5), const Color(0xFF113A30));
  static const emerald300 = Color(0xFF6EE7B7);
  static const emerald400 = Color(0xFF34D399);
  static const green = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const emerald800 = Color(0xFF065F46);
  static const emerald900 = Color(0xFF064E3B);

  // Warning
  static Color get amber50 =>
      _pick(const Color(0xFFFFFBEB), const Color(0xFF2B2312));
  static Color get amber100 =>
      _pick(const Color(0xFFFEF3C7), const Color(0xFF3A2E14));
  static Color get amber200 =>
      _pick(const Color(0xFFFDE68A), const Color(0xFF4A3A17));
  static const amber300 = Color(0xFFFCD34D);
  static const amber400 = Color(0xFFFBBF24);
  static const amber = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const amber800 = Color(0xFF92400E);

  // Over budget / destructive
  static Color get red50 =>
      _pick(const Color(0xFFFEF2F2), const Color(0xFF33191F));
  static Color get red100 =>
      _pick(const Color(0xFFFEE2E2), const Color(0xFF431E26));
  static const red300 = Color(0xFFFCA5A5);
  static const red400 = Color(0xFFF87171);
  static const red = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);

  // Extra category accents
  static Color get rose50 =>
      _pick(const Color(0xFFFFF1F2), const Color(0xFF341A26));
  static const rose400 = Color(0xFFFB7185);
  static const rose600 = Color(0xFFE11D48);
  static Color get sky50 =>
      _pick(const Color(0xFFF0F9FF), const Color(0xFF0E2434));
  static Color get sky100 =>
      _pick(const Color(0xFFE0F2FE), const Color(0xFF123247));
  static const sky = Color(0xFF0EA5E9);
  static Color get sky700 =>
      _pick(const Color(0xFF0369A1), const Color(0xFF7DD3FC)); // sky text on white (AA)

  // Macros, used the same way on every screen.
  static const protein = Color(0xFFEF4444);
  static const carbs = Color(0xFFF59E0B);
  static const fat = Color(0xFF0EA5E9);

  // Macro colours dark enough for text on white.
  static Color get proteinText =>
      _pick(const Color(0xFFDC2626), const Color(0xFFF87171));
  static Color get carbsText =>
      _pick(const Color(0xFFB45309), const Color(0xFFFBBF24));
  static Color get fatText =>
      _pick(const Color(0xFF0369A1), const Color(0xFF7DD3FC));

  // Cool greys
  static Color get canvas =>
      _pick(const Color(0xFFF3F4F8), const Color(0xFF0B1020));
  static Color get surface =>
      _pick(const Color(0xFFFFFFFF), const Color(0xFF151B2C)); // cards, sheets, fields
  static Color get gray50 =>
      _pick(const Color(0xFFF9FAFB), const Color(0xFF1B2236));
  static Color get gray100 =>
      _pick(const Color(0xFFF3F4F6), const Color(0xFF222A3F));
  static Color get border =>
      _pick(const Color(0xFFE5E7EB), const Color(0xFF2C3550));
  static Color get gray300 =>
      _pick(const Color(0xFFD1D5DB), const Color(0xFF3B4560));
  static Color get gray400 =>
      _pick(const Color(0xFF9CA3AF), const Color(0xFF6E7891));
  static Color get muted =>
      _pick(const Color(0xFF6B7280), const Color(0xFF9AA4BA));
  static Color get gray600 =>
      _pick(const Color(0xFF4B5563), const Color(0xFFB0B8CB));
  static Color get gray700 =>
      _pick(const Color(0xFF374151), const Color(0xFFC7CDDB));
  static Color get gray800 =>
      _pick(const Color(0xFF1F2937), const Color(0xFFDEE2EB));
  static Color get ink =>
      _pick(const Color(0xFF111827), const Color(0xFFF1F4F9));

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, violet],
  );
}

/// Accent colours for text and icons. Same as [AppColors] in light mode;
/// lighter in dark mode so they stay readable on dark surfaces.
class AppText {
  AppText._();

  static Color get primary =>
      AppColors.dark ? const Color(0xFF8B93F9) : AppColors.primary;
  static Color get primaryDark =>
      AppColors.dark ? const Color(0xFFA5B4FC) : AppColors.primaryDark;
  static Color get indigo700 =>
      AppColors.dark ? const Color(0xFFA5B4FC) : AppColors.indigo700;
  static Color get indigo800 =>
      AppColors.dark ? const Color(0xFFC7D2FE) : AppColors.indigo800;
  static Color get violet600 =>
      AppColors.dark ? const Color(0xFFC4B5FD) : AppColors.violet600;
  static Color get violet =>
      AppColors.dark ? const Color(0xFFA78BFA) : AppColors.violet;
  static Color get emerald600 =>
      AppColors.dark ? const Color(0xFF34D399) : AppColors.emerald600;
  static Color get emerald700 =>
      AppColors.dark ? const Color(0xFF6EE7B7) : AppColors.emerald700;
  static Color get emerald800 =>
      AppColors.dark ? const Color(0xFFA7F3D0) : AppColors.emerald800;
  static Color get green =>
      AppColors.dark ? const Color(0xFF34D399) : AppColors.green;
  static Color get red =>
      AppColors.dark ? const Color(0xFFF87171) : AppColors.red;
  static Color get red600 =>
      AppColors.dark ? const Color(0xFFF87171) : AppColors.red600;
  static Color get red700 =>
      AppColors.dark ? const Color(0xFFFCA5A5) : AppColors.red700;
  static Color get amber600 =>
      AppColors.dark ? const Color(0xFFFBBF24) : AppColors.amber600;
  static Color get amber700 =>
      AppColors.dark ? const Color(0xFFFCD34D) : AppColors.amber700;
  static Color get amber800 =>
      AppColors.dark ? const Color(0xFFFDE68A) : AppColors.amber800;
  static Color get sky =>
      AppColors.dark ? const Color(0xFF38BDF8) : AppColors.sky;
  static Color get rose600 =>
      AppColors.dark ? const Color(0xFFFB7185) : AppColors.rose600;
}

/// Shared shapes, so cards and panels look the same on every screen.
class AppDecor {
  AppDecor._();

  static const double radius = 16;

  /// A card (white, or dark grey in dark mode) with a hairline border: the app's standard surface.
  static BoxDecoration get card => BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.all(Radius.circular(radius)),
        border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
      );

  /// A quiet grey panel inside a card (totals, summaries).
  static BoxDecoration get inset => BoxDecoration(
        color: AppColors.gray50,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
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
