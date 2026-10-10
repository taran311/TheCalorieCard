import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/pages/forgot_password_page.dart';
import 'package:namer_app/services/auth_services.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/ui/auth_ui.dart';

/// Signing in. Where you go next (verify your email, set up your card, or
/// your card) is decided by AuthPage as the sign-in lands, so this page
/// never navigates by itself.
class LoginPage extends StatefulWidget {
  /// Switches to the sign-up form.
  final VoidCallback? onTap;

  /// Shared with the sign-up form so the email carries over. The page
  /// makes its own if none is given.
  final TextEditingController? emailController;

  const LoginPage({super.key, required this.onTap, this.emailController});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  TextEditingController? _ownEmail;
  TextEditingController get _email =>
      widget.emailController ?? (_ownEmail ??= TextEditingController());
  final _password = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  String? _emailError;
  String? _passwordError;
  AuthProblem? _problem;

  @override
  void dispose() {
    _ownEmail?.dispose();
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
      // AuthPage hears the sign-in and shows the right screen; the button
      // keeps spinning until it does.
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
      // Signed in: AuthPage takes over. Cancelled: back to the form.
      if (cred == null && mounted) setState(() => _googleLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _googleLoading = false;
        _problem = authProblemFor(e, flow: 'signin');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _googleLoading;
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
                onAction: _problem!.action == 'reset' ? _openReset : null,
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
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              errorText: _emailError,
              enabled: !busy,
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
              enabled: !busy,
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
                  onPressed: busy ? null : _openReset,
                ),
              ),
            ),
            const SizedBox(height: 18),
            AuthButton(
              label: 'Sign in',
              loading: _loading,
              onPressed: _googleLoading ? null : _signIn,
            ),
          ],
        ),
      ),
    );
  }
}
