/// Small string helpers that never throw on empty input.
extension SafeText on String {
  /// First character for avatars ("?" if the string is empty).
  String get initial {
    final t = trim();
    return t.isEmpty ? '?' : t.substring(0, 1);
  }
}

/// Reads a number Firestore may have stored as int, double or string.
double? asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Like [asDouble] but rounded to a whole number.
int? asInt(dynamic v) => asDouble(v)?.round();
