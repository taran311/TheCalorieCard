import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Play Store updates for the Android app (the website updates itself, see
/// AppUpdate).
///
/// - A new version that's been out for [nudgeAfterDays] and still isn't
///   installed (auto-update is off, or hasn't run): a small "Update" card
///   on the Card screen. It downloads in the background while they carry
///   on, then one tap restarts into it. "Later" hides it for a week.
/// - This build older than the server's `android_min_build` (set on Render
///   as ANDROID_MIN_BUILD, only for a serious bug): [mustUpdate] is true and
///   the app shows a full "Please update" screen until it's updated.
///
/// Only works for installs from Google Play (not sideloaded APKs).
class PlayUpdate {
  PlayUpdate._();

  /// Days an update has been out before we mention it. Most phones have
  /// updated by then on their own.
  static const nudgeAfterDays = 7;

  /// How long "Later" hides the card.
  static const snooze = Duration(days: 7);

  static const _snoozeKey = 'play_update_snoozed_at';

  /// Show the "new version ready" card.
  static final ValueNotifier<bool> offer = ValueNotifier(false);

  /// Downloaded and ready: one tap restarts into it.
  static final ValueNotifier<bool> downloaded = ValueNotifier(false);

  /// This version is too old to keep using: show the update screen.
  static final ValueNotifier<bool> mustUpdate = ValueNotifier(false);

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _started = false;
  static AppLifecycleListener? _lifecycle;
  static DateTime? _lastCheck;
  static StreamSubscription<InstallStatus>? _installSub;

  /// Checks now, and again whenever the app comes back to the front.
  static void start() {
    if (!supported || _started) return;
    _started = true;
    _lifecycle = AppLifecycleListener(onResume: check);
    // Let the app get going first.
    Timer(const Duration(seconds: 8), check);
  }

  /// Whether to offer the update card. Exported for tests.
  static bool shouldOffer({
    required bool available,
    required int? stalenessDays,
    required bool flexibleAllowed,
    required DateTime? snoozedAt,
    required DateTime now,
  }) =>
      available &&
      flexibleAllowed &&
      (stalenessDays ?? 0) >= nudgeAfterDays &&
      (snoozedAt == null || now.difference(snoozedAt) >= snooze);

  /// Whether this build is too old to use. Exported for tests.
  static bool isTooOld({required int? thisBuild, required int minBuild}) =>
      thisBuild != null && minBuild > 0 && thisBuild < minBuild;

  static Future<void> check() async {
    if (!supported) return;
    final now = DateTime.now();
    final last = _lastCheck;
    if (last != null && now.difference(last) < const Duration(minutes: 30)) {
      return;
    }
    _lastCheck = now;
    try {
      final info = await InAppUpdate.checkForUpdate();
      final available =
          info.updateAvailability == UpdateAvailability.updateAvailable ||
              info.updateAvailability ==
                  UpdateAvailability.developerTriggeredUpdateInProgress;
      if (info.installStatus == InstallStatus.downloaded) {
        downloaded.value = true;
        offer.value = true;
      }

      // Too old to use? Checked with the server, which knows the oldest
      // version that still works.
      final tooOld = isTooOld(
          thisBuild: await _thisBuild(), minBuild: await _minBuild());
      mustUpdate.value = tooOld && available;
      if (mustUpdate.value) return;

      final prefs = await SharedPreferences.getInstance();
      final snoozed = prefs.getInt(_snoozeKey);
      offer.value = downloaded.value ||
          shouldOffer(
            available: available,
            stalenessDays: info.clientVersionStalenessDays,
            flexibleAllowed: info.flexibleUpdateAllowed,
            snoozedAt: snoozed == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(snoozed),
            now: now,
          );
    } catch (_) {
      // Not installed from Play, offline, or Play Store unavailable: the
      // Play Store's own updates still happen.
    }
  }

  static Future<int?> _thisBuild() async {
    try {
      return int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
    } catch (_) {
      return null;
    }
  }

  static Future<int> _minBuild() async {
    try {
      final r = await ProxyClient.get('/app/config')
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return 0;
      final j = json.decode(r.body);
      final v = j is Map ? j['android_min_build'] : null;
      return v is num ? v.toInt() : 0;
    } catch (_) {
      // Can't tell: never lock anyone out over a network blip.
      return 0;
    }
  }

  /// "Update": downloads in the background, or restarts into it once it's
  /// downloaded.
  static Future<void> update() async {
    if (downloaded.value) {
      await InAppUpdate.completeFlexibleUpdate();
      return;
    }
    _installSub ??= InAppUpdate.installUpdateListener.listen((status) {
      if (status == InstallStatus.downloaded) downloaded.value = true;
    });
    await InAppUpdate.startFlexibleUpdate();
  }

  /// The "Please update" screen's button: Google's full-screen update.
  static Future<void> updateNow() => InAppUpdate.performImmediateUpdate();

  /// "Later": hidden for a week.
  static Future<void> later() async {
    offer.value = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_snoozeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static void stop() {
    _lifecycle?.dispose();
    _lifecycle = null;
    _installSub?.cancel();
    _installSub = null;
    _started = false;
  }
}
