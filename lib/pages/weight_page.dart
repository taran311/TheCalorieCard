import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/goal_maths.dart';
import 'package:namer_app/services/profile_limits.dart';
import 'package:namer_app/services/units.dart';
import 'package:namer_app/services/weight_service.dart';
import 'package:namer_app/ui/body_inputs.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Your weight log: today's weigh-in, the trend, and (after a few weeks) a
/// gentle check-in on whether the daily goal is doing what you want.
class WeightPage extends StatefulWidget {
  const WeightPage({super.key});

  @override
  State<WeightPage> createState() => _WeightPageState();
}

class _WeightPageState extends State<WeightPage> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  /// Created once; the page rebuilds from it as weigh-ins change.
  late final Stream<List<WeighIn>>? _history =
      _uid == null ? null : WeightService.watch(_uid!);

  Map<String, dynamic>? _profile;
  bool _loadingProfile = true;
  UnitPrefs _units = UnitPrefs.forCountry(
      WidgetsBinding.instance.platformDispatcher.locale.countryCode);

  double? _entryKg;
  bool _saving = false;
  bool _applyingNudge = false;

  /// The check-in was answered recently, so it's hidden for a while.
  bool _checkInSnoozed = false;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  String get _snoozeKey => 'weight_checkin_snoozed_${_uid ?? ''}';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadSnooze();
  }

  Future<void> _loadProfile() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final doc = await BalanceService.userDataDoc(uid);
      if (!mounted) return;
      final data = doc?.data();
      setState(() {
        _profile = data;
        _units = UnitPrefs.fromProfile(
          data,
          countryCode:
              WidgetsBinding.instance.platformDispatcher.locale.countryCode,
        );
        _entryKg ??= asDouble(data?['weight']);
        _loadingProfile = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _loadSnooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getString(_snoozeKey);
      final untilDate = until == null ? null : WeightService.parseDateKey(until);
      final snoozed = untilDate != null &&
          BalanceService.startOfDay(BalanceService.now()).isBefore(untilDate);
      if (mounted) setState(() => _checkInSnoozed = snoozed);
    } catch (_) {
      // No saved choice: show it.
    }
  }

  /// Hides the check-in for two weeks: enough new weigh-ins to judge again.
  Future<void> _snoozeCheckIn() async {
    setState(() => _checkInSnoozed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final until =
          BalanceService.addDays(BalanceService.now(), 14);
      await prefs.setString(_snoozeKey, BalanceService.dateKey(until));
    } catch (_) {
      // Only remembered for this visit.
    }
  }

  bool get _male => _profile?['gender'] == 'male';

  double _floorFor(double kg) => safeMinimumCalories(
        male: _male,
        resting: restingCalories(
          age: asInt(_profile?['age']),
          heightCm: asDouble(_profile?['height']),
          weightKg: kg,
          male: _male,
        ),
      );

  /// Saves today's weight, updates the profile and offers a new suggested
  /// goal worked out the same way Goals and profile does (keeping your
  /// macro split).
  Future<void> _save() async {
    final uid = _uid;
    final kg = _entryKg;
    if (uid == null || _saving) return;
    final messenger = ScaffoldMessenger.of(context);
    if (kg == null || !ProfileLimits.weightOk(kg)) {
      messenger.showSnackBar(
          SnackBar(content: Text(Units.weightRangeMessage(_units))));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await WeightService.log(uid, kg);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't save your weight. Please try again.")));
      return;
    }

    // The profile weight drives the suggested goal.
    String done = 'Weight saved.';
    try {
      final doc = await BalanceService.userDataDoc(uid);
      final data = doc?.data();
      final currentGoals = data == null ? null : BalanceService.goalsFrom(data);
      if (doc != null && data != null) {
        Macros? newGoals;
        if (currentGoals != null) {
          newGoals = await _offerNewGoal(data, currentGoals, kg);
        }
        if (newGoals != null) {
          await BalanceService.applyGoals(
            uid,
            goals: newGoals,
            extra: {
              'weight': Units.storeKg(kg),
              'goal_source': 'calculated',
            },
          );
          FoodLog.notifyChanged();
          done = 'Weight and goal saved. Your card is up to date.';
        } else {
          await doc.reference.update({'weight': Units.storeKg(kg)});
        }
      }
    } catch (_) {
      done = 'Weight logged, but your profile didn\'t update. '
          'Try again in Goals and profile.';
    }
    if (mounted) setState(() => _saving = false);
    messenger.showSnackBar(SnackBar(content: Text(done)));
    _loadProfile();
  }

  /// Asks whether to use the new suggested goal for [kg]. Returns the new
  /// goals, or null to keep the current ones.
  Future<Macros?> _offerNewGoal(
      Map<String, dynamic> data, Macros current, double kg) async {
    final mode = data['calorie_mode'];
    final male = data['gender'] == 'male';
    final base = maintenanceCalories(
      age: asInt(data['age']),
      heightCm: asDouble(data['height']),
      weightKg: kg,
      male: male,
      exerciseLevel: asDouble(data['exercise_level']) ?? 0,
    );
    if (base == null || !base.isFinite || base <= 0) return null;
    final suggested = suggestedCalorieGoal(
      base,
      mode is String ? mode : null,
      floor: _floorFor(kg),
    );
    if (suggested < 500 || suggested > 10000) return null;
    // Small changes aren't worth a question.
    if ((suggested - current.calories).abs() < 20) return null;
    final next = macrosScaledTo(current, suggested);
    if (!mounted) return null;
    final use = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New suggested goal'),
        content: Text(
          'With your new weight, your suggested goal is '
          '${formatCardKcal(suggested)} kcal a day '
          '(was ${formatCardKcal(current.calories)}).\n\n'
          'Your macros would be ${next.protein.round()}g protein, '
          '${next.carbs.round()}g carbs and ${next.fat.round()}g fat, '
          'the same split as now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep my goal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use it'),
          ),
        ],
      ),
    );
    return use == true ? next : null;
  }

  /// Moves the daily goal by [change] kcal, keeping the macro split and
  /// what's been eaten today.
  Future<void> _applyNudge(int change) async {
    final uid = _uid;
    if (uid == null || _applyingNudge) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _applyingNudge = true);
    try {
      final doc = await BalanceService.userDataDoc(uid);
      final data = doc?.data();
      final goals = data == null ? null : BalanceService.goalsFrom(data);
      if (goals == null) throw StateError('No goals');
      final kcal = (goals.calories + change).round();
      final next = macrosScaledTo(goals, kcal);
      await BalanceService.applyGoals(uid, goals: next);
      FoodLog.notifyChanged();
      await _snoozeCheckIn();
      messenger.showSnackBar(SnackBar(
          content: Text('Daily goal is now ${formatCardKcal(kcal)} kcal. '
              'Your card is up to date.')));
      await _loadProfile();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't change your goal. Please try again.")));
    } finally {
      if (mounted) setState(() => _applyingNudge = false);
    }
  }

  Future<void> _delete(WeighIn w) async {
    final uid = _uid;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await WeightService.delete(uid, w.dateKey);
      messenger.showSnackBar(SnackBar(
        content: Text('Removed ${_shortDate(w.date)}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => WeightService.log(uid, w.kg, on: w.date),
        ),
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't remove that. Please try again.")));
    }
  }

  // ---------------------------------------------------------------------------

  Widget _card({required Widget child}) => Container(
        decoration: AppDecor.card,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: child,
      );

  Widget _title(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.gray800,
        ),
      );

  Widget _todayCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title("Today's weight"),
          const SizedBox(height: 4),
          Text(
            'Weigh yourself at the same time each day, ideally first thing '
            'in the morning. Logging twice in a day just updates it.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          WeightInput(
            units: _units,
            valueKg: _entryKg,
            label: 'Weight',
            onChanged: (kg) => setState(() => _entryKg = kg),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save weight',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: AppDecor.inset,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendCard(List<WeighIn> all) {
    final now = BalanceService.now();
    final recent = WeightService.lastDays(all, 90, now: now);
    final smooth = WeightService.smoothed(recent);
    final first = all.isEmpty ? null : all.first;
    final last = all.isEmpty ? null : all.last;

    final String chartLabel;
    if (recent.length >= 2) {
      chartLabel = 'Weight over the last 90 days: from '
          '${Units.formatWeight(recent.first.kg, _units)} on '
          '${_shortDate(recent.first.date)} to '
          '${Units.formatWeight(recent.last.kg, _units)} on '
          '${_shortDate(recent.last.date)}.';
    } else {
      chartLabel = 'Not enough weigh-ins for a chart yet.';
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('Your trend'),
          const SizedBox(height: 12),
          if (last != null)
            Row(
              children: [
                _stat('Latest · ${_shortDate(last.date)}',
                    Units.formatWeight(last.kg, _units)),
                const SizedBox(width: 8),
                _stat(
                  first != null && first.dateKey != last.dateKey
                      ? 'Since ${_shortDate(first.date)}'
                      : 'Change',
                  first != null && first.dateKey != last.dateKey
                      ? Units.formatWeightChange(last.kg - first.kg, _units)
                      : '–',
                ),
              ],
            ),
          const SizedBox(height: 14),
          Semantics(
            label: chartLabel,
            child: ExcludeSemantics(
              child: recent.length < 2
                  ? Container(
                      height: 120,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(12),
                      decoration: AppDecor.inset,
                      child: Text(
                        all.isEmpty
                            ? 'Log your weight on a few days to see your '
                                'trend here.'
                            : 'One more weigh-in and your trend appears '
                                'here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    )
                  : SizedBox(
                      height: 190,
                      child: CustomPaint(
                        painter: _TrendPainter(
                          points: recent,
                          smooth: smooth,
                          from: BalanceService.addDays(
                              BalanceService.startOfDay(now), -89),
                          to: BalanceService.startOfDay(now),
                          units: _units,
                          dotColor: AppColors.primary.withValues(alpha: 0.45),
                          lineColor: AppText.primary,
                          gridColor: AppColors.border,
                          labelColor: AppColors.muted,
                        ),
                      ),
                    ),
            ),
          ),
          if (recent.length >= 2) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _legendDot(AppColors.primary.withValues(alpha: 0.45)),
                const SizedBox(width: 6),
                Text('Weigh-ins',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(width: 16),
                Container(
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppText.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '7-day average',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendDot(Color c) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  /// The check-in, once there are three weeks of weigh-ins.
  Widget? _checkInCard(List<WeighIn> all) {
    final profile = _profile;
    if (profile == null || _checkInSnoozed) return null;
    final goals = BalanceService.goalsFrom(profile);
    if (goals == null || all.isEmpty) return null;
    final mode = profile['calorie_mode'];
    final c = WeightService.checkIn(
      history: all,
      mode: mode is String ? mode : null,
      goalKcal: goals.calories,
      floorKcal: _floorFor(all.last.kg),
    );
    if (c == null) return null;

    final rate = Units.formatRate(c.kgPerWeek, _units);
    final losing = c.kgPerWeek < 0;
    final change = c.suggestedChange;
    final amount = '${change.abs()} kcal';

    String title;
    String body;
    String? action;
    if (c.atSafeMinimum) {
      title = "Your weight's holding steady";
      body = 'Over the last four weeks it has moved about $rate a week. '
          "Your goal is already at the lowest we'd suggest, so we won't "
          'lower it. A little more activity, or a look at portion sizes, '
          'can help.';
    } else if (c.onTrack) {
      title = "You're on track";
      body = switch (c.mode) {
        'gain' => "You've gained about $rate a week over the last four "
            'weeks. A steady pace.',
        'maintain' => 'Your weight has stayed steady over the last four '
            'weeks. Nicely done.',
        _ => "You've lost about $rate a week over the last four weeks. "
            "That's a steady pace you can keep up.",
      };
    } else {
      final direction = losing ? 'down' : 'up';
      switch (c.mode) {
        case 'lose':
          title = change < 0
              ? "Your weight's holding steady"
              : "You're losing quite quickly";
          body = change < 0
              ? 'Over the last four weeks it has gone $direction about '
                  '$rate a week. Taking $amount off your daily goal '
                  'could get things moving again.'
              : "You've been losing about $rate a week. Adding $amount a "
                  'day can make it easier to keep going.';
        case 'gain':
          title = change > 0
              ? "Your weight isn't going up yet"
              : "You're gaining quite quickly";
          body = change > 0
              ? 'Over the last four weeks it has gone $direction about '
                  '$rate a week. Adding $amount to your daily goal can help.'
              : "You've been gaining about $rate a week. Taking $amount off "
                  'keeps it steadier.';
        default:
          title = "Your weight's drifting $direction";
          body = 'Over the last four weeks it has gone $direction about '
              '$rate a week. ${change < 0 ? 'Taking $amount off' : 'Adding $amount to'} '
              'your daily goal should steady it.';
      }
      action = change < 0 ? 'Take off $amount' : 'Add $amount';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.indigo50,
        borderRadius: BorderRadius.circular(AppDecor.radius),
        border: Border.all(color: AppColors.indigo100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: AppText.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
                fontSize: 13.5, height: 1.4, color: AppColors.gray700),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              if (!c.onTrack)
                TextButton(
                  onPressed: _applyingNudge ? null : _snoozeCheckIn,
                  child: Text(action == null ? 'OK' : 'Not now'),
                ),
              if (action != null)
                FilledButton(
                  onPressed:
                      _applyingNudge ? null : () => _applyNudge(change),
                  child: Text(action),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recentList(List<WeighIn> all) {
    final items = all.reversed.take(7).toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('Recent weigh-ins'),
          const SizedBox(height: 4),
          for (final w in items)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _shortDate(w.date),
                    style: TextStyle(fontSize: 14, color: AppColors.gray700),
                  ),
                ),
                Text(
                  Units.formatWeight(w.kg, _units),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove ${_shortDate(w.date)}',
                  onPressed: () => _delete(w),
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: AppColors.gray400),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = _history;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('My weight')),
      body: stream == null
          ? const Center(child: Text('Sign in to log your weight.'))
          : StreamBuilder<List<WeighIn>>(
              stream: stream,
              builder: (context, snapshot) {
                final all = snapshot.data ?? const <WeighIn>[];
                final waiting = _loadingProfile ||
                    (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData);
                if (waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final checkIn = _checkInCard(all);
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxWidth: Breakpoints.contentMaxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (snapshot.hasError) ...[
                            Text(
                              "Couldn't load your weight log. Check your "
                              'connection.',
                              style: TextStyle(color: AppText.red600),
                            ),
                            const SizedBox(height: 12),
                          ],
                          _todayCard(),
                          if (checkIn != null) ...[
                            const SizedBox(height: 16),
                            checkIn,
                          ],
                          const SizedBox(height: 16),
                          _trendCard(all),
                          if (all.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _recentList(all),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// The last 90 days: a dot per weigh-in and a 7-day average line.
class _TrendPainter extends CustomPainter {
  final List<WeighIn> points;
  final List<double> smooth;
  final DateTime from;
  final DateTime to;
  final UnitPrefs units;
  final Color dotColor;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;

  _TrendPainter({
    required this.points,
    required this.smooth,
    required this.from,
    required this.to,
    required this.units,
    required this.dotColor,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || smooth.length != points.length) return;
    final values = [...points.map((p) => p.kg), ...smooth];
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    // At least 2 kg of range, so small changes don't look dramatic.
    if (hi - lo < 2) {
      final mid = (hi + lo) / 2;
      lo = mid - 1;
      hi = mid + 1;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;

    const leftGutter = 76.0;
    const bottom = 8.0;
    final chart = Rect.fromLTRB(
        leftGutter, 6, size.width - 6, size.height - bottom);
    final days = math.max(1, to.difference(from).inHours / 24);

    double x(DateTime d) =>
        chart.left +
        (d.difference(from).inHours / 24 / days).clamp(0.0, 1.0) *
            chart.width;
    double y(double kg) =>
        chart.bottom - (kg - lo) / (hi - lo) * chart.height;

    // Three gridlines with labels in the person's units.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final kg = lo + (hi - lo) * (0.15 + 0.35 * i);
      final gy = y(kg);
      canvas.drawLine(Offset(chart.left, gy), Offset(chart.right, gy), grid);
      final tp = TextPainter(
        text: TextSpan(
          text: Units.formatWeight(kg, units),
          style: TextStyle(fontSize: 11, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: leftGutter - 6);
      tp.paint(canvas, Offset(0, gy - tp.height / 2));
      tp.dispose();
    }

    final dot = Paint()..color = dotColor;
    for (final p in points) {
      canvas.drawCircle(Offset(x(p.date), y(p.kg)), 3.5, dot);
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(x(points[i].date), y(smooth[i]));
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points ||
      old.smooth != smooth ||
      old.units != units ||
      old.lineColor != lineColor ||
      old.dotColor != dotColor;
}
