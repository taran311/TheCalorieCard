import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/proxy_client.dart';

/// Usage statistics: tells the server when something that matters happens
/// (opened the app today, made a card, logged food, closed the day) so it
/// can count them per day. No cookies, nothing stored on the device, no
/// third parties; see the privacy policy. Never slows anything down or
/// shows an error: a missed count doesn't matter.
class Analytics {
  Analytics._();

  /// Off in tests.
  static bool enabled = true;

  static DateTime? _lastActive;

  static void track(String event) {
    if (!enabled) return;
    unawaited(_send(event));
  }

  static Future<void> _send(String event) async {
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
      await ProxyClient.post('/track', {'event': event})
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
  }

  /// Says they're using the app: counted once a day by the server, which
  /// also keeps their "last seen" time. Sent at most every 10 minutes
  /// (opening the app and coming back to it).
  static void active() {
    final now = DateTime.now();
    final last = _lastActive;
    final newDay = last == null ||
        BalanceService.dateKey(last) != BalanceService.dateKey(now);
    if (!newDay && now.difference(last!) < const Duration(minutes: 10)) {
      return;
    }
    _lastActive = now;
    track('active');
  }
}
