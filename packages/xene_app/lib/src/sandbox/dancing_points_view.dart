/// Conditional facade for the Dancing Points visualizer embed.
///
/// Web build → real iframe host (`dancing_points_view_web.dart`).
/// Native (Android/iOS) → the SAME page inside a WebView so it runs on the
///   phone/tablet app (`dancing_points_view_native.dart`).
/// Anything else → web-only notice (`dancing_points_view_stub.dart`).
/// dart.library.html is web-only; dart.library.io is true on Android/iOS.
export 'dancing_points_view_stub.dart'
    if (dart.library.html) 'dancing_points_view_web.dart'
    if (dart.library.io) 'dancing_points_view_native.dart';
