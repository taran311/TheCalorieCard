import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/ui/auth_ui.dart';

/// Waits for the user to click the link in their verification email.
/// Checks automatically (every 3 seconds for the first minute, then every
/// 10) and straight away when they come back to the app, then moves on by
/// itself.
class EmailVerificationPage extends StatefulWidget {
  final String email;

  /// Send a fresh link as the page opens. Off when the app reopens on this
  /// page (they already have one; Resend is there if not).
  final bool sendOnOpen;

  const EmailVerificationPage({
    super.key,
    required this.email,
    this.sendOnOpen = true,
  });

  /// Records that a verification email has just gone out (sign-up sends
  /// one itself), so this page doesn't send another and Resend waits a
  /// minute.
  static void markSent() {
    _EmailVerificationPageState._lastAutoSend = DateTime.now();
    _EmailVerificationPageState._sentSignal.value++;
  }

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  /// When the last automatic email went out, so two copies of this page
  /// (e.g. during a route change) don't both send one.
  static DateTime? _lastAutoSend;

  /// Bumped by [EmailVerificationPage.markSent].
  static final ValueNotifier<int> _sentSignal = ValueNotifier<int>(0);

  Timer? _pollTimer;
  Timer? _resendTimer;
  int _resendIn = 0;
  bool _checking = false;
  bool _leaving = false;
  AuthNotice? _notice;
  late final DateTime _openedAt = DateTime.now();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final last = _lastAutoSend;
    final recent = last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 60);
    if (widget.sendOnOpen && !recent) {
      _lastAutoSend = DateTime.now();
      _sendEmail(initial: true);
    } else if (recent) {
      // One went out moments ago: Resend waits out the rest of the minute.
      _startResendCooldown(
          seconds: 60 - DateTime.now().difference(last!).inSeconds);
    }
    _sentSignal.addListener(_onSentElsewhere);
    // Back from the email app or another tab: check straight away.
    _lifecycle = AppLifecycleListener(onResume: () => _check(quiet: true));
    _scheduleCheck();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _resendTimer?.cancel();
    _sentSignal.removeListener(_onSentElsewhere);
    _lifecycle.dispose();
    super.dispose();
  }

  void _onSentElsewhere() {
    if (mounted) _startResendCooldown();
  }

  /// Every 3 seconds for the first minute, then every 10: quick while
  /// they're likely clicking the link, gentler on the server after.
  void _scheduleCheck() {
    _pollTimer?.cancel();
    if (_leaving) return;
    final early = DateTime.now().difference(_openedAt) <
        const Duration(minutes: 1);
    _pollTimer = Timer(Duration(seconds: early ? 3 : 10), () async {
      await _check(quiet: true);
      if (mounted) _scheduleCheck();
    });
  }

  void _startResendCooldown({int seconds = 60}) {
    _resendTimer?.cancel();
    if (seconds <= 0) return;
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _sendEmail({bool initial = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.emailVerified) return;
    try {
      await user.sendEmailVerification();
      if (!mounted) return;
      _startResendCooldown();
      if (!initial) {
        setState(() => _notice = const AuthNotice(
              kind: AuthNoticeKind.success,
              message: 'Sent. Check your inbox for a new link.',
            ));
      }
    } catch (e) {
      if (!mounted) return;
      final code = e is FirebaseAuthException ? e.code : '';
      setState(() => _notice = AuthNotice(
            kind: AuthNoticeKind.error,
            message: code == 'too-many-requests'
                ? "We've sent several emails already. Wait a few minutes before asking for another."
                : "The email didn't send. Check your connection and tap Resend.",
          ));
    }
  }

  /// [quiet] checks run in the background; a manual check reports back.
  Future<void> _check({bool quiet = false}) async {
    if (_checking || _leaving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!quiet) setState(() => _checking = true);
    try {
      await user.reload();
      final verified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      if (!mounted) return;
      if (verified) {
        _leaving = true;
        _pollTimer?.cancel();
        Provider.of<CategoryService>(context, listen: false).resetToDefault();
        // Back through AuthPage: it checks for an existing card, so a
        // returning user isn't sent through setup (which would overwrite
        // their card). New users carry on to setup from there.
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthPage()),
          (route) => false,
        );
        return;
      }
      if (!quiet) {
        setState(() => _notice = const AuthNotice(
              kind: AuthNoticeKind.info,
              message:
                  "Not verified yet. Open the link in the email, then come back here.",
            ));
      }
    } catch (_) {
      if (!quiet && mounted) {
        setState(() => _notice = const AuthNotice(
              kind: AuthNoticeKind.error,
              message: "Couldn't check right now. Check your connection.",
            ));
      }
    } finally {
      if (!quiet && mounted && !_leaving) setState(() => _checking = false);
    }
  }

  Future<void> _useDifferentEmail() async {
    _pollTimer?.cancel();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    // This page replaced the app's first screen, so there's nothing to pop
    // back to. Restart from the sign-in flow instead.
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Verify your email',
      subtitle: 'We sent a link to ${widget.email}. '
          'Open it and this page will carry on by itself.',
      cardholder: cardholderFromEmail(widget.email),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_notice != null) ...[
            _notice!,
            const SizedBox(height: 20),
          ],
          const AuthSteps(steps: [
            'Open the email from The Calorie Card',
            'Tap the verification link',
            'Come back here. We\'ll set up your card next.',
          ]),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AuthColors.action,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Waiting for you to verify…',
                  style: TextStyle(color: AuthColors.muted, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AuthButton(
            label: "I've verified my email",
            loading: _checking,
            onPressed: () => _check(),
          ),
          const SizedBox(height: 12),
          AuthSecondaryButton(
            label: _resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend email',
            onPressed: _resendIn > 0 ? null : () => _sendEmail(),
          ),
          const SizedBox(height: 8),
          Center(
            child: AuthLink(
              label: 'Use a different email',
              onPressed: _useDifferentEmail,
            ),
          ),
        ],
      ),
    );
  }
}
