import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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

extension type _Location._(JSObject _) implements JSObject {
  external String get pathname;
  external String get hash;
}

extension type _History._(JSObject _) implements JSObject {
  external void replaceState(JSAny? data, String unused, String url);
}

@JS('location')
external _Location get _location;

@JS('history')
external _History get _history;

/// Removes `?game=…`, `?add=…` etc. from the address bar once handled, so
/// a refresh doesn't open the same thing again. Keeps the page and hash.
void clearUrlQuery() {
  try {
    _history.replaceState(null, '', '${_location.pathname}${_location.hash}');
  } catch (_) {}
}

@JS('document')
external _Document get _document;

extension type _Navigator._(JSObject _) implements JSObject {
  external String get userAgent;
  external JSBoolean? get standalone;
  external JSNumber? get maxTouchPoints;

  /// navigator.share itself, to check it exists (null where it doesn't).
  @JS('share')
  external JSAny? get shareFunction;
  external JSPromise<JSAny?> share(_ShareData data);
}

extension type _ShareData._(JSObject _) implements JSObject {
  external factory _ShareData({String title, String text, String url});
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

/// Opens the phone's (or browser's) own share sheet with [url]. Returns
/// false if there isn't one or it refused, so the caller can copy the link
/// instead. Closing the sheet without sharing counts as handled (true):
/// they saw it and chose not to.
Future<bool> shareText(String title, String text, String url) async {
  try {
    if (_navigator.shareFunction == null) return false;
    final data = _ShareData(title: title, text: text, url: url);
    await _navigator.share(data).toDart;
    return true;
  } catch (e) {
    return e.toString().contains('AbortError');
  }
}

// ---------------------------------------------------------------- voice
// The browser's own speech recognition (Chrome, Edge, Safari; not
// Firefox). Audio is handled by the browser's speech service.

extension type _SpeechRec._(JSObject _) implements JSObject {
  external set lang(String value);
  external set interimResults(bool value);
  external set continuous(bool value);
  external set maxAlternatives(int value);
  external set onresult(JSFunction? value);
  external set onerror(JSFunction? value);
  external set onend(JSFunction? value);
  external void start();
  external void stop();
}

extension type _SpeechEvent._(JSObject _) implements JSObject {
  external _SpeechResults get results;
}

extension type _SpeechResults._(JSObject _) implements JSObject {
  external int get length;
  external _SpeechResult item(int index);
}

extension type _SpeechResult._(JSObject _) implements JSObject {
  external bool get isFinal;
  external int get length;
  external _SpeechAlternative item(int index);
}

extension type _SpeechAlternative._(JSObject _) implements JSObject {
  external String get transcript;
}

extension type _SpeechError._(JSObject _) implements JSObject {
  external String get error;
}

JSFunction? _speechConstructor() {
  try {
    for (final name in const ['SpeechRecognition', 'webkitSpeechRecognition']) {
      final value = globalContext.getProperty<JSAny?>(name.toJS);
      if (value != null && value.typeofEquals('function')) {
        return value as JSFunction;
      }
    }
  } catch (_) {}
  return null;
}

/// A voice-to-text session in progress (see [startSpeech]).
class SpeechSession {
  final _SpeechRec _rec;

  SpeechSession._(this._rec);

  /// Stops listening; the final words still arrive.
  void stop() {
    try {
      _rec.stop();
    } catch (_) {}
  }
}

bool? _speechSupported;

/// True when this browser can turn speech into text.
bool get speechSupported => _speechSupported ??= _speechConstructor() != null;

/// Starts listening (British English). [onText] gets everything heard so
/// far, again each time it changes, with done = true once it's final.
/// [onEnd] is called once when listening stops, with the browser's error
/// code if something went wrong ('not-allowed', 'no-speech', …). Returns
/// null if speech isn't available. Must be called from a tap.
SpeechSession? startSpeech({
  required void Function(String text, bool done) onText,
  required void Function(String? error) onEnd,
  String lang = 'en-GB',
}) {
  final ctor = _speechConstructor();
  if (ctor == null) return null;
  try {
    final rec = ctor.callAsConstructor<_SpeechRec>();
    rec.lang = lang;
    rec.interimResults = true;
    rec.continuous = false;
    rec.maxAlternatives = 1;
    String? error;
    var ended = false;
    rec.onresult = ((_SpeechEvent event) {
      final results = event.results;
      final text = StringBuffer();
      var done = true;
      for (var i = 0; i < results.length; i++) {
        final result = results.item(i);
        if (!result.isFinal) done = false;
        if (result.length > 0) text.write(result.item(0).transcript);
      }
      onText(text.toString().trim(), done);
    }).toJS;
    rec.onerror = ((_SpeechError event) {
      error = event.error;
    }).toJS;
    rec.onend = ((JSAny? _) {
      if (ended) return;
      ended = true;
      onEnd(error);
    }).toJS;
    rec.start();
    return SpeechSession._(rec);
  } catch (_) {
    return null;
  }
}
