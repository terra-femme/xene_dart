/// Web implementation of the CORS-for-FFT probe.
///
/// The Dancing Points visual reacts via LIVE FFT — it taps the playing audio
/// through Web Audio (`createMediaElementSource` → `AnalyserNode`). That only
/// yields real samples if the audio resource is CORS-readable (element has
/// `crossorigin="anonymous"` AND the server returns `Access-Control-Allow-Origin`).
/// A SoundCloud CDN stream may play fine yet feed the analyser SILENCE because
/// it is cross-origin without CORS headers (the stream is "tainted").
///
/// This probe loads the given URL through a throwaway `<audio crossorigin>`
/// element + AnalyserNode, plays ~2.5s, and reports the peak RMS the analyser
/// actually saw. Non-zero ⇒ live FFT is possible. Zero-while-playing ⇒ tainted,
/// so we'd need a same-origin proxy or the precomputed-analysis fallback.
///
/// The Web Audio calls live in a hand-written JS function (known-correct) that
/// we inject once, then invoke from Dart via `dart:js_interop` — the same
/// inline-script bridge pattern used by `soundcloud_embed_web.dart`.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'av_cors_probe_stub.dart' show CorsProbeResult;

export 'av_cors_probe_stub.dart' show CorsProbeResult;

bool _injected = false;

void _ensureScript() {
  if (_injected) return;
  _injected = true;
  const js = r'''
window.__xeneCorsProbe = function(url) {
  return new Promise(function(resolve) {
    var done = false, maxRms = 0, samples = 0, audio = null, ctx = null;
    function finish(err) {
      if (done) return;
      done = true;
      var played = false;
      try { played = !!(audio && audio.currentTime > 0.05); } catch (e) {}
      try { if (audio) audio.pause(); } catch (e) {}
      try { if (ctx) ctx.close(); } catch (e) {}
      resolve({
        ok: !err && maxRms > 1e-4,
        maxRms: maxRms,
        samples: samples,
        played: played,
        error: err ? ('' + err) : null
      });
    }
    try {
      audio = new Audio();
      audio.crossOrigin = 'anonymous';
      audio.src = url;
      audio.addEventListener('error', function() { finish('audio load/CORS/format error'); });
      var Ctx = window.AudioContext || window.webkitAudioContext;
      ctx = new Ctx();
      var src = ctx.createMediaElementSource(audio);
      var analyser = ctx.createAnalyser();
      analyser.fftSize = 1024;
      analyser.smoothingTimeConstant = 0.0;
      src.connect(analyser);
      src.connect(ctx.destination);
      var buf = new Float32Array(analyser.fftSize);
      var startedAt = 0;
      function poll() {
        if (done) return;
        analyser.getFloatTimeDomainData(buf);
        var sum = 0;
        for (var i = 0; i < buf.length; i++) { var v = buf[i]; sum += v * v; }
        var rms = Math.sqrt(sum / buf.length);
        if (rms > maxRms) maxRms = rms;
        samples++;
        if (performance.now() - startedAt > 2500) { finish(null); return; }
        requestAnimationFrame(poll);
      }
      var p = ctx.resume();
      (p && p.then ? p : Promise.resolve()).then(function() {
        return audio.play();
      }).then(function() {
        startedAt = performance.now();
        poll();
      }).catch(function(e) { finish('play failed: ' + e); });
      setTimeout(function() { finish(maxRms > 0 ? null : 'timeout - no signal in 7s'); }, 7000);
    } catch (e) {
      finish('' + e);
    }
  });
};
''';
  final script = web.HTMLScriptElement()..text = js;
  web.document.body!.appendChild(script);
}

@JS('__xeneCorsProbe')
external JSPromise<JSAny?> _xeneCorsProbe(JSString url);

/// Probe whether Web Audio can read [url] for live FFT. See [CorsProbeResult].
Future<CorsProbeResult> probeCorsForFft(String url) async {
  _ensureScript();
  try {
    final raw = await _xeneCorsProbe(url.toJS).toDart;
    final m = raw.dartify();
    if (m is! Map) {
      return const CorsProbeResult(
        ok: false,
        maxRms: 0,
        error: 'probe returned no result',
      );
    }
    return CorsProbeResult(
      ok: m['ok'] == true,
      maxRms: (m['maxRms'] as num?)?.toDouble() ?? 0,
      samples: (m['samples'] as num?)?.toInt() ?? 0,
      played: m['played'] == true,
      error: m['error'] as String?,
    );
  } catch (e) {
    return CorsProbeResult(
      ok: false,
      maxRms: 0,
      error: 'probe call failed: $e',
    );
  }
}
