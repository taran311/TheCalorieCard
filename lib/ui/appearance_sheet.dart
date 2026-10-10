import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/theme_controller.dart';

/// Light, dark or match the device.
Future<void> showAppearanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListenableBuilder(
        listenable: ThemeController.instance,
        builder: (context, _) {
          final current = ThemeController.instance.mode;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Saved on this device.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                for (final mode in AppThemeMode.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ModeTile(
                      mode: mode,
                      selected: mode == current,
                      onTap: () => ThemeController.instance.setMode(mode),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _ModeTile extends StatelessWidget {
  final AppThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.indigo50 : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(mode.icon, color: AppText.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? AppText.primary : AppColors.gray400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
