/// Small browser-only helpers (file downloads, "is this an iPhone that
/// hasn't installed the app?"). On other platforms they quietly do
/// nothing, so pages can call them without checking.
export 'web_platform_stub.dart'
    if (dart.library.js_interop) 'web_platform_web.dart';
