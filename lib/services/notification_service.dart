import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// The evening "you haven't logged today" reminder.
///
/// The app only asks for permission and saves this device's push token
/// (plus your reminder time and time zone) on `users/{uid}`. The server
/// checks once the hour comes round and sends a friendly nudge if nothing
/// has been logged today. Saved fields: `reminder_enabled`,
/// `reminder_hour`, `tz_offset_minutes`, `fcm_tokens`, `reminder_prompted`.
class NotificationService {
  NotificationService._();

  /// Firebase console → Project settings → Cloud Messaging → Web Push
  /// certificates → "Generate key pair", then paste the key here. Until
  /// it's set, reminders are hidden on the web.
  static const vapidKey = '';

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

  static String hourLabel(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h${hour < 12 ? 'am' : 'pm'}';
  }

  static Future<({bool enabled, int hour, bool prompted})> load() async {
    final uid = _uid;
    if (uid == null) return (enabled: false, hour: defaultHour, prompted: false);
    final data = (await _db.collection('users').doc(uid).get()).data();
    final hour = data?['reminder_hour'];
    return (
      enabled: data?['reminder_enabled'] == true,
      hour: hour is int && hour >= 0 && hour < 24 ? hour : defaultHour,
      prompted: data?['reminder_prompted'] == true,
    );
  }

  /// Turns the reminder on at [hour]. Returns a message to show if it
  /// couldn't be turned on, or null when it worked.
  static Future<String?> enable({int hour = defaultHour}) async {
    final uid = _uid;
    if (uid == null) return 'Sign in first.';
    if (!supported) return "Reminders aren't available on this device yet.";
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      final status = settings.authorizationStatus;
      if (status == AuthorizationStatus.denied) {
        return 'Notifications are blocked. Allow them for The Calorie Card '
            'in your browser or phone settings, then try again.';
      }
      if (status == AuthorizationStatus.notDetermined) {
        return 'Allow notifications to get the reminder.';
      }
      final token = await messaging.getToken(
        vapidKey: kIsWeb ? vapidKey : null,
      );
      if (token == null || token.isEmpty) {
        return "Couldn't set up notifications on this device.";
      }
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
  /// Safe to call on every launch; does nothing unless reminders are on.
  static Future<void> sync() async {
    try {
      final uid = _uid;
      if (uid == null || !supported) return;
      final ref = _db.collection('users').doc(uid);
      final data = (await ref.get()).data();
      if (data?['reminder_enabled'] != true) return;
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
