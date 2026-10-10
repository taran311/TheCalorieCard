import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Sign-in with other accounts (Google). Email and password sign-in lives
/// on the sign-in and sign-up pages.
///
/// Needs the Google provider switched on in the Firebase console
/// (Authentication → Sign-in method → Google), and the site's domain in
/// Authentication → Settings → Authorised domains.
class AuthService {
  AuthService._();

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
  static Future<UserCredential?> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
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
