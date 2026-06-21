/// Non-web stub. The CORS-for-FFT probe needs the Web Audio API, which only
/// exists in a browser build. On native platforms this returns "unsupported".
library;

/// Result of probing whether Web Audio can read a stream URL for live FFT.
///
/// - [ok] true  → the AnalyserNode saw real signal (non-zero RMS) → the stream
///   is CORS-readable, so live-FFT reactivity (Dancing Points) is possible.
/// - [ok] false + [played] true → the audio played but FFT was silent → the
///   resource is cross-origin WITHOUT CORS headers (tainted → zeros). Live FFT
///   is NOT possible; needs a same-origin proxy or a precomputed fallback.
/// - [error] set → the audio could not even load/play (CORS/format/network).
class CorsProbeResult {
  const CorsProbeResult({
    required this.ok,
    required this.maxRms,
    this.samples = 0,
    this.played = false,
    this.error,
  });

  final bool ok;
  final double maxRms;
  final int samples;
  final bool played;
  final String? error;
}

/// Native stub — always unsupported off the web.
Future<CorsProbeResult> probeCorsForFft(String url) async {
  return const CorsProbeResult(
    ok: false,
    maxRms: 0,
    error: 'Web-only: run this in the web build to probe Web Audio CORS.',
  );
}
