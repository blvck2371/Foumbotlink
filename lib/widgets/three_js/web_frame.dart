/// Scène Three.js dans un `iframe` — navigateur uniquement (le mobile
/// passe par une WebView, voir `three_js_view.dart`).
library;

export 'web_frame_stub.dart' if (dart.library.js_interop) 'web_frame_web.dart';
