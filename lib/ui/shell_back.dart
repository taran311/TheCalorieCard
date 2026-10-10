import 'package:flutter/material.dart';

/// Gives a top-level screen (Coach, and on phones Hiscores, Statement and
/// Chat) a back arrow that returns to the screen you came from.
///
/// The app shell puts one of these around each tab. Pages call
/// [ShellBack.button] for their app bar's `leading`.
class ShellBack extends InheritedWidget {
  /// Null when this tab doesn't need a back arrow.
  final VoidCallback? onBack;

  const ShellBack({super.key, required this.onBack, required super.child});

  /// A back arrow for the app bar, or null to keep the usual behaviour
  /// (pages pushed on top already get Flutter's own back arrow).
  static Widget? button(BuildContext context) {
    final onBack =
        context.dependOnInheritedWidgetOfExactType<ShellBack>()?.onBack;
    if (onBack == null) return null;
    if (Navigator.of(context).canPop()) return null;
    return BackButton(onPressed: onBack);
  }

  @override
  bool updateShouldNotify(ShellBack oldWidget) =>
      (oldWidget.onBack == null) != (onBack == null);
}
