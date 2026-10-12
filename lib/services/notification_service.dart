import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:namer_app/services/web_platform.dart' as web;

/// The evening "you haven't logged today" reminder, and Guess the
/// Calories "your turn" alerts.
///
/// The app only asks for permission and saves this device's push token
/// (plus your reminder time and time zone) on `users/{uid}`. The server
/// checks once the hour comes round and sends a friendly nudge if nothing
/// has been logged today. Saved fields: `reminder_enabled`,
/// `reminder_hour`, `tz_offset_minutes`, `fcm_tokens`, `reminder_prompted`,
/// `game_notifications` (game alerts are on unless this is false, as long
/// as there's a token to send to) and `chat_notifications` (the same, for
/// new messages from friends).
class NotificationService {
  NotificationService._();

  /// Firebase console → Project settings → Cloud Messaging → Web Push
  /// certificates → "Generate key pair", then paste the key here. Until
  /// it's set, reminders are hidden on the web.
  static const vapidKey =
      'BGBE2g8WQKWwvtvY59ZixD0aJBR7xvVo9Ta3jw1_LlAwleVp4Sbg2W24rDJm5AVWxPQL5L1Q4xGn19mCOXHI_Do';

  static const defaultHour = 20;

  /// Times people can pick.
  static const hours = [18, 19, 20, 21, 22];

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Whether reminders can work on this device.
  static bool get supported {
    if (kIsWeb) return vapidKey.isNotEmpty;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// On an iPhone or iPad, web notifications only work once the app has
  /// been added to the Home Screen (and opened from there). In Safari
  /// itself the permission request is refused, which would otherwise look
  /// like the person had blocked notifications.
  static bool get needsHomeScreen => kIsWeb && web.iosNeedsHomeScreen;

  static const homeScreenMessage =
      'Add The Calorie Card to your Home Screen first: tap Share, then '
      '"Add to Home Screen". Open it from there and turn the reminder on.';

  /// [homeScreenMessage] for game alerts.
  static const homeScreenGamesMessage =
      'Add The Calorie Card to your Home Screen first: tap Share, then '
      '"Add to Home Screen". Open it from there and turn notifications on.';

  static String hourLabel(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h${hour < 12 ? 'am' : 'pm'}';
  }

  /// [gameAlerts]: Guess the Calories turn alerts are on, which needs a
  /// saved token (so it's false until notifications were allowed once).
  static Future<
      ({
        bool enabled,
        int hour,
        bool prompted,
        bool gameAlerts,
        bool chatAlerts,
      })> load() async {
    final uid = _uid;
    if (uid == null) {
      return (
        enabled: false,
        hour: defaultHour,
        prompted: false,
        gameAlerts: false,
        chatAlerts: false,
      );
    }
    final data = (await _db.collection('users').doc(uid).get()).data();
    final hour = data?['reminder_hour'];
    final tokens = data?['fcm_tokens'];
    return (
      enabled: data?['reminder_enabled'] == true,
      hour: hour is int && hour >= 0 && hour < 24 ? hour : defaultHour,
      prompted: data?['reminder_prompted'] == true,
      gameAlerts: data?['game_notifications'] != false &&
          tokens is List &&
          tokens.isNotEmpty,
      chatAlerts: data?['chat_notifications'] != false &&
          tokens is List &&
          tokens.isNotEmpty,
    );
  }

  /// Asks for permission and gets this device's push token. Returns the
  /// token, or a message to show when it couldn't (for [what], e.g. "the
  /// reminder").
  static Future<({String? token, String? error})> _permissionAndToken(
      String what) async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    final status = settings.authorizationStatus;
    if (status == AuthorizationStatus.denied) {
      return (
        token: null,
        error: 'Notifications are blocked. Allow them for The Calorie Card '
            'in your browser or phone settings, then try again.',
      );
    }
    if (status == AuthorizationStatus.notDetermined) {
      return (token: null, error: 'Allow notifications to get $what.');
    }
    final token = await messaging.getToken(
      vapidKey: kIsWeb ? vapidKey : null,
    );
    if (token == null || token.isEmpty) {
      return (
        token: null,
        error: "Couldn't set up notifications on this device.",
      );
    }
    return (token: token, error: null);
  }

  /// Turns the reminder on at [hour]. Returns a message to show if it
  /// couldn't be turned on, or null when it worked.
  static Future<String?> enable({int hour = defaultHour}) async {
    final uid = _uid;
    if (uid == null) return 'Sign in first.';
    if (!supported) return "Reminders aren't available on this device yet.";
    if (needsHomeScreen) return homeScreenMessage;
    try {
      final r = await _permissionAndToken('the reminder');
      final token = r.token;
      if (token == null) return r.error;
      await _db.collection('users').doc(uid).set({
        'reminder_enabled': true,
        'reminder_hour': hour,
        'reminder_prompted': true,
        'tz_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        'fcm_tokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
      return null;
    } catch (_) {
      return "Couldn't turn on reminders. Please try again.";
    }
  }

  /// Turns on "your turn" alerts for Guess the Calories on this device.
  /// Doesn't touch the evening reminder. Returns a message to show if it
  /// couldn't be turned on, or null when it worked.
  static Future<String?> enableGameAlerts() async {
    final uid = _uid;
    if (uid == null) return 'Sign in first.';
    if (!supported) {
      return "Notifications aren't available on this device yet.";
    }
    if (needsHomeScreen) return homeScreenGamesMessage;
    try {
      final r = await _permissionAndToken('game alerts');
      final token = r.token;
      if (token == null) return r.error;
      await _db.collection('users').doc(uid).set({
        'game_notifications': true,
        'tz_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        'fcm_tokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
      return null;
    } catch (_) {
      return "Couldn't turn on game alerts. Please try again.";
    }
  }

  /// Turns on notifications for new messages from friends on this device.
  /// Returns a message to show if it couldn't, or null when it worked.
  static Future<String?> enableChatAlerts() async {
    final uid = _uid;
    if (uid == null) return 'Sign in first.';
    if (!supported) {
      return "Notifications aren't available on this device yet.";
    }
    if (needsHomeScreen) return homeScreenGamesMessage;
    try {
      final r = await _permissionAndToken('message notifications');
      final token = r.token;
      if (token == null) return r.error;
      await _db.collection('users').doc(uid).set({
        'chat_notifications': true,
        'tz_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        'fcm_tokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
      return null;
    } catch (_) {
      return "Couldn't turn on message notifications. Please try again.";
    }
  }

  /// Turns message notifications on or off without asking for permission
  /// (use [enableChatAlerts] to turn them on for the first time).
  static Future<void> setChatAlerts(bool on) async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .set({'chat_notifications': on}, SetOptions(merge: true));
  }

  /// Turns game alerts on or off without asking for permission (use
  /// [enableGameAlerts] to turn them on for the first time).
  static Future<void> setGameAlerts(bool on) async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .set({'game_notifications': on}, SetOptions(merge: true));
  }

  static Future<void> disable() async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'reminder_enabled': false,
      'reminder_prompted': true,
    }, SetOptions(merge: true));
  }

  static Future<void> setHour(int hour) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'reminder_hour': hour,
      'tz_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
    }, SetOptions(merge: true));
  }

  /// "Not now" on the home screen offer.
  static Future<void> dismissOffer() async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .set({'reminder_prompted': true}, SetOptions(merge: true));
  }

  /// Keeps the time zone (clocks change) and this device's token fresh.
  /// Safe to call on every launch; does nothing unless the reminder or
  /// game alerts are on.
  static Future<void> sync() async {
    try {
      final uid = _uid;
      if (uid == null || !supported) return;
      final ref = _db.collection('users').doc(uid);
      final data = (await ref.get()).data();
      if (data?['reminder_enabled'] != true &&
          data?['game_notifications'] != true &&
          data?['chat_notifications'] != true) {
        return;
      }
      final update = <String, dynamic>{};
      final offset = DateTime.now().timeZoneOffset.inMinutes;
      if (data?['tz_offset_minutes'] != offset) {
        update['tz_offset_minutes'] = offset;
      }
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await FirebaseMessaging.instance.getToken(
          vapidKey: kIsWeb ? vapidKey : null,
        );
        final tokens = data?['fcm_tokens'];
        if (token != null &&
            token.isNotEmpty &&
            !(tokens is List && tokens.contains(token))) {
          update['fcm_tokens'] = FieldValue.arrayUnion([token]);
        }
      }
      if (update.isNotEmpty) await ref.set(update, SetOptions(merge: true));
    } catch (_) {
      // Tried again next launch.
    }
  }
}
