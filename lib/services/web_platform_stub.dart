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
