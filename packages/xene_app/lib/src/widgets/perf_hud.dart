import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// On-screen performance HUD for diagnosing jank on the *actual* device.
///
/// WHY THIS EXISTS: on a touch-only tablet/phone you cannot open DevTools, so
/// desktop F12 frame timings don't describe what the device is really doing.
/// This overlay subscribes to [SchedulerBinding.addTimingsCallback] — the same
/// data DevTools' performance view uses — and paints it directly on the screen
/// you're holding.
///
/// HOW TO READ IT:
/// - `build`  = time the UI thread spent building/laying out a frame (Dart).
/// - `raster` = time the GPU thread spent rasterizing it (CanvasKit/Skia).
/// - A frame is smooth if **build + raster** each stay under ~16ms (60fps) or
///   ~11ms (90/120fps). The HUD shows the worst frame in the last window and a
///   running jank counter so you can correlate spikes with a gesture (e.g. the
///   moment the feed jiggles or a tab switch stalls).
///
/// The HUD refreshes on a throttled [Timer] (not every frame) so it adds
/// negligible load and does not distort its own measurements.
class PerfHud extends StatefulWidget {
  const PerfHud({super.key});

  @override
  State<PerfHud> createState() => _PerfHudState();
}

class _PerfHudState extends State<PerfHud> {
  // Jank thresholds in milliseconds. A 60fps budget is ~16.7ms per thread.
  static const _budget60 = 16.7;
  static const _budget30 = 33.3;

  // Rolling window of the most recent frame timings between HUD refreshes.
  final List<FrameTiming> _window = [];

  // Cumulative counters since the HUD mounted.
  int _totalFrames = 0;
  int _jank60 = 0; // frames over the 60fps budget on either thread
  int _jank30 = 0; // frames over the 30fps budget on either thread (severe)

  // Snapshot rendered to the screen (recomputed on the throttle tick).
  double _avgBuild = 0;
  double _avgRaster = 0;
  double _worstBuild = 0;
  double _worstRaster = 0;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // Refresh the on-screen numbers ~2x/sec. Cheap, and slow enough that the
    // HUD's own rebuild is not a meaningful share of the frame budget.
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  // Called by the engine after each batch of frames. Keep this cheap — just
  // bucket the numbers; rendering happens on the throttle tick.
  void _onTimings(List<FrameTiming> timings) {
    _window.addAll(timings);
    for (final t in timings) {
      _totalFrames++;
      final buildMs = t.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = t.rasterDuration.inMicroseconds / 1000.0;
      if (buildMs > _budget30 || rasterMs > _budget30) {
        _jank30++;
      } else if (buildMs > _budget60 || rasterMs > _budget60) {
        _jank60++;
      }
    }
  }

  void _refresh() {
    if (!mounted) return;
    if (_window.isEmpty) {
      // No frames since last tick (idle). Don't zero the cumulative counters;
      // just leave the last snapshot in place.
      setState(() {});
      return;
    }

    double sumBuild = 0, sumRaster = 0, worstBuild = 0, worstRaster = 0;
    for (final t in _window) {
      final b = t.buildDuration.inMicroseconds / 1000.0;
      final r = t.rasterDuration.inMicroseconds / 1000.0;
      sumBuild += b;
      sumRaster += r;
      if (b > worstBuild) worstBuild = b;
      if (r > worstRaster) worstRaster = r;
    }
    final n = _window.length;

    setState(() {
      _avgBuild = sumBuild / n;
      _avgRaster = sumRaster / n;
      _worstBuild = worstBuild;
      _worstRaster = worstRaster;
    });
    _window.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Device pixel ratio drives the "scroll shimmer" hypothesis: a fractional
    // DPR re-rasterizes glyphs onto different sub-pixels each scroll frame
    // (jiggle), while an integer DPR (2.0/3.0 on iOS) does not. Reading it on
    // both devices confirms whether to gate the auto-crawl on fractional DPR.
    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    final isIntegerDpr = dpr == dpr.roundToDouble();
    final size = mq.size;

    // Provide our own Directionality: the HUD is mounted *above* the app's
    // navigator (in MaterialApp.builder), so it can't inherit one from below.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Container(
              margin: const EdgeInsets.only(top: 64, right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _line('build  avg ${_avgBuild.toStringAsFixed(1)}ms'),
                  _line(
                    '       max ${_worstBuild.toStringAsFixed(1)}ms',
                    warn: _worstBuild > _budget60,
                  ),
                  _line('raster avg ${_avgRaster.toStringAsFixed(1)}ms'),
                  _line(
                    '       max ${_worstRaster.toStringAsFixed(1)}ms',
                    warn: _worstRaster > _budget60,
                  ),
                  const SizedBox(height: 2),
                  _line('frames $_totalFrames'),
                  _line('jank>16ms $_jank60', warn: _jank60 > 0),
                  _line('jank>33ms $_jank30', warn: _jank30 > 0),
                  const SizedBox(height: 2),
                  // DPR in red when fractional — the suspected jiggle trigger.
                  _line('dpr $dpr', warn: !isIntegerDpr),
                  _line(
                    'size ${size.width.toStringAsFixed(0)}x'
                    '${size.height.toStringAsFixed(0)}',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String text, {bool warn = false}) {
    return Text(
      text,
      style: TextStyle(
        color: warn ? const Color(0xFFFF6B6B) : const Color(0xFF7CFC8A),
        fontFamily: 'monospace',
        fontSize: 11,
        height: 1.3,
      ),
    );
  }
}
