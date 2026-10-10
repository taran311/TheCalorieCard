import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/data_export.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/services/weight_service.dart';
import 'package:namer_app/services/web_platform.dart' as web;
import 'package:namer_app/ui/auth_ui.dart' show openSitePage;
import 'package:namer_app/ui/responsive.dart';
import 'package:url_launcher/url_launcher.dart';

/// Account and privacy: your display name, password, a copy of your data,
/// deleting your account, and the legal pages.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  /// Where help requests go.
  static const supportEmail = 'support@thecaloriecard.com';

  /// Set at build time with --dart-define=APP_VERSION=1.2.0.
  static const appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '0.0.1');

  /// Longest display name we keep (it has to fit on cards and lists).
  static const maxNameLength = 40;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final User? _user = FirebaseAuth.instance.currentUser;
  final _name = TextEditingController();
  String _savedName = '';
  bool _loadingName = true;
  bool _savingName = false;
  bool _sendingReset = false;
  bool _exporting = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onNameChanged);
    _loadName();
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasPassword =>
      _user?.providerData.any((p) => p.providerId == 'password') ?? false;

  Future<void> _loadName() async {
    final uid = _user?.uid;
    if (uid == null) return;
    try {
      final doc = await BalanceService.db.collection('users').doc(uid).get();
      final name = '${doc.data()?['display_name'] ?? ''}'.trim();
      if (!mounted) return;
      setState(() {
        _savedName = name;
        _name.text = name;
      });
    } catch (_) {
      // Left blank; they can still type one.
    } finally {
      if (mounted) setState(() => _loadingName = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveName() async {
    final uid = _user?.uid;
    if (uid == null || _savingName) return;
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    FocusScope.of(context).unfocus();
    setState(() => _savingName = true);
    try {
      // Friends see this instead of the start of your email.
      await BalanceService.db.collection('users').doc(uid).set({
        'display_name': name.isEmpty ? FieldValue.delete() : name,
      }, SetOptions(merge: true));
      try {
        await _user?.updateDisplayName(name.isEmpty ? null : name);
      } catch (_) {
        // The Firestore name is the one the app uses.
      }
      if (!mounted) return;
      setState(() {
        _savedName = name;
        _name.text = name;
      });
      _snack(name.isEmpty
          ? 'Name removed. Friends will see your email name.'
          : 'Saved. Friends will see you as $name.');
    } catch (_) {
      if (mounted) _snack("Couldn't save your name. Please try again.");
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _user?.email;
    if (email == null || email.isEmpty || _sendingReset) return;
    setState(() => _sendingReset = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Check your email'),
          content: Text(
              "We've sent a link to $email. Open it to choose a new "
              "password. If it isn't there in a few minutes, check your "
              'spam folder.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final code = e is FirebaseAuthException ? e.code : '';
      _snack(code == 'too-many-requests'
          ? "We've sent a few already. Wait a few minutes and try again."
          : "The email didn't send. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  /// Builds the CSV and saves it through the browser. Where downloads
  /// aren't possible, copies it instead.
  Future<void> _downloadData() async {
    final uid = _user?.uid;
    if (uid == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final foods = await BalanceService.db
          .collection('user_food')
          .where('user_id', isEqualTo: uid)
          .get();
      final weighIns = await WeightService.history(uid);
      final csv = DataExport.csv(
        foods: [for (final d in foods.docs) d.data()],
        weighIns: weighIns,
      );
      final name =
          'calorie-card-${BalanceService.dateKey(BalanceService.now())}.csv';
      // The byte-order mark makes Excel read £ and accents correctly.
      final saved = web.downloadTextFile(name, '\uFEFF$csv');
      if (!saved) {
        await Clipboard.setData(ClipboardData(text: csv));
      }
      if (!mounted) return;
      _snack(saved
          ? 'Downloaded $name.'
          : 'Copied your data. Paste it into a spreadsheet or a note.');
    } catch (_) {
      if (mounted) {
        _snack("Couldn't get your data. Check your connection and try again.");
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    String? error;
    try {
      final r = await ProxyClient.post('/account/delete', const {'confirm': 'DELETE'})
          .timeout(const Duration(seconds: 60));
      Map? body;
      try {
        final j = json.decode(r.body);
        if (j is Map) body = j;
      } catch (_) {}
      if (r.statusCode != 200 || body?['ok'] != true) {
        final message = body?['error'];
        error = message is String && message.isNotEmpty
            ? message
            : "Your account wasn't deleted. Please try again, or contact "
                'support.';
      }
    } catch (_) {
      error = "Couldn't reach the server. Check your connection and try "
          'again.';
    }

    if (!mounted) return;
    if (error != null) {
      setState(() => _deleting = false);
      _snack(error);
      return;
    }

    // Gone on the server: sign out here and start again from the
    // beginning.
    Premium.stop();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
    messenger.showSnackBar(const SnackBar(
        content: Text('Your account and data have been deleted.')));
  }

  Future<void> _contactSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AccountPage.supportEmail,
      query: 'subject=${Uri.encodeComponent('The Calorie Card: help')}',
    );
    var ok = false;
    try {
      ok = await launchUrl(uri);
    } catch (_) {}
    if (!ok && mounted) {
      await Clipboard.setData(
          const ClipboardData(text: AccountPage.supportEmail));
      if (mounted) {
        _snack('Copied ${AccountPage.supportEmail}. Email us any time.');
      }
    }
  }

  Future<void> _openLegal(String path) async {
    final ok = await openSitePage(path);
    if (!ok && mounted) _snack("Couldn't open that page.");
  }

  // ---------------------------------------------------------------------------

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        Container(
          decoration: AppDecor.card,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _body(String text) => Text(
        text,
        style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.gray700),
      );

  Widget _spinner({Color color = Colors.white}) => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );

  Widget _linkRow(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppText.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.gray400),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _user?.email ?? '';
    final nameChanged = _name.text.trim() != _savedName;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Account and privacy')),
      body: AbsorbPointer(
        absorbing: _deleting,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: Breakpoints.contentMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _section('Your name', [
                    _body('Friends see this name instead of the start of '
                        'your email address.'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      enabled: !_loadingName && !_savingName,
                      maxLength: AccountPage.maxNameLength,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (nameChanged) _saveName();
                      },
                      decoration: InputDecoration(
                        labelText: 'Display name',
                        hintText: _loadingName ? 'Loading…' : 'E.g. Sam J',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed:
                            nameChanged && !_savingName ? _saveName : null,
                        child: _savingName
                            ? _spinner()
                            : const Text('Save name'),
                      ),
                    ),
                  ]),
                  _section('Password', [
                    if (_hasPassword) ...[
                      _body("We'll email a secure link to $email so you can "
                          'choose a new password.'),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed:
                              _sendingReset ? null : _sendPasswordReset,
                          icon: _sendingReset
                              ? _spinner(color: AppText.primary)
                              : const Icon(Icons.lock_reset_rounded),
                          label: const Text('Email me a reset link'),
                        ),
                      ),
                    ] else
                      _body('You sign in with Google, so there is no '
                          'password to change here. Manage it in your '
                          'Google account.'),
                  ]),
                  _section('Your data', [
                    _body('Download everything you have logged (food, '
                        'calories, macros and weigh-ins) as a spreadsheet '
                        'file.'),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _exporting ? null : _downloadData,
                        icon: _exporting
                            ? _spinner(color: AppText.primary)
                            : const Icon(Icons.download_rounded),
                        label: const Text('Download my data'),
                      ),
                    ),
                  ]),
                  _section('Delete account', [
                    _body('Permanently deletes your card, food log, '
                        'recipes, weigh-ins, streaks, friends and messages, '
                        'and cancels any Premium subscription. This '
                        "can't be undone."),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _deleting ? null : _deleteAccount,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppText.red600,
                          side: BorderSide(color: AppText.red600),
                        ),
                        icon: _deleting
                            ? _spinner(color: AppText.red600)
                            : const Icon(Icons.delete_forever_outlined),
                        label: Text(
                            _deleting ? 'Deleting…' : 'Delete my account'),
                      ),
                    ),
                  ]),
                  _section('About', [
                    _linkRow(Icons.privacy_tip_outlined, 'Privacy policy',
                        () => _openLegal('/privacy.html')),
                    _linkRow(Icons.description_outlined, 'Terms of use',
                        () => _openLegal('/terms.html')),
                    _linkRow(Icons.mail_outline_rounded, 'Contact support',
                        _contactSupport),
                    const SizedBox(height: 8),
                    Text(
                      'The Calorie Card · version ${AccountPage.appVersion}\n'
                      'The Calorie Card is a trading name of Hayer Software '
                      'Limited, registered in England and Wales '
                      '(company no. 14026484).',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.muted,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Type DELETE to confirm". Owns its text box so it's tidied up.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog();

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _ok => _confirm.text.trim() == 'DELETE';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This deletes your card, everything you have logged, your '
              'recipes, weigh-ins, streaks and friends, and cancels any '
              "Premium subscription. It can't be undone.\n\n"
              'Want a copy first? Use "Download my data".',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirm,
              autofocus: true,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_ok) Navigator.pop(context, true);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _ok ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red600,
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete for good'),
        ),
      ],
    );
  }
}
