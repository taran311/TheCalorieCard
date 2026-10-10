import 'package:flutter/material.dart';
import 'package:namer_app/services/leaderboard_service.dart';
import 'package:namer_app/services/streak.dart';
import 'package:namer_app/ui/responsive.dart';

/// Small "🔥 12" pill next to the day picker. Shows banked Streak Freezes
/// as ❄️, and opens an explainer when tapped.
class StreakPill extends StatefulWidget {
  final String userId;

  const StreakPill({super.key, required this.userId});

  @override
  State<StreakPill> createState() => _StreakPillState();
}

class _StreakPillState extends State<StreakPill> {
  @override
  void initState() {
    super.initState();
    MyStreak.load(widget.userId);
  }

  @override
  void didUpdateWidget(StreakPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) MyStreak.load(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StreakResult?>(
      valueListenable: MyStreak.notifier,
      builder: (context, streak, _) {
        final s = streak ?? StreakResult.empty;
        final label = '${s.current}-day streak'
            '${s.freezes > 0 ? ', ${s.freezes} Streak Freeze${s.freezes == 1 ? '' : 's'}' : ''}';
        return Semantics(
          button: true,
          label: label,
          child: Tooltip(
            message: label,
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: AppColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => showStreakSheet(context, s),
                child: SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.current > 0 ? '🔥' : '🌱',
                              style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 4),
                          Text(
                            '${s.current}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          if (s.freezes > 0) ...[
                            const SizedBox(width: 8),
                            const Text('❄️', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 2),
                            Text(
                              '${s.freezes}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.sky700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Explains your streak and Streak Freezes.
Future<void> showStreakSheet(BuildContext context, StreakResult s) {
  final frozenDays = s.frozen.toList()..sort();
  String pretty(String key) {
    final d = DateTime.tryParse(key);
    if (d == null) return key;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.current > 0
                  ? '🔥 ${s.current}-day streak'
                  : '🌱 Start a streak today',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.current > 0
                  ? 'Finish today to keep it going.'
                  : 'Log your food and finish the day to get your first one.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.sky50,
                borderRadius: BorderRadius.circular(AppDecor.radius),
                border: Border.all(color: AppColors.sky100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('❄️', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Streak Freezes: ${s.freezes} of ${Streaks.maxFreezes}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.sky700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Finish ${Streaks.earnEvery} days in a row to earn a '
                    'freeze. If you miss a day, one is used automatically '
                    'and your streak lives on.',
                    style: TextStyle(color: AppColors.gray700, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < Streaks.maxFreezes; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            i < s.freezes
                                ? Icons.ac_unit_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 18,
                            color: i < s.freezes
                                ? AppText.sky
                                : AppColors.gray400,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            i < s.freezes ? 'Ready to use' : 'Empty slot',
                            style: TextStyle(color: AppColors.gray700),
                          ),
                        ],
                      ),
                    ),
                  if (s.toNextFreeze > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (Streaks.earnEvery - s.toNextFreeze) /
                            Streaks.earnEvery,
                        minHeight: 8,
                        backgroundColor: AppColors.sky100,
                        color: AppColors.sky,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${s.toNextFreeze} more finished '
                      'day${s.toNextFreeze == 1 ? '' : 's'} to earn the next one',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (frozenDays.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Saved by a freeze: ${frozenDays.map(pretty).join(', ')}',
                style: TextStyle(color: AppColors.gray700),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

