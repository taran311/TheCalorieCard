import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/pages/email_verification_page.dart';
import 'package:namer_app/services/auth_services.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/ui/auth_ui.dart';

/// Creating an account. Like sign-in, it doesn't navigate: AuthPage sees
/// the new account and shows "Verify your email" (or, for Google, goes
/// straight to setting up the card).
class RegisterPage extends StatefulWidget {
  /// Switches back to the sign-in form.
  final VoidCallback? onTap;

  /// Shared with the sign-in form so the email carries over. The page
  /// makes its own if none is given.
  final TextEditingController? emailController;

  const RegisterPage({super.key, required this.onTap, this.emailController});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  TextEditingController? _ownEmail;
  TextEditingController get _email =>
      widget.emailController ?? (_ownEmail ??= TextEditingController());
  // One password box: the eye button lets people check what they typed,
  // which catches typos better than typing it twice.
  final _password = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  bool _submitted = false;
  String? _emailError;
  String? _passwordError;
  AuthProblem? _problem;

  @override
  void dispose() {
    _ownEmail?.dispose();
    _password.dispose();
    super.dispose();
  }

  void _validate() {
    final email = _email.text.trim();
    _emailError = validateEmail(email);
    _passwordError = validateNewPassword(_password.text);
  }

  Future<void> _signUp() async {
    if (_loading) return;
    setState(() {
      _submitted = true;
      _problem = null;
      _validate();
    });
    if (_emailError != null || _passwordError != null) {
      return;
    }

    setState(() => _loading = true);
    final email = _email.text.trim();
    final categories = Provider.of<CategoryService>(context, listen: false);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        // Never trim passwords: sign-in uses exactly what was typed.
        password: _password.text,
      );
      TextInput.finishAutofillContext();
      categories.resetToDefault();
      // AuthPage is already swapping to "Verify your email" (which doesn't
      // send one itself when it opens this way), so send the link here.
      EmailVerificationPage.markSent();
      try {
        await cred.user?.sendEmailVerification();
      } catch (_) {
        // They can tap Resend on the next page.
      }
    } catch (e) {
      if (!mounted) return;
      final problem = authProblemFor(e, flow: 'signup');
      setState(() {
        _loading = false;
        if (problem.field == 'email') {
          _emailError = problem.message;
        } else if (problem.field == 'password') {
          _passwordError = problem.message;
        } else {
          _problem = problem;
        }
      });
    }
  }

  /// Re-check as people type, but only after a first submit attempt, so
  /// we don't shout at someone who has barely started.
  void _revalidate() {
    if (!_submitted) {
      setState(() {});
      return;
    }
    setState(_validate);
  }

  Future<void> _google() async {
    if (_loading || _googleLoading) return;
    final categories = Provider.of<CategoryService>(context, listen: false);
    setState(() {
      _googleLoading = true;
      _problem = null;
    });
    try {
      final cred = await AuthService.signInWithGoogle();
      if (cred?.additionalUserInfo?.isNewUser == true) {
        categories.resetToDefault();
      }
      // Signed in: AuthPage takes over (Google emails are already
      // verified, so it's straight to setting up the card).
      if (cred == null && mounted) setState(() => _googleLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _googleLoading = false;
        _problem = authProblemFor(e, flow: 'signup');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final length = _password.text.length;
    final busy = _loading || _googleLoading;

    return AuthScaffold(
      title: 'Create your card',
      subtitle:
          'Set up an account, then we\'ll work out your daily calorie budget.',
      cardholder: cardholderFromEmail(_email.text),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthDivider(text: 'Already have an account?'),
          const SizedBox(height: 16),
          AuthSecondaryButton(
            label: 'Sign in',
            onPressed: busy ? null : widget.onTap,
          ),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_problem != null) ...[
              AuthNotice(
                kind: AuthNoticeKind.error,
                message: _problem!.message,
                actionLabel: _problem!.actionLabel,
                onAction: _problem!.action == 'signin' ? widget.onTap : null,
              ),
              const SizedBox(height: 20),
            ],
            GoogleButton(
              loading: _googleLoading,
              onPressed: busy ? null : _google,
            ),
            const SizedBox(height: 20),
            const AuthDivider(text: 'or'),
            const SizedBox(height: 20),
            AuthField(
              controller: _email,
              label: 'Email',
              hint: 'name@example.com',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              errorText: _emailError,
              enabled: !busy,
              onChanged: (_) => _revalidate(),
            ),
            const SizedBox(height: 18),
            AuthField(
              controller: _password,
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              password: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              errorText: _passwordError,
              enabled: !busy,
              onChanged: (_) => _revalidate(),
              onSubmitted: (_) => _signUp(),
            ),
            if (_passwordError == null) ...[
              const SizedBox(height: 8),
              _PasswordHint(length: length),
            ],
            const SizedBox(height: 24),
            AuthButton(
              label: 'Create my card',
              loading: _loading,
              onPressed: _googleLoading ? null : _signUp,
            ),
            const SizedBox(height: 8),
            const LegalAgreement(),
          ],
        ),
      ),
    );
  }
}

/// Live, quiet guidance under the password field.
class _PasswordHint extends StatelessWidget {
  final int length;

  const _PasswordHint({required this.length});

  @override
  Widget build(BuildContext context) {
    final ok = length >= minPasswordLength;
    final strong = length >= 10;
    final color = !ok
        ? AuthColors.muted
        : (strong ? AuthColors.successText : AuthColors.infoText);
    final text = !ok
        ? 'At least $minPasswordLength characters'
        : (strong ? 'Nice and strong' : 'Good. Longer is even better.');

    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }
}
