import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:namer_app/services/web_platform.dart' as web;

/// Spots when a newer version of the site is live, so the app can offer
/// "A new version is ready · Refresh".
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
  static DateTime? _lastCheck;

  static void start() {
    if (!kIsWeb || buildId.isEmpty || _timer != null) return;
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => check());
    _lifecycle = AppLifecycleListener(onResume: check);
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
