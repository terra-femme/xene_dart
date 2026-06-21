/// Conditional facade for the CORS-for-FFT probe.
///
/// Web build → real Web Audio probe (`av_cors_probe_web.dart`).
/// Everything else → no-op stub (`av_cors_probe_stub.dart`).
export 'av_cors_probe_stub.dart'
    if (dart.library.html) 'av_cors_probe_web.dart';
