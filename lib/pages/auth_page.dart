import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/pages/email_verification_page.dart';
import 'package:namer_app/pages/get_started_page.dart';
import 'package:namer_app/pages/main_shell.dart';
import 'package:namer_app/pages/login_or_register_page.dart';
import 'package:namer_app/ui/auth_ui.dart';
import 'package:namer_app/ui/responsive.dart';

/// Decides the first screen from the sign-in state, and is the only place
/// that does: signed out → sign in / create; email not verified → verify;
/// no card yet → Get started; otherwise the app. The sign-in and sign-up
/// pages just sign in and let this page move on.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  /// Created once, so rebuilds don't resubscribe (and flash the splash).
  final Stream<User?> _authState = FirebaseAuth.instance.authStateChanges();

  /// The profile check for [_checkedUid], kept so rebuilds don't run the
  /// query again.
  Future<bool>? _userExists;
  String? _checkedUid;

  /// Whether this user already has a profile. Errors are passed on (not
  /// treated as "no profile"), so an offline returning user is never sent
  /// through onboarding, which would overwrite their card.
  Future<bool> checkIfUserExists(String userId) async {
    final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
        .collection('user_data')
        .where('user_id', isEqualTo: userId)
        .limit(1)
        .get();
    return querySnapshot.docs.isNotEmpty;
  }

  Future<bool> _userExistsFor(String uid) {
    if (_userExists == null || _checkedUid != uid) {
      _checkedUid = uid;
      _userExists = checkIfUserExists(uid);
    }
    return _userExists!;
  }

  void _retry() {
    final uid = _checkedUid;
    if (uid == null) return;
    setState(() {
      _userExists = checkIfUserExists(uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: _authState,
        builder: (context, snapshot) {
          // Firebase is still restoring the session: show the brand, not a
          // sign-in form that would flash past for signed-in people.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AuthSplash();
          }
          final user = snapshot.data;
          if (user == null) {
            return const LoginOrRegisterPage();
          }
          // Next time this device opens on "Sign in", not "Create".
          LoginOrRegisterPage.rememberSignedIn();

          // currentUser is refreshed by reload(), so prefer it: the stream
          // may still hold the copy from before the email was verified.
          final fresh = FirebaseAuth.instance.currentUser;
          final verified = fresh != null && fresh.uid == user.uid
              ? fresh.emailVerified
              : user.emailVerified;
          if (!verified) {
            return EmailVerificationPage(
              email: user.email ?? '',
              sendOnOpen: false,
            );
          }

          return FutureBuilder<bool>(
            future: _userExistsFor(user.uid),
            builder: (context, AsyncSnapshot<bool> userExistsSnapshot) {
              if (userExistsSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const AuthSplash();
              }

              if (userExistsSnapshot.hasError) {
                return _RetryView(onRetry: _retry);
              }

              if (userExistsSnapshot.data == true) {
                return const MainShell(initialIndex: 1);
              }
              return GetStartedPage();
            },
          );
        },
      ),
    );
  }
}

/// Shown when we can't tell whether the user already has a card.
class _RetryView extends StatelessWidget {
  final VoidCallback onRetry;

  const _RetryView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.canvas,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: AppDecor.card,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 40,
                      color: AppText.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "We couldn't reach your card. Check your connection.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
