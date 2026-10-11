import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/services/web_platform.dart' as web;
import 'package:namer_app/ui/auth_ui.dart';

/// A link from one of our account emails, opened in the app.
///
/// Firebase's email templates point at https://thecaloriecard.com/ (set in
/// the Firebase console: Authentication → Templates → Customise action
/// URL), and add `?mode=…&oobCode=…`. So the link lands here instead of on
/// Firebase's own page, and carries straight on into the app.
class EmailAction {
  /// verifyEmail, resetPassword, recoverEmail or verifyAndChangeEmail.
  final String mode;
  final String code;

  const EmailAction(this.mode, this.code);

  static const _modes = {
    'verifyEmail',
    'resetPassword',
    'recoverEmail',
    'verifyAndChangeEmail',
  };

  /// The action in the address the app was opened with, if any.
  static EmailAction? fromUri(Uri uri) {
    final mode = uri.queryParameters['mode'] ?? '';
    final code = uri.queryParameters['oobCode'] ?? '';
    if (code.isEmpty || !_modes.contains(mode)) return null;
    return EmailAction(mode, code);
  }

  static EmailAction? get current {
    try {
      return fromUri(Uri.base);
    } catch (_) {
      return null;
    }
  }
}

enum _Stage {
  working,
  verified,
  verifiedSignedOut,
  resetForm,
  resetSaving,
  emailRestored,
  emailChanged,
  failed,
}

class EmailActionPage extends StatefulWidget {
  final EmailAction action;
  const EmailActionPage({super.key, required this.action});

  @override
  State<EmailActionPage> createState() => _EmailActionPageState();
}

class _EmailActionPageState extends State<EmailActionPage> {
  final _auth = FirebaseAuth.instance;
  final _password = TextEditingController();

  _Stage _stage = _Stage.working;
  String _email = '';
  String? _failure;
  String? _passwordError;
  AuthNotice? _notice;
  bool _sendingReset = false;
  Timer? _autoContinue;

  String get _mode => widget.action.mode;
  String get _code => widget.action.code;

  @override
  void initState() {
    super.initState();
    // The code is single use: take it out of the address bar so a refresh
    // or a shared link doesn't try it again.
    web.clearUrlQuery();
    _run();
  }

  @override
  void dispose() {
    _autoContinue?.cancel();
    _password.dispose();
    super.dispose();
  }

  /// Waits for Firebase to restore a saved sign-in (it isn't there the
  /// moment the app opens).
  Future<User?> _restoredUser() async {
    try {
      return await _auth
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return _auth.currentUser;
    }
  }

  Future<void> _run() async {
    switch (_mode) {
      case 'verifyEmail':
        await _verifyEmail();
      case 'resetPassword':
        await _checkReset();
      case 'recoverEmail':
        await _recoverEmail();
      case 'verifyAndChangeEmail':
        await _changeEmail();
    }
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _failure = _messageFor(e);
    });
  }

  String _messageFor(Object e) {
    final code = e is FirebaseAuthException ? e.code : '';
    switch (code) {
      case 'expired-action-code':
        return _mode == 'resetPassword'
            ? 'This reset link has expired. Ask for a new one from the sign-in page.'
            : 'This link has expired.';
      case 'invalid-action-code':
        return _mode == 'resetPassword'
            ? "This reset link has already been used, or isn't valid. Ask for a new one from the sign-in page."
            : "This link has already been used, or isn't valid.";
      case 'user-disabled':
        return 'This account has been turned off. Contact support to restore it.';
      case 'user-not-found':
        return "We couldn't find that account. It may have been deleted.";
      case 'network-request-failed':
        return "You're offline or the connection dropped. Check your internet and open the link again.";
      default:
        return 'Something went wrong with this link. Open it again, or ask for a new one.';
    }
  }

  // -------------------------------------------------------------- verify

  Future<void> _verifyEmail() async {
    final user = await _restoredUser();
    try {
      await _auth.applyActionCode(_code);
    } catch (e) {
      // Used already (e.g. opened twice, or an email scanner opened it):
      // if this account is verified, that's fine.
      if (user != null) {
        try {
          await user.reload();
          if (_auth.currentUser?.emailVerified == true) {
            _showVerified(signedIn: true);
            return;
          }
        } catch (_) {}
      }
      _fail(e);
      return;
    }
    if (user != null) {
      try {
        await user.reload();
      } catch (_) {}
    }
    _showVerified(signedIn: user != null);
  }

  void _showVerified({required bool signedIn}) {
    if (!mounted) return;
    setState(() =>
        _stage = signedIn ? _Stage.verified : _Stage.verifiedSignedOut);
    if (signedIn) {
      // A moment to see the tick, then straight on.
      _autoContinue =
          Timer(const Duration(milliseconds: 1400), _continueToApp);
    }
  }

  // --------------------------------------------------------------- reset

  Future<void> _checkReset() async {
    try {
      final email = await _auth.verifyPasswordResetCode(_code);
      if (!mounted) return;
      setState(() {
        _email = email;
        _stage = _Stage.resetForm;
      });
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _saveNewPassword() async {
    if (_stage != _Stage.resetForm) return;
    final password = _password.text;
    final problem = validateNewPassword(password);
    setState(() {
      _passwordError = problem;
      _notice = null;
    });
    if (problem != null) return;
    setState(() => _stage = _Stage.resetSaving);
    try {
      await _auth.confirmPasswordReset(code: _code, newPassword: password);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'weak-password') {
        setState(() {
          _stage = _Stage.resetForm;
          _passwordError = authProblemFor(e, flow: 'signup').message;
        });
        return;
      }
      _fail(e);
      return;
    } catch (e) {
      _fail(e);
      return;
    }
    TextInput.finishAutofillContext();
    // Signed in as the same person (or no one): sign straight in with the
    // new password. Someone else signed in on this device stays as they are.
    final current = await _restoredUser();
    final same = current == null ||
        (current.email ?? '').toLowerCase() == _email.toLowerCase();
    if (same) {
      try {
        if (current != null) await _auth.signOut();
        await _auth.signInWithEmailAndPassword(
            email: _email, password: password);
      } catch (_) {
        // They can sign in themselves on the next screen.
      }
    }
    _continueToApp(
        message: same ? null : 'Password changed. Sign in with it next time.');
  }

  // ------------------------------------------------- email change / undo

  Future<void> _recoverEmail() async {
    try {
      final info = await _auth.checkActionCode(_code);
      final restored = '${info.data['email'] ?? ''}';
      await _auth.applyActionCode(_code);
      try {
        await _auth.currentUser?.reload();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _email = restored;
        _stage = _Stage.emailRestored;
      });
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _sendResetForRestored() async {
    if (_sendingReset || _email.isEmpty) return;
    setState(() => _sendingReset = true);
    try {
      await _auth.sendPasswordResetEmail(email: _email);
      if (!mounted) return;
      setState(() => _notice = AuthNotice(
            kind: AuthNoticeKind.success,
            message: 'Sent. Check $_email for a link to choose a new password.',
          ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _notice = AuthNotice(
            kind: AuthNoticeKind.error,
            message: authProblemFor(e, flow: 'reset').message,
          ));
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  Future<void> _changeEmail() async {
    try {
      await _auth.applyActionCode(_code);
      try {
        await _auth.currentUser?.reload();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _stage = _Stage.emailChanged);
    } catch (e) {
      _fail(e);
    }
  }

  // ---------------------------------------------------------------- ui

  /// On into the app: the sign-in flow picks up wherever this person is
  /// (setup, their card, or signing in).
  void _continueToApp({String? message}) {
    _autoContinue?.cancel();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.working:
        return AuthScaffold(
          title: _mode == 'resetPassword'
              ? 'Checking your link…'
              : 'One moment…',
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      case _Stage.verified:
        return AuthScaffold(
          title: 'Email verified ✓',
          subtitle: 'Thanks. Taking you to your card…',
          child: AuthButton(label: 'Continue', onPressed: _continueToApp),
        );
      case _Stage.verifiedSignedOut:
        return AuthScaffold(
          title: 'Email verified ✓',
          subtitle: 'Sign in to carry on.',
          child: AuthButton(label: 'Sign in', onPressed: _continueToApp),
        );
      case _Stage.resetForm:
      case _Stage.resetSaving:
        final saving = _stage == _Stage.resetSaving;
        return AuthScaffold(
          title: 'Choose a new password',
          subtitle: 'For $_email',
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthField(
                  controller: _password,
                  label: 'New password',
                  icon: Icons.lock_outline,
                  password: true,
                  autofocus: true,
                  enabled: !saving,
                  errorText: _passwordError,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveNewPassword(),
                ),
                const SizedBox(height: 16),
                AuthButton(
                  label: 'Save and sign in',
                  loading: saving,
                  onPressed: saving ? null : _saveNewPassword,
                ),
              ],
            ),
          ),
        );
      case _Stage.emailRestored:
        return AuthScaffold(
          title: 'Email change undone',
          subtitle: 'Your account email is back to $_email.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthNotice(
                kind: AuthNoticeKind.info,
                message: "If you didn't ask to change it, someone else may "
                    'know your password. Choose a new one to keep your '
                    'account safe.',
              ),
              const SizedBox(height: 12),
              if (_notice != null) ...[
                _notice!,
                const SizedBox(height: 12),
              ],
              AuthButton(
                label: 'Send me a password reset',
                loading: _sendingReset,
                onPressed: _sendingReset ? null : _sendResetForRestored,
              ),
              const SizedBox(height: 10),
              AuthSecondaryButton(
                  label: 'Continue', onPressed: () => _continueToApp()),
            ],
          ),
        );
      case _Stage.emailChanged:
        return AuthScaffold(
          title: 'Email updated ✓',
          subtitle: 'Use your new email to sign in from now on.',
          child: AuthButton(label: 'Continue', onPressed: _continueToApp),
        );
      case _Stage.failed:
        return AuthScaffold(
          title: "That link didn't work",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthNotice(
                kind: AuthNoticeKind.error,
                message: _failure ?? 'Something went wrong with this link.',
              ),
              const SizedBox(height: 16),
              AuthButton(
                label: _mode == 'verifyEmail'
                    ? 'Continue (we can send a new link)'
                    : 'Continue',
                onPressed: _continueToApp,
              ),
            ],
          ),
        );
    }
  }
}
