/// Conditional facade for the Dancing Points visualizer embed.
///
/// Web build → real iframe host (`dancing_points_view_web.dart`).
/// Everything else → web-only notice (`dancing_points_view_stub.dart`).
export 'dancing_points_view_stub.dart'
    if (dart.library.html) 'dancing_points_view_web.dart';
