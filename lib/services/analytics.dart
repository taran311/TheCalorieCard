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

  static String? _activeDay;

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

  /// Counts them as active today (the server counts each person once a
  /// day; this just avoids asking more than once per day per visit).
  static void active() {
    final day = BalanceService.dateKey(DateTime.now());
    if (_activeDay == day) return;
    _activeDay = day;
    track('active');
  }
}
