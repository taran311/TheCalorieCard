import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/pages/email_verification_page.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/ui/auth_ui.dart';

class RegisterPage extends StatefulWidget {
  /// Switches back to the sign-in form.
  final VoidCallback? onTap;

  const RegisterPage({super.key, required this.onTap});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _loading = false;
  bool _submitted = false;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  AuthProblem? _problem;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _validate() {
    final email = _email.text.trim();
    _emailError = validateEmail(email);
    _passwordError = validateNewPassword(_password.text);
    _confirmError = _confirm.text.isEmpty
        ? 'Type your password again'
        : (_confirm.text != _password.text ? "Passwords don't match" : null);
  }

  Future<void> _signUp() async {
    if (_loading) return;
    setState(() {
      _submitted = true;
      _problem = null;
      _validate();
    });
    if (_emailError != null || _passwordError != null || _confirmError != null) {
      return;
    }

    setState(() => _loading = true);
    final email = _email.text.trim();
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        // Never trim passwords: sign-in uses exactly what was typed.
        password: _password.text,
      );
      TextInput.finishAutofillContext();
      if (!mounted) return;

      Provider.of<CategoryService>(context, listen: false).resetToDefault();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EmailVerificationPage(email: email),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final length = _password.text.length;

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
            onPressed: _loading ? null : widget.onTap,
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
            AuthField(
              controller: _email,
              label: 'Email',
              hint: 'name@example.com',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              errorText: _emailError,
              enabled: !_loading,
              onChanged: (_) => _revalidate(),
            ),
            const SizedBox(height: 18),
            AuthField(
              controller: _password,
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              password: true,
              autofillHints: const [AutofillHints.newPassword],
              errorText: _passwordError,
              enabled: !_loading,
              onChanged: (_) => _revalidate(),
            ),
            if (_passwordError == null) ...[
              const SizedBox(height: 8),
              _PasswordHint(length: length),
            ],
            const SizedBox(height: 18),
            AuthField(
              controller: _confirm,
              label: 'Confirm password',
              icon: Icons.lock_outline_rounded,
              password: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              errorText: _confirmError,
              enabled: !_loading,
              onChanged: (_) => _revalidate(),
              onSubmitted: (_) => _signUp(),
            ),
            const SizedBox(height: 24),
            AuthButton(
              label: 'Create account',
              loading: _loading,
              onPressed: _signUp,
            ),
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
        : (strong ? 'Strong length' : 'Good. Longer is stronger.');

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
