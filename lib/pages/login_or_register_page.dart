import 'package:flutter/material.dart';
import 'package:namer_app/pages/login_page.dart';
import 'package:namer_app/pages/register_page.dart';
import 'package:namer_app/ui/auth_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sign-in and sign-up share this spot; the switch fades between them.
///
/// A device that has never been signed in opens on "Create your card"
/// (most people arriving there are new); one that has opens on sign-in.
/// The email typed on one form carries over to the other.
class LoginOrRegisterPage extends StatefulWidget {
  const LoginOrRegisterPage({super.key});

  /// Saved once anyone signs in on this device.
  static const signedInBeforeKey = 'has_signed_in_before';

  /// Remembers that this device has been signed in. Safe to call often.
  static Future<void> rememberSignedIn() async {
    if (_remembered) return;
    _remembered = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(signedInBeforeKey, true);
    } catch (_) {
      _remembered = false;
    }
  }

  static bool _remembered = false;

  @override
  State<LoginOrRegisterPage> createState() => _LoginOrRegisterPageState();
}

class _LoginOrRegisterPageState extends State<LoginOrRegisterPage> {
  /// Null until we know whether this device has signed in before.
  bool? showLoginPage;

  /// One email box shared by both forms, so switching keeps what's typed.
  final _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pickFirstPage();
  }

  Future<void> _pickFirstPage() async {
    var signedInBefore = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      signedInBefore = prefs.getBool(LoginOrRegisterPage.signedInBeforeKey) ??
          false;
    } catch (_) {
      // Private browsing or storage blocked: treat as a new device.
    }
    if (mounted) setState(() => showLoginPage ??= signedInBefore);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void togglePages() {
    setState(() {
      showLoginPage = !(showLoginPage ?? true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final login = showLoginPage;
    return AnimatedSwitcher(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 220),
      child: login == null
          ? const AuthSplash(key: ValueKey('splash'))
          : login
              ? LoginPage(
                  key: const ValueKey('signin'),
                  onTap: togglePages,
                  emailController: _email,
                )
              : RegisterPage(
                  key: const ValueKey('signup'),
                  onTap: togglePages,
                  emailController: _email,
                ),
    );
  }
}
