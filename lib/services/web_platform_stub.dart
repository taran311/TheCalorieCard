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
