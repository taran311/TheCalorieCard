import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Sign-in with other accounts (Google, Facebook). Email and password
/// sign-in lives on the sign-in and sign-up pages.
///
/// Each needs its provider switched on in the Firebase console
/// (Authentication → Sign-in method), and the site's domain in
/// Authentication → Settings → Authorised domains. Facebook also needs a
/// Meta developer app (its App ID and secret go into Firebase).
class AuthService {
  AuthService._();

  /// "Continue with Facebook" is shown to everyone now the Meta app is
  /// published. Set to false to hide it again (it can still be tried with
  /// `?facebook=1`).
  static const facebookLive = true;

  /// For trying Facebook sign-in before it's live: open the site with
  /// `?facebook=1` on the end of the address.
  static bool _facebookTest = false;

  /// Reads `?facebook=1`. Called at start-up, before the address bar is
  /// tidied.
  static void readUrlFlags() {
    _facebookTest = Uri.base.queryParameters['facebook'] == '1';
  }

  /// Whether to show "Continue with Facebook".
  static bool get showFacebook => facebookLive || _facebookTest;

  /// Codes Firebase uses when someone closes the Google window or taps
  /// Cancel. Not an error worth showing.
  static const _cancelled = {
    'popup-closed-by-user',
    'cancelled-popup-request',
    'user-cancelled',
    'web-context-canceled',
    'web-context-cancelled',
    'canceled',
    'cancelled',
  };

  /// Signs in with Google: a pop-up on the web, the system sheet in the
  /// apps. Returns null if they cancelled, or if the browser blocked the
  /// pop-up and we've switched to a full-page redirect (the app reopens
  /// signed in). Other problems are thrown as [FirebaseAuthException] for
  /// `authProblemFor` to explain.
  ///
  /// Google accounts are already verified, so afterwards the sign-in flow
  /// goes straight to setting up the card (or to the card itself).
  static Future<UserCredential?> signInWithGoogle() {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    return _signIn(provider);
  }

  /// Signs in with Facebook, the same way as [signInWithGoogle]. Facebook
  /// accounts don't always have an email address, and Firebase doesn't
  /// mark Facebook emails as verified, so the sign-in flow trusts the
  /// account itself instead (see [isTrusted]).
  static Future<UserCredential?> signInWithFacebook() {
    final provider = FacebookAuthProvider()
      ..addScope('email')
      ..addScope('public_profile');
    return _signIn(provider);
  }

  /// Signed in with an account that's already checked (Google or
  /// Facebook), so there's no "verify your email" step.
  static bool isTrusted(User user) =>
      user.emailVerified ||
      user.providerData.any(
          (p) => p.providerId == 'google.com' || p.providerId == 'facebook.com');

  static Future<UserCredential?> _signIn(AuthProvider provider) async {
    try {
      if (kIsWeb) {
        return await FirebaseAuth.instance.signInWithPopup(provider);
      }
      return await FirebaseAuth.instance.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      if (_cancelled.contains(e.code)) return null;
      if (kIsWeb && e.code == 'popup-blocked') {
        await FirebaseAuth.instance.signInWithRedirect(provider);
        return null;
      }
      rethrow;
    }
  }
}
