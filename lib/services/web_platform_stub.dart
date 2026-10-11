/// Not running in a browser: there's nothing to download into, so the
/// caller falls back (e.g. copies the text instead). Returns false.
bool downloadTextFile(
  String filename,
  String text, {
  String mimeType = 'text/csv',
}) =>
    false;

/// Only meaningful in a browser.
bool get iosNeedsHomeScreen => false;

/// Nothing to tidy outside a browser.
void clearUrlQuery() {}

/// No browser share sheet here: returns false so the caller copies the
/// link instead.
Future<bool> shareText(String title, String text, String url) async => false;

/// A voice-to-text session in progress (see [startSpeech]).
class SpeechSession {
  SpeechSession._();

  /// Stops listening; the final words still arrive.
  void stop() {}
}

/// No speech recognition outside a browser.
bool get speechSupported => false;

/// Not available here: always null.
SpeechSession? startSpeech({
  required void Function(String text, bool done) onText,
  required void Function(String? error) onEnd,
  String lang = 'en-GB',
}) =>
    null;

/// Nothing to reload outside a browser.
void reloadToLatest() {}
