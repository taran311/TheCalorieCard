import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/pages/email_verification_page.dart';
import 'package:namer_app/pages/forgot_password_page.dart';
import 'package:namer_app/pages/main_shell.dart';
import 'package:namer_app/ui/auth_ui.dart';

class LoginPage extends StatefulWidget {
  /// Switches to the sign-up form.
  final VoidCallback? onTap;

  const LoginPage({super.key, required this.onTap});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  String? _emailError;
  String? _passwordError;
  AuthProblem? _problem;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _openReset() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForgotPasswordPage(initialEmail: _email.text.trim()),
      ),
    );
  }

  Future<void> _signIn() async {
    if (_loading) return;
    final email = _email.text.trim();
    final password = _password.text; // passwords are never trimmed

    setState(() {
      _problem = null;
      _emailError = validateEmail(email);
      _passwordError = password.isEmpty ? 'Enter your password' : null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Lets browsers and password managers offer to save the login.
      TextInput.finishAutofillContext();
      if (!mounted) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.emailVerified) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmailVerificationPage(email: user.email ?? email),
          ),
        );
      } else {
        Navigator.of(context, rootNavigator: true).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 1)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final problem = authProblemFor(e, flow: 'signin');
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

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Sign in',
      subtitle: 'Pick up where you left off with today\'s balance.',
      cardholder: cardholderFromEmail(_email.text),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthDivider(text: 'New here?'),
          const SizedBox(height: 16),
          AuthSecondaryButton(
            label: 'Create your card',
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
                onAction: _problem!.action == 'reset' ? _openReset : null,
              ),
              const SizedBox(height: 20),
            ],
            AuthField(
              controller: _email,
              label: 'Email',
              hint: 'name@example.com',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              errorText: _emailError,
              enabled: !_loading,
              onChanged: (_) => setState(() {
                _emailError = null;
              }),
            ),
            const SizedBox(height: 18),
            AuthField(
              controller: _password,
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              password: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              errorText: _passwordError,
              enabled: !_loading,
              onChanged: (_) {
                if (_passwordError != null) {
                  setState(() => _passwordError = null);
                }
              },
              onSubmitted: (_) => _signIn(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: AuthLink(
                  label: 'Forgot password?',
                  onPressed: _loading ? null : _openReset,
                ),
              ),
            ),
            const SizedBox(height: 18),
            AuthButton(
              label: 'Sign in',
              loading: _loading,
              onPressed: _signIn,
            ),
          ],
        ),
      ),
    );
  }
}
