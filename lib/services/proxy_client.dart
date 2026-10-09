import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Single place for talking to the fatsecret-proxy backend.
///
/// Every request carries the signed-in user's Firebase ID token so the proxy
/// can reject anonymous traffic (and rate-limit per user).
class ProxyClient {
  ProxyClient._();

  /// Override at build time with:
  ///   flutter build web --dart-define=PROXY_BASE_URL=http://localhost:3000
  static const String baseUrl = String.fromEnvironment(
    'PROXY_BASE_URL',
    defaultValue: 'https://fatsecret-proxy.onrender.com',
  );

  static Future<Map<String, String>> _headers() async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Cached by the SDK and refreshed automatically when close to expiry.
      final token = await user.getIdToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<http.Response> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
      body: json.encode(body),
    );
  }

  static DateTime? _lastWarmUp;

  /// Wakes the server up ahead of a lookup. The free hosting plan puts it
  /// to sleep when idle and the first request can take 30-50 seconds, so
  /// we nudge it as soon as someone looks likely to log food. Cheap and
  /// fire-and-forget: at most once every 4 minutes, errors ignored.
  static void warmUp() {
    final now = DateTime.now();
    final last = _lastWarmUp;
    if (last != null && now.difference(last) < const Duration(minutes: 4)) {
      return;
    }
    _lastWarmUp = now;
    http
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 60))
        .then((_) {}, onError: (_) {});
  }

  static Future<http.Response> get(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    return http.get(uri, headers: await _headers());
  }
}
