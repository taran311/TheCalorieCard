import 'dart:async';
import 'dart:js_interop';

// Just the few browser APIs we need, declared by hand so the app doesn't
// need another package.

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny?> parts, _BlobOptions options);
}

extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({String type});
}

extension type _UrlApi._(JSObject _) implements JSObject {
  external String createObjectURL(_Blob blob);
  external void revokeObjectURL(String url);
}

@JS('URL')
external _UrlApi get _urlApi;

extension type _Style._(JSObject _) implements JSObject {
  external set display(String value);
}

extension type _Element._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external _Style get style;
  external void click();
  external void remove();
  external JSObject appendChild(_Element child);
}

extension type _Document._(JSObject _) implements JSObject {
  external _Element createElement(String tag);
  external _Element? get body;
}

@JS('document')
external _Document get _document;

extension type _Navigator._(JSObject _) implements JSObject {
  external String get userAgent;
  external JSBoolean? get standalone;
  external JSNumber? get maxTouchPoints;
}

@JS('navigator')
external _Navigator get _navigator;

extension type _MediaQueryList._(JSObject _) implements JSObject {
  external bool get matches;
}

@JS('matchMedia')
external _MediaQueryList _matchMedia(String query);

/// Saves [text] as a file called [filename] through the browser's normal
/// download. Returns false if the browser wouldn't do it.
bool downloadTextFile(
  String filename,
  String text, {
  String mimeType = 'text/csv',
}) {
  try {
    final blob = _Blob(
      <JSAny?>[text.toJS].toJS,
      _BlobOptions(type: '$mimeType;charset=utf-8'),
    );
    final url = _urlApi.createObjectURL(blob);
    final link = _document.createElement('a');
    link.href = url;
    link.download = filename;
    link.style.display = 'none';
    final body = _document.body;
    if (body != null) body.appendChild(link);
    link.click();
    link.remove();
    // Give the download time to start before freeing the memory.
    Timer(const Duration(seconds: 30), () {
      try {
        _urlApi.revokeObjectURL(url);
      } catch (_) {}
    });
    return true;
  } catch (_) {
    return false;
  }
}

/// True on an iPhone or iPad when the app is open in the browser rather
/// than from the Home Screen. Apple only allows web notifications for
/// sites added to the Home Screen.
bool get iosNeedsHomeScreen {
  try {
    final ua = _navigator.userAgent;
    final touch = (_navigator.maxTouchPoints?.toDartDouble ?? 0) > 1;
    // iPads ask for the desktop site, so they say "Macintosh" with touch.
    final ios = RegExp(r'iPhone|iPad|iPod').hasMatch(ua) ||
        (ua.contains('Macintosh') && touch);
    if (!ios) return false;
    final standalone = (_navigator.standalone?.toDart ?? false) ||
        _matchMedia('(display-mode: standalone)').matches;
    return !standalone;
  } catch (_) {
    return false;
  }
}
