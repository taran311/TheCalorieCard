import 'package:flutter/material.dart';

/// Brand colours used across the app.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF6366F1); // indigo
  static const primaryDark = Color(0xFF4F46E5);
  static const violet = Color(0xFF8B5CF6);
  static const green = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const protein = Color(0xFFEF4444);
  static const carbs = Color(0xFFF59E0B);
  static const fat = Color(0xFF3B82F6);
  static const canvas = Color(0xFFF3F4F8);
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);

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
