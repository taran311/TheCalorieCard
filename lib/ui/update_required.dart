import 'package:flutter/material.dart';
import 'package:namer_app/services/play_update.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:url_launcher/url_launcher.dart';

/// Covers the app with "Please update" while [PlayUpdate.mustUpdate] is
/// on (this version is too old to use safely). The app underneath stays
/// as it was, so nothing is lost once they've updated.
class UpdateGate extends StatelessWidget {
  final Widget child;

  const UpdateGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PlayUpdate.mustUpdate,
      // Same shape either way, so the app underneath isn't rebuilt.
      builder: (context, must, _) => Stack(
        children: [
          child,
          if (must) const Positioned.fill(child: _UpdateRequired()),
        ],
      ),
    );
  }
}

class _UpdateRequired extends StatefulWidget {
  const _UpdateRequired();

  @override
  State<_UpdateRequired> createState() => _UpdateRequiredState();
}

class _UpdateRequiredState extends State<_UpdateRequired> {
  bool _busy = false;

  static final _store = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.thecaloriecard.app');

  Future<void> _update() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await PlayUpdate.updateNow();
    } catch (_) {
      // Google's update screen isn't available: open the store listing.
      await launchUrl(_store, mode: LaunchMode.externalApplication);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.system_update_alt_rounded,
                        color: Colors.white, size: 56),
                    const SizedBox(height: 20),
                    const Text(
                      'Time for an update',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This version of The Calorie Card is out of date. '
                      'Update to keep using it. Everything you\'ve logged '
                      'is safe and waiting for you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryDark,
                        ),
                        onPressed: _busy ? null : _update,
                        child: const Text(
                          'Update now',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
