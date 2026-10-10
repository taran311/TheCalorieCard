import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light, dark, or follow the device.
enum AppThemeMode {
  system('Match device', Icons.brightness_auto_rounded),
  light('Light', Icons.light_mode_rounded),
  dark('Dark', Icons.dark_mode_rounded);

  final String label;
  final IconData icon;
  const AppThemeMode(this.label, this.icon);
}

/// Owns the app's light/dark choice (saved on this device) and keeps
/// [AppColors.dark] in step with it.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const _key = 'theme_mode';

  AppThemeMode _mode = AppThemeMode.system;
  AppThemeMode get mode => _mode;

  bool get isDark => AppColors.dark;

  /// Call once before runApp.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      _mode = AppThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => AppThemeMode.system,
      );
    } catch (_) {
      // No saved choice: follow the device.
    }
    WidgetsBinding.instance.addObserver(this);
    AppColors.dark = _resolve();
  }

  Future<void> setMode(AppThemeMode mode) async {
    _mode = mode;
    _apply();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }

  bool _resolve() => switch (_mode) {
        AppThemeMode.light => false,
        AppThemeMode.dark => true,
        AppThemeMode.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark,
      };

  void _apply() {
    final dark = _resolve();
    final changed = dark != AppColors.dark;
    AppColors.dark = dark;
    notifyListeners();
    if (changed) _rebuildEverything();
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == AppThemeMode.system) _apply();
  }

  /// Most screens read colours straight from [AppColors], so they don't
  /// rebuild on their own when the theme flips. Mark every element dirty
  /// so the whole app repaints in the new colours.
  void _rebuildEverything() {
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }
}

/// The app theme for the current [AppColors.dark] setting.
ThemeData buildAppTheme() {
  final dark = AppColors.dark;
  final buttonShape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: dark ? AppText.primary : AppColors.primary,
      brightness: dark ? Brightness.dark : Brightness.light,
      surface: dark ? AppColors.surface : null,
    ),
    scaffoldBackgroundColor: AppColors.canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? AppColors.surface : AppColors.primary,
      foregroundColor: dark ? AppColors.ink : Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: dark ? AppColors.ink : Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    // One button style app-wide: brand filled buttons, quiet outlines.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 44),
        shape: buttonShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(48, 44),
        shape: buttonShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppText.primaryDark,
        minimumSize: const Size(48, 44),
        side: BorderSide(color: AppColors.gray300),
        shape: buttonShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppText.primaryDark,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primaryDark,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    // Flat cards with a hairline border, not tinted shadows.
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 19,
        fontWeight: FontWeight.w800,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: AppColors.border),
    // Sheets and dialogs shouldn't stretch across a whole monitor.
    bottomSheetTheme: BottomSheetThemeData(
      constraints: const BoxConstraints(maxWidth: 640),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
  );
}
