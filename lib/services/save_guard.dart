import 'package:namer_app/services/web_platform.dart' as web;

/// Saves still on their way to the server (logging, removing or changing
/// food). While any are, closing or refreshing the page asks "Leave site?"
/// first, so a quick refresh can't lose a change half way.
class SaveGuard {
  SaveGuard._();

  static int _pending = 0;

  static int get pending => _pending;

  static Future<T> track<T>(Future<T> Function() save) async {
    _pending++;
    web.setPendingSaves(_pending);
    try {
      return await save();
    } finally {
      _pending--;
      web.setPendingSaves(_pending);
    }
  }
}
