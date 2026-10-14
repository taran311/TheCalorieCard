import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/ui/responsive.dart';

/// Admin only: daily counts the server keeps (no cookies, no third
/// parties). Shows today, the last 7 days and the last 28 days, plus the
/// two numbers that matter most before spending on ads: how many new
/// cards log a first food, and how many come back the next day.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _Metric {
  final String key;
  final String label;
  final String help;
  const _Metric(this.key, this.label, this.help);
}

class _StatsPageState extends State<StatsPage> {
  /// Newest first: index 0 is today.
  List<Map<String, num>>? _days;
  String? _error;
  bool _loading = false;

  static const _metrics = [
    _Metric('active', 'Active people', 'Opened the app (once a day each)'),
    _Metric('card_created', 'New cards', 'Finished setting up a card'),
    _Metric('first_food', 'First food logged', 'New people logging for the first time'),
    _Metric('food_logged', 'Foods logged', 'Each time food was added'),
    _Metric('day_closed', 'Days closed', 'Days paid off at the end'),
    _Metric('back_day_1', 'Back next day', 'Opened the day after joining'),
    _Metric('back_day_7', 'Back a week later', 'Opened 7 days after joining'),
    _Metric('premium_started', 'Premium started', 'New paid subscriptions'),
    _Metric('gift_redeemed', 'Gift codes used', 'Premium given by code'),
    _Metric('food_lookup', 'Food lookups', 'Server lookups (AI and database)'),
    _Metric('food_lookup_saved', 'Saved answers used',
        'Lookups answered from saved foods, no AI needed'),
    _Metric('coach_message', 'Coach messages', 'Messages sent to the Coach'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ProxyClient.get('/admin/stats', query: {'days': '28'})
          .timeout(const Duration(seconds: 60));
      final j = json.decode(r.body);
      if (r.statusCode != 200 || j is! Map) {
        throw Exception(j is Map ? j['error'] : 'Failed');
      }
      final days = <Map<String, num>>[
        for (final d in (j['days'] as List? ?? const []))
          if (d is Map)
            {
              for (final e in ((d['counts'] as Map?) ?? const {}).entries)
                if (e.value is num) '${e.key}': e.value as num,
            },
      ];
      if (mounted) setState(() => _days = days);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = "Couldn't load the stats. Is the server up to date?");
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  num _sum(String key, int days) {
    final list = _days ?? const [];
    num total = 0;
    for (var i = 0; i < days && i < list.length; i++) {
      total += list[i][key] ?? 0;
    }
    return total;
  }

  static String _fmt(num n) => n.round().toString();

  String _ratio(String top, String bottom, int days) {
    final b = _sum(bottom, days);
    if (b == 0) return '–';
    return '${(_sum(top, days) / b * 100).round()}%';
  }

  Widget _headerCell(String text) => SizedBox(
        width: 56,
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
      );

  Widget _numCell(String text) => SizedBox(
        width: 56,
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );

  Widget _row(String label, String help, List<String> values) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(help,
                      style:
                          TextStyle(fontSize: 12, color: AppColors.gray600)),
                ],
              ),
            ),
            for (final v in values) _numCell(v),
          ],
        ),
      );

  Widget _table(List<Widget> rows) => ClipRRect(
        borderRadius: BorderRadius.circular(AppDecor.radius),
        child: Container(
          decoration: AppDecor.card,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    _headerCell('Today'),
                    _headerCell('7 days'),
                    _headerCell('28 days'),
                  ],
                ),
              ),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.border),
                rows[i],
              ],
            ],
          ),
        ),
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final days = _days;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Stats'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted)),
                )
              : days == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        children: [
                          _heading('Are new people sticking?'),
                          _table([
                            _row(
                              'Log a first food',
                              'First foods ÷ new cards',
                              [
                                for (final d in const [1, 7, 28])
                                  _ratio('first_food', 'card_created', d),
                              ],
                            ),
                            _row(
                              'Come back next day',
                              'Back next day ÷ new cards',
                              [
                                for (final d in const [1, 7, 28])
                                  _ratio('back_day_1', 'card_created', d),
                              ],
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            'Rough guide: today\'s "back next day" counts '
                            'people who joined yesterday, so read the 7 and '
                            '28 day columns.',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.muted),
                          ),
                          _heading('Counts'),
                          _table([
                            for (final m in _metrics)
                              _row(m.label, m.help, [
                                for (final d in const [1, 7, 28])
                                  _fmt(_sum(m.key, d)),
                              ]),
                          ]),
                          const SizedBox(height: 8),
                          Text(
                            'Days run midnight to midnight UK time. Counting '
                            'started when this update went live.',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}
