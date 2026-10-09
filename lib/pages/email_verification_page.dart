import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/pages/get_started_page.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/ui/auth_ui.dart';

/// Waits for the user to click the link in their verification email.
/// Checks automatically every few seconds and moves on by itself.
class EmailVerificationPage extends StatefulWidget {
  final String email;

  const EmailVerificationPage({super.key, required this.email});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  Timer? _pollTimer;
  Timer? _resendTimer;
  int _resendIn = 0;
  bool _checking = false;
  bool _leaving = false;
  AuthNotice? _notice;

  @override
  void initState() {
    super.initState();
    _sendEmail(initial: true);
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _check(quiet: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 60);
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => GetStartedPage()),
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
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AuthColors.action,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
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
