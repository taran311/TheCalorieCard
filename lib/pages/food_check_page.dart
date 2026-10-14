import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:namer_app/ui/responsive.dart';

/// Admin only: looks up the test foods on the live server and shows how
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

/// A saved answer someone corrected (see GET /admin/food-corrections).
class _Corrected {
  final String food;
  final String kind; // "text": those exact words; "food": any amount of it
  final int people;
  final int? calories;

  const _Corrected(this.food, this.kind, this.people, this.calories);
}

class _FoodCheckPageState extends State<FoodCheckPage> {
  List<_CheckFood>? _foods;
  String? _loadError;
  bool _running = false;

  /// The last full run's score on this device, to compare against.
  String? _lastRun;
  static const _lastRunKey = 'food_check_last_run';

  List<_Corrected>? _corrected;

  /// Lookups at once: quick, without hammering the server.
  static const _concurrency = 3;

  @override
  void initState() {
    super.initState();
    _load();
    _loadLastRun();
    _loadCorrected();
  }

  Future<void> _loadLastRun() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_lastRunKey);
      if (mounted && last != null) setState(() => _lastRun = last);
    } catch (_) {}
  }

  /// After a full run: remember its score, to compare the next one with.
  Future<void> _saveLastRun(List<_CheckFood> foods) async {
    final done = foods.where((f) => f.done).toList();
    if (done.length < foods.length) return;
    final hits = done.where((f) => f.ok).length;
    final diffs = [
      for (final f in done)
        if (f.result != null) _n(f.result!['diff']).abs()
    ];
    final avg =
        diffs.isEmpty ? 0 : diffs.reduce((a, b) => a + b) / diffs.length;
    final now = DateTime.now();
    final text = '$hits of ${done.length} within range, average '
        '${avg.toStringAsFixed(1)}% (${now.day}/${now.month}/${now.year})';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRunKey, text);
    } catch (_) {}
  }

  Future<void> _loadCorrected() async {
    try {
      final r = await ProxyClient.get('/admin/food-corrections')
          .timeout(const Duration(seconds: 60));
      final j = json.decode(r.body);
      if (r.statusCode != 200 || j is! Map) return;
      final list = [
        for (final f in (j['foods'] as List? ?? const []))
          if (f is Map)
            _Corrected('${f['food']}', '${f['kind']}', _n(f['people']).round(),
                f['calories'] is num ? (f['calories'] as num).round() : null),
      ];
      if (mounted) setState(() => _corrected = list);
    } catch (_) {}
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
    if (!mounted) return;
    // Shown until the next full run, so the two can be compared.
    final before = _lastRun;
    await _saveLastRun(foods);
    if (mounted) {
      setState(() {
        _running = false;
        _previousRun = before;
      });
    }
  }

  /// The score before this session's run, shown beside the new one.
  String? _previousRun;

  Widget _summary(List<_CheckFood> foods) {
    final done = foods.where((f) => f.done).toList();
    final hits = done.where((f) => f.ok).length;
    final diffs = [
      for (final f in done)
        if (f.result != null) _n(f.result!['diff']).abs()
    ];
    final avg =
        diffs.isEmpty ? 0 : diffs.reduce((a, b) => a + b) / diffs.length;
    // Per source: how many it answered, and how many of those were in range.
    final bySource = <String, int>{};
    final hitsBySource = <String, int>{};
    for (final f in done) {
      final s = '${f.result?['source'] ?? 'failed'}';
      bySource[s] = (bySource[s] ?? 0) + 1;
      if (f.ok) hitsBySource[s] = (hitsBySource[s] ?? 0) + 1;
    }
    final last = _previousRun ?? _lastRun;
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
              'Average difference ${avg.toStringAsFixed(1)}%',
              style: TextStyle(color: AppColors.gray600),
            ),
            const SizedBox(height: 2),
            Text(
              bySource.entries
                  .map((e) => '${_sourceLabel(e.key)}: '
                      '${hitsBySource[e.key] ?? 0} of ${e.value} in range')
                  .join(' · '),
              style: TextStyle(fontSize: 12.5, color: AppColors.gray600),
            ),
          ],
          if (last != null) ...[
            const SizedBox(height: 4),
            Text(
              '${_previousRun != null ? 'Run before' : 'Last full run'}: $last',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
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
        'label' => 'UK label',
        'tables' => 'UK food tables',
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

  /// Saved answers people corrected: foods the lookup got wrong for
  /// someone. Each can be forgotten here (and is worth adding to the
  /// test list in benchmark/foods.json).
  List<Widget> _correctedSection() {
    final list = _corrected;
    if (list == null || list.isEmpty) return const [];
    return [
      const SizedBox(height: 20),
      Text(
        'Corrected by people',
        style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
      ),
      const SizedBox(height: 4),
      Text(
        'Saved answers someone fixed the calories of. 3 people and it\'s '
        'looked up afresh automatically.',
        style: TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(AppDecor.radius),
        child: Container(
          decoration: AppDecor.card,
          child: Column(
            children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.border),
                ListTile(
                  title: Text(list[i].food),
                  subtitle: Text([
                    '${list[i].people} '
                        '${list[i].people == 1 ? 'person' : 'people'}',
                    if (list[i].calories != null) 'we said ${list[i].calories} kcal',
                    if (list[i].kind == 'food') 'any amount',
                  ].join(' · ')),
                  trailing: TextButton(
                    onPressed: () => _forgetFood(initial: list[i].food),
                    child: const Text('Forget'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  /// Drops a saved answer (that text, and that food in any amount), so
  /// it's looked up afresh next time someone asks.
  Future<void> _forgetFood({String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    final food = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget a saved food'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'e.g. 3 McCain hash browns',
            helperText: 'Type it as people did. Any amount of it is forgotten.',
            helperMaxLines: 2,
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (food == null || food.isEmpty || !mounted) return;
    String message;
    try {
      final r = await ProxyClient.post('/admin/food-forget', {'food': food})
          .timeout(const Duration(seconds: 30));
      message = r.statusCode == 200
          ? 'Forgotten. "$food" will be looked up afresh.'
          : "Couldn't forget that. Is the server up to date?";
    } catch (_) {
      message = "Couldn't forget that. Please try again.";
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    _loadCorrected();
  }

  @override
  Widget build(BuildContext context) {
    final foods = _foods;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Food check'),
        actions: [
          IconButton(
            tooltip: 'Forget a saved food',
            onPressed: _forgetFood,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
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
                        ..._correctedSection(),
                      ],
                    ),
        ),
      ),
    );
  }
}
