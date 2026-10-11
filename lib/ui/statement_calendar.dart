import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/statement_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/statement_widgets.dart';

/// How a calendar day is marked. Worked out from [DaySummary.onBudget], the
/// same rule as the statement and Hiscores.
enum CalendarMark { none, onBudget, over, rest }

class CalendarDay {
  final CalendarMark mark;

  /// kcal over budget, for [CalendarMark.over].
  final double over;

  const CalendarDay(this.mark, [this.over = 0]);

  /// Today only gets a tick once it's finished (it isn't over yet), but
  /// going over shows straight away. A rest day shows 🏖️.
  static CalendarDay of(DaySummary d, double? fallback, {required bool today}) {
    if (d.restDay) return const CalendarDay(CalendarMark.rest);
    final over = d.overBy(fallback);
    if (over != null) return CalendarDay(CalendarMark.over, over);
    if (d.onBudget(fallback) == true && (!today || d.finished)) {
      return const CalendarDay(CalendarMark.onBudget);
    }
    return const CalendarDay(CalendarMark.none);
  }
}

/// A month of the statement as a calendar, like the calendar in a banking
/// app's spending trends: ✓ for days on budget, +N for days over.
class StatementCalendar extends StatefulWidget {
  final String userId;

  /// Shown above the month (the List / Calendar switch).
  final Widget header;

  /// A day was tapped. [summary] is null for a day with nothing loaded;
  /// [fallbackBudget] is today's goal, for days without their own.
  final void Function(DateTime day, DaySummary? summary, double? fallbackBudget)
      onOpenDay;

  const StatementCalendar({
    super.key,
    required this.userId,
    required this.header,
    required this.onOpenDay,
  });

  @override
  State<StatementCalendar> createState() => _StatementCalendarState();
}

class _StatementCalendarState extends State<StatementCalendar> {
  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday'
  ];

  /// First day of the month on show.
  late DateTime _month = _firstOf(BalanceService.now());

  /// Loaded once per month (not in build).
  late Future<Statement> _load = _fetch();

  static DateTime _firstOf(DateTime d) => DateTime(d.year, d.month);

  bool get _isCurrentMonth {
    final now = BalanceService.now();
    return _month.year == now.year && _month.month == now.month;
  }

  /// The month's days up to today (no point reading the future).
  Future<Statement> _fetch() {
    final today = BalanceService.startOfDay(BalanceService.now());
    final nextMonth = DateTime(_month.year, _month.month + 1);
    final tomorrow = BalanceService.addDays(today, 1);
    final end = nextMonth.isBefore(tomorrow) ? nextMonth : tomorrow;
    return StatementService.loadRange(widget.userId, _month, end);
  }

  void _moveMonth(int by) {
    setState(() {
      _month = DateTime(_month.year, _month.month + by);
      _load = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        widget.header,
        const SizedBox(height: 16),
        PanelCard(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => _moveMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      formatMonth(_month),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: _isCurrentMonth ? null : () => _moveMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Semantics(
                        label: _weekdayNames[i],
                        excludeSemantics: true,
                        child: Text(
                          _weekdays[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              FutureBuilder<Statement>(
                future: _load,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Text(
                            "Couldn't load this month.",
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () =>
                                setState(() => _load = _fetch()),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    );
                  }
                  final s = snap.data;
                  if (s == null) {
                    return const SizedBox(
                      height: 280,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _grid(s);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _CalendarLegend(),
      ],
    );
  }

  Widget _grid(Statement s) {
    final byKey = {
      for (final d in s.days) BalanceService.dateKey(d.day): d,
    };
    final now = BalanceService.now();
    final todayKey = BalanceService.dateKey(now);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = _month.weekday - 1; // Monday first
    final cells = lead + daysInMonth;
    final rows = (cells / 7).ceil();

    var onBudget = 0, over = 0, logged = 0;
    for (final d in s.days) {
      if (d.transactions.isNotEmpty) logged++;
      final mark = CalendarDay.of(d, s.dailyBudget,
              today: BalanceService.dateKey(d.day) == todayKey)
          .mark;
      if (mark == CalendarMark.onBudget) onBudget++;
      if (mark == CalendarMark.over) over++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cell(r * 7 + c - lead + 1, daysInMonth,
                    byKey, s.dailyBudget, todayKey)),
            ],
          ),
        const SizedBox(height: 10),
        Text(
          [
            '${formatDays(onBudget)} on budget',
            '${formatDays(over)} over',
            '${formatDays(logged)} logged',
          ].join(' · '),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.gray700,
          ),
        ),
      ],
    );
  }

  Widget _cell(int dayNumber, int daysInMonth, Map<String, DaySummary> byKey,
      double? fallback, String todayKey) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 54);
    }
    final date = DateTime(_month.year, _month.month, dayNumber);
    final key = BalanceService.dateKey(date);
    final summary = byKey[key];
    final isToday = key == todayKey;
    final future = summary == null && key.compareTo(todayKey) > 0;
    final info = summary == null
        ? const CalendarDay(CalendarMark.none)
        : CalendarDay.of(summary, fallback, today: isToday);

    final logged = summary != null && summary.transactions.isNotEmpty;
    final (Color? fill, String markText, Color markColor, String spoken) =
        switch (info.mark) {
      CalendarMark.onBudget => (
          AppColors.green.withValues(alpha: 0.14),
          '✓',
          AppText.emerald700,
          'on budget',
        ),
      CalendarMark.over => (
          AppColors.red.withValues(alpha: 0.12),
          '+${formatKcal(info.over)}',
          AppText.red600,
          'over budget by ${formatKcal(info.over)} kcal',
        ),
      CalendarMark.rest => (
          AppColors.sky.withValues(alpha: 0.10),
          '🏖️',
          AppColors.ink,
          'rest day',
        ),
      CalendarMark.none => (
          null,
          '',
          AppColors.muted,
          future
              ? 'not yet'
              : logged
                  ? '${formatKcal(summary?.calories ?? 0)} kcal so far'
                  : 'nothing logged',
        ),
    };

    final content = Container(
      height: 54,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: isToday
            ? Border.all(color: AppColors.primary, width: 2)
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      // Scales down on narrow phones, long "+1,320"s and big text sizes.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$dayNumber',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: future ? AppColors.gray400 : AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              // Keeps the day number in the same place on blank days.
              markText.isEmpty ? ' ' : markText,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: markColor,
              ),
            ),
          ],
        ),
      ),
    );

    final label = '${formatDayShort(date)}${isToday ? ', today' : ''}, $spoken';
    if (future) {
      return Semantics(label: label, excludeSemantics: true, child: content);
    }
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => widget.onOpenDay(date, summary, fallback),
        child: content,
      ),
    );
  }

}

/// Key for the calendar, in words as well as colour.
class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, color: AppColors.muted);
    Widget item(Widget swatch, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [swatch, const SizedBox(width: 6), Text(text, style: style)],
        );
    Widget box(
            {Color? fill, Border? border, String text = '', Color? color}) =>
        Container(
          width: 26,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            border: border,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color ?? AppColors.ink)),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 8,
      children: [
        item(
            box(
                fill: AppColors.green.withValues(alpha: 0.14),
                text: '✓',
                color: AppText.emerald700),
            'On budget'),
        item(
            box(
                fill: AppColors.red.withValues(alpha: 0.12),
                text: '+N',
                color: AppText.red600),
            'kcal over'),
        item(box(fill: AppColors.sky.withValues(alpha: 0.10), text: '🏖️'),
            'Rest day'),
        item(box(border: Border.all(color: AppColors.primary, width: 2)),
            'Today'),
      ],
    );
  }
}
