import 'package:flutter/material.dart';
import 'package:namer_app/services/notification_service.dart';
import 'package:namer_app/ui/responsive.dart';

/// Settings for the evening "log today's food" reminder.
Future<void> showReminderSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const SafeArea(child: _ReminderSheet()),
  );
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet();

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  bool _loading = true;
  bool _busy = false;
  bool _enabled = false;
  int _hour = NotificationService.defaultHour;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await NotificationService.load();
      if (!mounted) return;
      setState(() {
        _enabled = s.enabled;
        _hour = s.hour;
      });
    } catch (_) {
      // Shown as off.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool on) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      if (on) {
        error = await NotificationService.enable(hour: _hour);
      } else {
        await NotificationService.disable();
      }
    } catch (_) {
      error = "Couldn't save that. Please try again.";
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) _enabled = on;
    });
  }

  Future<void> _pickHour(int hour) async {
    final before = _hour;
    setState(() => _hour = hour);
    if (!_enabled) return;
    try {
      await NotificationService.setHour(hour);
    } catch (_) {
      if (mounted) {
        setState(() {
          _hour = before;
          _error = "Couldn't save that. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = NotificationService.supported;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Evening reminder',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "If you haven't logged anything by then, you'll get a friendly "
            "nudge. Already logged? We won't bother you.",
            style: TextStyle(color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (!supported)
            Text(
              "Reminders aren't available here yet.",
              style: TextStyle(color: AppColors.gray700),
            )
          else ...[
            Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDecor.radius),
                side: BorderSide(color: AppColors.border),
              ),
              child: SwitchListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDecor.radius),
                ),
                value: _enabled,
                onChanged: _busy ? null : _toggle,
                secondary: Icon(Icons.notifications_active_outlined,
                    color: AppText.primary),
                title: Text(
                  _enabled ? 'On' : 'Off',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                subtitle: Text(
                  _enabled
                      ? 'Every day at ${NotificationService.hourLabel(_hour)}'
                      : 'Turn on to get a nudge',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Remind me at',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.gray700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in NotificationService.hours)
                  ChoiceChip(
                    label: Text(NotificationService.hourLabel(h)),
                    selected: _hour == h,
                    onSelected: _busy ? null : (_) => _pickHour(h),
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: AppText.red600)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
