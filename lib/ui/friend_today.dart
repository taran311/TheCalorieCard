import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/friend_activity.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';

/// Live view of a friend's day (today's `daily_logs` doc, plus their goal).
/// Moves on to the new day at midnight. [builder] gets null until the
/// first snapshot arrives, so callers can keep the same size meanwhile.
class FriendTodayBuilder extends StatefulWidget {
  final String userId;
  final Widget Function(BuildContext context, FriendDay? day) builder;

  const FriendTodayBuilder({
    super.key,
    required this.userId,
    required this.builder,
  });

  @override
  State<FriendTodayBuilder> createState() => _FriendTodayBuilderState();
}

class _FriendTodayBuilderState extends State<FriendTodayBuilder> {
  late String _dayKey;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _log;
  late Future<double?> _goal = FriendActivity.goalOf(widget.userId);
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _scheduleMidnight();
  }

  void _subscribe() {
    _dayKey = BalanceService.dateKey(BalanceService.now());
    _log = FriendActivity.dayLog(widget.userId);
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    _midnight = FriendActivity.atMidnight(() {
      if (!mounted) return;
      setState(_subscribe);
      _scheduleMidnight();
    });
  }

  @override
  void didUpdateWidget(covariant FriendTodayBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _subscribe();
      _goal = FriendActivity.goalOf(widget.userId);
    }
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Timers can be late (a sleeping laptop): catch the new day here too.
    if (BalanceService.dateKey(BalanceService.now()) != _dayKey) _subscribe();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _log,
      builder: (context, snap) {
        if (snap.hasError) return widget.builder(context, FriendDay.none);
        if (!snap.hasData) return widget.builder(context, null);
        final log = snap.data!.data();
        return FutureBuilder<double?>(
          future: _goal,
          builder: (context, goal) => widget.builder(
            context,
            FriendDay.fromLog(log, fallbackGoal: goal.data),
          ),
        );
      },
    );
  }
}

/// An avatar with today's progress drawn round it: the share of their
/// budget spent (red once over), a ✓ when they've finished the day, and a
/// plain grey ring when there's nothing to show.
class ProgressAvatar extends StatelessWidget {
  final String name;
  final FriendDay? day;
  final double size;

  const ProgressAvatar({
    super.key,
    required this.name,
    required this.day,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    final d = day;
    final fraction = d?.fraction;
    final over = d?.onTrack == false;
    final ring = size / 13;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: fraction == null
                  ? 0.0
                  : fraction.clamp(0.0, 1.0).toDouble(),
              strokeWidth: ring,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(
                  over ? AppColors.red : AppColors.primary),
            ),
          ),
          Center(
            child: CircleAvatar(
              radius: size / 2 - ring - 3,
              backgroundColor: AppColors.indigo50,
              child: Text(
                name.initial.toUpperCase(),
                style: TextStyle(
                  color: AppText.primaryDark,
                  fontSize: size / 3,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (d?.finished == true)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: size / 2.6,
                height: size / 2.6,
                decoration: BoxDecoration(
                  color: AppColors.emerald600,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: Icon(Icons.check,
                    size: size / 4, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
