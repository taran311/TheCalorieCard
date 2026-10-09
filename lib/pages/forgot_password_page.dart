import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/ui/auth_ui.dart';

/// Request a password-reset email, then show what to do next.
class ForgotPasswordPage extends StatefulWidget {
  /// Pre-fills the email typed on the sign-in screen.
  final String initialEmail;

  const ForgotPasswordPage({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail);

  bool _loading = false;
  bool _sent = false;
  String? _emailError;
  AuthProblem? _problem;

  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    if (_loading) return;
    final email = _email.text.trim();
    setState(() {
      _problem = null;
      _emailError = validateEmail(email);
    });
    if (_emailError != null) return;

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sent = true;
      });
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      final problem = authProblemFor(e, flow: 'reset');
      setState(() {
        _loading = false;
        if (problem.field == 'email') {
          _emailError = problem.message;
          _sent = false;
        } else {
          _problem = problem;
        }
      });
    }
  }

  void _back() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    return _sent ? _buildSent() : _buildForm();
  }

  Widget _buildForm() {
    return AuthScaffold(
      title: 'Reset your password',
      subtitle:
          "Enter the email you signed up with and we'll send you a link to choose a new password.",
      showCard: false,
      onBack: _back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_problem != null) ...[
            AuthNotice(kind: AuthNoticeKind.error, message: _problem!.message),
            const SizedBox(height: 20),
          ],
          AuthField(
            controller: _email,
            label: 'Email',
            hint: 'name@example.com',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.send,
            autofocus: widget.initialEmail.isEmpty,
            errorText: _emailError,
            enabled: !_loading,
            onChanged: (_) {
              if (_emailError != null) setState(() => _emailError = null);
            },
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 24),
          AuthButton(
            label: 'Send reset link',
            loading: _loading,
            onPressed: _send,
          ),
          const SizedBox(height: 8),
          Center(
            child: AuthLink(
              label: 'Back to sign in',
              onPressed: _loading ? null : _back,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSent() {
    final email = _email.text.trim();
    return AuthScaffold(
      title: 'Check your email',
      subtitle: 'If there\'s an account for $email, a reset link is on its way.',
      showCard: false,
      onBack: _back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_problem != null) ...[
            AuthNotice(kind: AuthNoticeKind.error, message: _problem!.message),
            const SizedBox(height: 20),
          ],
          const AuthSteps(steps: [
            'Open the email from The Calorie Card',
            'Tap the link and choose a new password',
            'Come back here and sign in with it',
          ]),
          const SizedBox(height: 8),
          const AuthNotice(
            kind: AuthNoticeKind.info,
            message:
                "Nothing after a few minutes? Check your spam or promotions folder.",
          ),
          const SizedBox(height: 24),
          AuthButton(label: 'Back to sign in', onPressed: _back),
          const SizedBox(height: 12),
          AuthSecondaryButton(
            label: _resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend email',
            onPressed: (_resendIn > 0 || _loading) ? null : _send,
          ),
          const SizedBox(height: 8),
          Center(
            child: AuthLink(
              label: 'Use a different email',
              onPressed: () => setState(() {
                _sent = false;
                _problem = null;
              }),
            ),
          ),
        ],
      ),
    );
  }
}
