import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:namer_app/services/save_guard.dart';
import 'package:namer_app/services/web_platform.dart' as web;

/// Spots when a newer version of the site is live and moves to it without
/// getting in the way: nothing pops up over the app.
///
/// - Quietly: when you come back to the app after it's been in the
///   background for [quietAfter], and nothing could be lost (no screen,
///   sheet or dialog open on top, no saves still on their way), it
///   reloads, opening on the new version's home screen.
/// - By choice: Profile shows "Update ready" to load it straight away.
/// - Otherwise the next time the app is opened gets it anyway.
///
/// Each deploy (.github/workflows/deploy.yml) builds the app with
/// `--dart-define=BUILD_ID=<commit>` and publishes `/build.json` with the
/// same id. The app checks that file on start, when it comes back to the
/// front, and every 30 minutes; a different id means a newer version.
/// Local builds have no BUILD_ID and never check.
class AppUpdate {
  AppUpdate._();

  static const buildId = String.fromEnvironment('BUILD_ID');

  /// True once a newer version is live.
  static final ValueNotifier<bool> available = ValueNotifier(false);

  static Timer? _timer;
  static AppLifecycleListener? _lifecycle;
  static AppLifecycleListener? _visibility;
  static DateTime? _lastCheck;
  static DateTime? _hiddenAt;

  /// How long the app must have been in the background before it updates
  /// itself on the way back.
  static const quietAfter = Duration(minutes: 15);

  /// The app's navigators (the main one and each tab's), so a quiet update
  /// can see whether anything is open on top of a tab's first screen.
  static final Set<NavigatorObserver> _watched = {};

  /// Pass to a Navigator's `observers` so quiet updates know about it.
  static NavigatorObserver watch() {
    final o = NavigatorObserver();
    _watched.add(o);
    return o;
  }

  /// For the app's main navigator.
  static final NavigatorObserver rootWatch = watch();

  /// Nothing open over any tab's first screen: no page, sheet or dialog.
  static bool get _nothingOpen =>
      _watched.every((o) => o.navigator?.canPop() != true);

  /// Whether to reload without asking: an update is waiting, the app was
  /// in the background for at least [quietAfter], and nothing open or
  /// unsaved would be lost.
  static bool shouldReloadQuietly({
    required bool available,
    required DateTime? hiddenAt,
    required DateTime now,
    required bool nothingOpen,
    required int pendingSaves,
  }) =>
      available &&
      hiddenAt != null &&
      now.difference(hiddenAt) >= quietAfter &&
      nothingOpen &&
      pendingSaves == 0;

  static void _maybeReloadQuietly() {
    if (shouldReloadQuietly(
      available: available.value,
      hiddenAt: _hiddenAt,
      now: DateTime.now(),
      nothingOpen: _nothingOpen,
      pendingSaves: SaveGuard.pending,
    )) {
      reload();
    }
  }

  static void start() {
    if (!kIsWeb || buildId.isEmpty || _timer != null) return;
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => check());
    _lifecycle = AppLifecycleListener(onResume: check);
    _visibility = AppLifecycleListener(
      onHide: () => _hiddenAt ??= DateTime.now(),
      onShow: () {
        _maybeReloadQuietly();
        _hiddenAt = null;
      },
    );
    // Not straight away: let the app get going first.
    Timer(const Duration(seconds: 20), check);
  }

  /// [id] from `/build.json`, compared with this build.
  static bool isNewer(String? id) =>
      id != null && id.isNotEmpty && buildId.isNotEmpty && id != buildId;

  static Future<void> check() async {
    if (available.value) return;
    final now = DateTime.now();
    final last = _lastCheck;
    // Coming back to the app often shouldn't mean checking every time.
    if (last != null && now.difference(last) < const Duration(minutes: 2)) {
      return;
    }
    _lastCheck = now;
    try {
      final url = Uri.base.resolve('/build.json').replace(
          queryParameters: {'t': '${now.millisecondsSinceEpoch}'});
      final r = await http.get(url).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return;
      final j = json.decode(r.body);
      final id = j is Map ? j['build']?.toString() : null;
      if (isNewer(id)) {
        available.value = true;
        _timer?.cancel();
        _lifecycle?.dispose();
        _lifecycle = null;
      }
    } catch (_) {
      // Offline or no file yet: try again later.
    }
  }

  /// Loads the new version.
  static void reload() => web.reloadToLatest();
}
