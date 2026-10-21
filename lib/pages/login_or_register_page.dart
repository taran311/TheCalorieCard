import 'package:flutter/material.dart';
import 'package:namer_app/pages/intro_page.dart';
import 'package:namer_app/pages/login_page.dart';
import 'package:namer_app/pages/register_page.dart';
import 'package:namer_app/ui/auth_ui.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sign-in and sign-up share this spot; the switch fades between them.
///
/// A device that has never been signed in first shows the intro (what the
/// app is), then "Create your card"; one that has opens on sign-in.
/// The email typed on one form carries over to the other.
class LoginOrRegisterPage extends StatefulWidget {
  const LoginOrRegisterPage({super.key});

  /// Saved once anyone signs in on this device.
  static const signedInBeforeKey = 'has_signed_in_before';

  /// Saved once the intro has been seen on this device.
  static const introSeenKey = 'intro_seen';

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

  /// The intro shows first on a device that's new to the app.
  bool _showIntro = false;

  /// One email box shared by both forms, so switching keeps what's typed.
  final _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pickFirstPage();
  }

  Future<void> _pickFirstPage() async {
    var signedInBefore = false;
    var introSeen = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      signedInBefore = prefs.getBool(LoginOrRegisterPage.signedInBeforeKey) ??
          false;
      introSeen = prefs.getBool(LoginOrRegisterPage.introSeenKey) ?? false;
    } catch (_) {
      // Private browsing or storage blocked: treat as a new device.
    }
    if (mounted) {
      setState(() {
        showLoginPage ??= signedInBefore;
        _showIntro = !signedInBefore && !introSeen;
      });
    }
  }

  /// Leaves the intro for sign-up ([login] false) or sign-in.
  void _leaveIntro({required bool login}) {
    setState(() {
      _showIntro = false;
      showLoginPage = login;
    });
    SharedPreferences.getInstance()
        .then((p) => p.setBool(LoginOrRegisterPage.introSeenKey, true))
        .catchError((_) => false);
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

  /// On a wide window the brand panel beside the form already says what
  /// the app is, so the intro slides would repeat it. Measured on the whole
  /// window: this page itself sits in a phone-width panel there.
  bool _brandPanelShowing(BuildContext context) {
    final window = MediaQueryData.fromView(View.of(context)).size;
    return window.width >= Breakpoints.desktop;
  }

  @override
  Widget build(BuildContext context) {
    final login = showLoginPage;
    final intro = _showIntro && !_brandPanelShowing(context);
    return AnimatedSwitcher(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 220),
      child: login == null
          ? const AuthSplash(key: ValueKey('splash'))
          : intro
              ? IntroPage(
                  key: const ValueKey('intro'),
                  onCreate: () => _leaveIntro(login: false),
                  onSignIn: () => _leaveIntro(login: true),
                )
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
