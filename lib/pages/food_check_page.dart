import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/ui/responsive.dart';

/// Admin only: looks up the 40 test foods on the live server and shows how
/// close each answer is to its known value, so a change to the lookup can
/// be checked in a minute. The list lives in the server's
/// benchmark/foods.json.
class FoodCheckPage extends StatefulWidget {
  const FoodCheckPage({super.key});

  @override
  State<FoodCheckPage> createState() => _FoodCheckPageState();
}

class _CheckFood {
  final String query;
  final double kcal;
  final String ref;
  final double tolerance;
  Map<String, dynamic>? result;
  String? error;
  bool running = false;

  _CheckFood(this.query, this.kcal, this.ref, this.tolerance);

  bool get done => result != null || error != null;
  bool get ok => result?['ok'] == true;
}

class _FoodCheckPageState extends State<FoodCheckPage> {
  List<_CheckFood>? _foods;
  String? _loadError;
  bool _running = false;

  /// Lookups at once: quick, without hammering the server.
  static const _concurrency = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static double _n(dynamic v) => v is num ? v.toDouble() : 0;

  Future<void> _load() async {
    try {
      final r = await ProxyClient.get('/admin/food-check')
          .timeout(const Duration(seconds: 60));
      final j = json.decode(r.body);
      if (r.statusCode != 200 || j is! Map) {
        throw Exception(j is Map ? j['error'] : 'Failed');
      }
      final foods = [
        for (final f in (j['foods'] as List? ?? const []))
          if (f is Map)
            _CheckFood('${f['query']}', _n(f['kcal']), '${f['ref'] ?? ''}',
                _n(f['tolerance']) == 0 ? 15 : _n(f['tolerance'])),
      ];
      if (mounted) setState(() => _foods = foods);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError =
            "Couldn't load the food list. Is the server up to date?");
      }
    }
  }

  Future<void> _checkOne(int i) async {
    final f = _foods![i];
    setState(() {
      f.running = true;
      f.result = null;
      f.error = null;
    });
    try {
      final r = await ProxyClient.post('/admin/food-check', {'index': i})
          .timeout(const Duration(seconds: 90));
      final j = json.decode(r.body);
      if (r.statusCode != 200 || j is! Map<String, dynamic>) {
        throw Exception();
      }
      f.result = j;
    } catch (_) {
      f.error = 'Lookup failed';
    }
    if (mounted) setState(() => f.running = false);
  }

  Future<void> _runAll() async {
    final foods = _foods;
    if (foods == null || _running) return;
    setState(() {
      _running = true;
      for (final f in foods) {
        f.result = null;
        f.error = null;
      }
    });
    var next = 0;
    Future<void> worker() async {
      while (mounted) {
        final i = next++;
        if (i >= foods.length) return;
        await _checkOne(i);
      }
    }

    await Future.wait([for (var w = 0; w < _concurrency; w++) worker()]);
    if (mounted) setState(() => _running = false);
  }

  Widget _summary(List<_CheckFood> foods) {
    final done = foods.where((f) => f.done).toList();
    final hits = done.where((f) => f.ok).length;
    final diffs = [
      for (final f in done)
        if (f.result != null) _n(f.result!['diff']).abs()
    ];
    final avg =
        diffs.isEmpty ? 0 : diffs.reduce((a, b) => a + b) / diffs.length;
    final bySource = <String, int>{};
    for (final f in done) {
      final s = '${f.result?['source'] ?? 'failed'}';
      bySource[s] = (bySource[s] ?? 0) + 1;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecor.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            done.isEmpty
                ? '${foods.length} foods, each with a known calorie value.'
                : '$hits of ${done.length} within range'
                    '${done.length < foods.length ? ' so far' : ''}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Average difference ${avg.toStringAsFixed(1)}% · '
              '${bySource.entries.map((e) => '${_sourceLabel(e.key)} ${e.value}').join(', ')}',
              style: TextStyle(color: AppColors.gray600),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
            onPressed: _running ? null : _runAll,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_running
                ? 'Checking ${done.length} of ${foods.length}…'
                : done.isEmpty
                    ? 'Run the check'
                    : 'Run again'),
          ),
              if (done.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _copyResults(foods),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy results'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Looks every food up fresh on the live server (about a minute, '
            'a few pence of AI use).',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  /// The results as plain text, misses first, ready to paste into a chat.
  String _resultsText(List<_CheckFood> foods) {
    final done = foods.where((f) => f.done).toList();
    final hits = done.where((f) => f.ok).length;
    String line(_CheckFood f) {
      final r = f.result;
      if (r == null) {
        return 'ERROR ${f.query} | expected ${f.kcal.round()} | ${f.error}';
      }
      final diff = _n(r['diff']);
      return [
        '${f.ok ? 'ok' : 'MISS'} ${f.query}',
        'expected ${f.kcal.round()} (±${f.tolerance.round()}%)',
        'got ${r['kcal']} (${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}%)',
        'P${r['protein']} C${r['carbs']} F${r['fat']}',
        _sourceLabel('${r['source']}'),
        if ('${r['portion']}'.isNotEmpty) 'portion: ${r['portion']}',
        if ('${r['name']}'.isNotEmpty) 'matched: ${r['name']}',
        if ('${r['why']}'.isNotEmpty) 'why: ${r['why']}',
        'ref: ${f.ref}',
      ].join(' | ');
    }

    final misses = done.where((f) => !f.ok).toList();
    final passes = done.where((f) => f.ok).toList();
    return [
      'Food check: $hits of ${done.length} within range',
      if (misses.isNotEmpty) ...['', 'Misses:', ...misses.map(line)],
      if (passes.isNotEmpty) ...['', 'Within range:', ...passes.map(line)],
    ].join('\n');
  }

  Future<void> _copyResults(List<_CheckFood> foods) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: _resultsText(foods)));
      messenger.showSnackBar(const SnackBar(
          content: Text('Results copied. Paste them into a message.')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't copy the results.")));
    }
  }

  static String _sourceLabel(String s) => switch (s) {
        'fatsecret' => 'database',
        'ai' => 'AI',
        'web' => 'web label',
        _ => s,
      };

  Widget _row(int i, _CheckFood f) {
    final r = f.result;
    final Widget status;
    if (f.running) {
      status = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (f.error != null) {
      status = Icon(Icons.error_outline, color: AppText.red600);
    } else if (r == null) {
      status = Icon(Icons.circle_outlined, color: AppColors.gray400, size: 20);
    } else if (f.ok) {
      status = Icon(Icons.check_circle, color: AppText.emerald600);
    } else {
      status = Icon(Icons.warning_amber_rounded, color: AppText.amber700);
    }
    final diff = r == null ? null : _n(r['diff']);
    final details = r == null
        ? (f.error ?? 'Expected ${f.kcal.round()} kcal · ${f.ref}')
        : [
            'Expected ${f.kcal.round()} · got ${r['kcal']} kcal '
                '(${diff! >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}%)',
            [
              _sourceLabel('${r['source']}'),
              if ('${r['portion']}'.isNotEmpty) '${r['portion']}',
              if ('${r['name']}'.isNotEmpty && '${r['name']}' != f.query)
                '"${r['name']}"',
            ].join(' · '),
          ].join('\n');
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: _running || f.running ? null : () => _checkOne(i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: status),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.query,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: TextStyle(fontSize: 12.5, color: AppColors.gray600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final foods = _foods;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Food check')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: _loadError != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_loadError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted)),
                )
              : foods == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        _summary(foods),
                        const SizedBox(height: 8),
                        Text(
                          'Tap a food to check just that one again.',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppDecor.radius),
                          child: Container(
                            decoration: AppDecor.card,
                            child: Column(
                              children: [
                                for (var i = 0; i < foods.length; i++) ...[
                                  if (i > 0)
                                    Divider(
                                        height: 1, color: AppColors.border),
                                  _row(i, foods[i]),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
