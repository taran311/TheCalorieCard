import 'package:shared_preferences/shared_preferences.dart';

/// Whether this device was signed in last time the app was open.
///
/// After a refresh on the web, Firebase can briefly report "signed out"
/// before it has restored the saved session, which flashed the sign-in
/// page and then jumped to the app. With this hint the first screen waits
/// a moment for the session instead. People who really are signed out
/// (the hint is off) see the sign-in page straight away.
class SessionHint {
  SessionHint._();

  static const _key = 'session_was_signed_in';

  static bool _wasSignedIn = false;

  /// Read once at start-up (see main.dart).
  static bool get wasSignedIn => _wasSignedIn;

  /// How long to wait for a saved session before showing sign-in.
  static const grace = Duration(seconds: 4);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _wasSignedIn = prefs.getBool(_key) ?? false;
    } catch (_) {
      _wasSignedIn = false;
    }
  }

  /// Remembers whether someone is signed in on this device now.
  static Future<void> set(bool signedIn) async {
    if (_wasSignedIn == signedIn) return;
    _wasSignedIn = signedIn;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, signedIn);
    } catch (_) {}
  }
}
