import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/ui/responsive.dart';

/// Admin only: everyone with a card, most recently active first, with when
/// they were last using the app. Read from the server (GET /admin/users).
class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _Person {
  final String name;
  final String? username;
  final DateTime? lastSeen;
  final DateTime? joined;

  const _Person(this.name, this.username, this.lastSeen, this.joined);
}

class _PeoplePageState extends State<PeoplePage> {
  List<_Person>? _people;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ProxyClient.get('/admin/users')
          .timeout(const Duration(seconds: 60));
      final j = json.decode(r.body);
      if (r.statusCode != 200 || j is! Map) throw Exception();
      final people = [
        for (final u in (j['users'] as List? ?? const []))
          if (u is Map)
            _Person(
              '${u['name'] ?? 'Unknown'}',
              u['username'] is String ? u['username'] as String : null,
              _time(u['last_seen']),
              _time(u['joined']),
            ),
      ];
      if (mounted) setState(() => _people = people);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = "Couldn't load people. Is the server up to date?");
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  /// "Today", "Yesterday" or "Earlier", for the sections.
  static String _section(DateTime? t) {
    if (t == null) return 'Not seen yet';
    final today = _day(DateTime.now());
    final d = _day(t);
    if (d == today) return 'Today';
    if (d == DateTime(today.year, today.month, today.day - 1)) {
      return 'Yesterday';
    }
    return 'Earlier';
  }

  /// "09:12", or "12 Oct, 18:05" for earlier days.
  static String _when(DateTime t) {
    final s = _section(t);
    if (s == 'Today' || s == 'Yesterday') return _clock(t);
    return '${t.day} ${_months[t.month - 1]}, ${_clock(t)}';
  }

  Widget _row(_Person p) {
    final seen = p.lastSeen;
    final joined = p.joined;
    final details = [
      if (p.username != null) '@${p.username}',
      if (joined != null)
        'joined ${joined.day} ${_months[joined.month - 1]} ${joined.year}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.indigo50,
            child: Text(
              p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
              style: TextStyle(
                  color: AppText.primary, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.ink)),
                if (details.isNotEmpty)
                  Text(details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: AppColors.gray600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            seen == null ? '–' : _when(seen),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final sections = <String, List<_Person>>{};
    for (final p in people ?? const <_Person>[]) {
      sections.putIfAbsent(_section(p.lastSeen), () => []).add(p);
    }
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('People'),
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
              : people == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          Text(
                            '${people.length} '
                            '${people.length == 1 ? 'person' : 'people'} · '
                            '${sections['Today']?.length ?? 0} active today, '
                            '${sections['Yesterday']?.length ?? 0} yesterday',
                            style: TextStyle(color: AppColors.gray600),
                          ),
                          for (final name in const [
                            'Today',
                            'Yesterday',
                            'Earlier',
                            'Not seen yet',
                          ])
                            if (sections[name]?.isNotEmpty ?? false) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(4, 18, 4, 8),
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(AppDecor.radius),
                                child: Container(
                                  decoration: AppDecor.card,
                                  child: Column(
                                    children: [
                                      for (var i = 0;
                                          i < sections[name]!.length;
                                          i++) ...[
                                        if (i > 0)
                                          Divider(
                                              height: 1,
                                              color: AppColors.border),
                                        _row(sections[name]![i]),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          const SizedBox(height: 10),
                          Text(
                            'Last seen is when they last had the app open, to '
                            'within a few minutes (about an hour for anyone '
                            "who hasn't opened the latest version yet). "
                            'Times are in your time zone.',
                            style:
                                TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}
