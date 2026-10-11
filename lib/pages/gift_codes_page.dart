import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/services/web_platform.dart' as web;
import 'package:namer_app/ui/responsive.dart';

/// Lifetime Premium gift codes: make one, send it, see who used it.
/// Only shown to admins (the server checks every request too).
class GiftCodesPage extends StatefulWidget {
  const GiftCodesPage({super.key});

  @override
  State<GiftCodesPage> createState() => _GiftCodesPageState();
}

class _GiftCodesPageState extends State<GiftCodesPage> {
  List<GiftCode>? _codes;
  String? _error;
  bool _making = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final codes = await GiftCodes.list();
      if (mounted) {
        setState(() {
          _codes = codes;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is PremiumException
            ? e.message
            : "Couldn't load your codes.");
      }
    }
  }

  Future<void> _make() async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _NoteDialog(),
    );
    if (note == null || !mounted) return;
    setState(() => _making = true);
    try {
      final code = await GiftCodes.create(note: note);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Text('🎁', style: TextStyle(fontSize: 40)),
          title: const Text('Your code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Works once. Your friend enters it under Premium → '
                '"Have a code?".',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _share(code);
              },
              icon: const Icon(Icons.ios_share),
              label: const Text('Send'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is PremiumException
                ? e.message
                : "Couldn't make a code. Try again.")));
      }
    } finally {
      if (mounted) setState(() => _making = false);
    }
  }

  Future<void> _share(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = "Here's lifetime Premium on The Calorie Card, on me 💜 "
        'Open the app, go to Premium → "Have a code?" and enter $code';
    var shared = false;
    try {
      shared = await web.shareText(
          'Lifetime Premium on The Calorie Card', text,
          'https://thecaloriecard.com/');
    } catch (_) {}
    if (shared) return;
    try {
      await Clipboard.setData(ClipboardData(text: code));
      messenger.showSnackBar(SnackBar(content: Text('$code copied')));
    } catch (_) {}
  }

  Future<void> _cancel(GiftCode c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this code?'),
        content: Text('${c.code} will stop working. This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red600),
            child: const Text('Cancel code'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await GiftCodes.cancel(c.code);
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e is PremiumException
              ? e.message
              : "Couldn't cancel it. Try again.")));
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static String _date(DateTime? d) =>
      d == null ? '' : '${d.day} ${_months[d.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final codes = _codes;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Gift codes')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'gift-code-new',
        onPressed: _making ? null : _make,
        icon: _making
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: const Text('New code'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
              children: [
                Text(
                  'Each code gives one person lifetime Premium, free. It '
                  'works once, and only you can make them.',
                  style: TextStyle(color: AppColors.gray600, height: 1.35),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: AppText.red600))
                else if (codes == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (codes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No codes yet. Tap New code to make one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.gray600),
                    ),
                  )
                else
                  Container(
                    decoration: AppDecor.card,
                    child: Column(
                      children: [
                        for (final c in codes)
                          ListTile(
                            leading: Icon(
                              c.used
                                  ? Icons.check_circle
                                  : c.cancelled
                                      ? Icons.block
                                      : Icons.redeem_outlined,
                              color: c.used
                                  ? AppText.emerald600
                                  : c.cancelled
                                      ? AppColors.gray400
                                      : AppText.violet600,
                            ),
                            title: Text(
                              c.code,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                color: AppColors.ink,
                                decoration: c.cancelled
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (c.note.isNotEmpty) c.note,
                                if (c.used)
                                  'Used by ${c.redeemedName ?? 'someone'}'
                                      '${c.redeemedAt != null ? ' on ${_date(c.redeemedAt)}' : ''}'
                                else if (c.cancelled)
                                  'Cancelled'
                                else
                                  'Not used yet · made ${_date(c.createdAt)}',
                              ].join(' · '),
                              style: TextStyle(color: AppColors.gray600),
                            ),
                            trailing: c.open
                                ? PopupMenuButton<String>(
                                    tooltip: 'More',
                                    onSelected: (v) {
                                      if (v == 'send') _share(c.code);
                                      if (v == 'cancel') _cancel(c);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'send', child: Text('Send')),
                                      PopupMenuItem(
                                          value: 'cancel',
                                          child: Text('Cancel code')),
                                    ],
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Who's it for?" before making a code (optional, just for you).
class _NoteDialog extends StatefulWidget {
  const _NoteDialog();

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New gift code'),
      content: TextField(
        controller: _note,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: "Who's it for? (optional)",
          hintText: 'e.g. Sam from the gym',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => Navigator.of(context).pop(_note.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_note.text),
          child: const Text('Make code'),
        ),
      ],
    );
  }
}
