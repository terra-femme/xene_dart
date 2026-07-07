import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/device_capability_stub.dart'
    if (dart.library.html) '../platform/device_capability_web.dart';

/// How feed cards are rendered for the current device.
///
/// - [full]: the rich card (nested layout, badges, gradients) — used on iOS,
///   desktop, and capable Android.
/// - [lite]: a flat, cheap-to-build card (still keeps the thumbnail — raster is
///   not the bottleneck; widget *build* cost is) — used on weak Android tablets.
enum FeedRenderMode { full, lite }

/// Decides [FeedRenderMode] with a hybrid strategy:
///
/// 1. **Heuristic (instant):** the browser's deviceMemory / core count gives an
///    initial guess at construction, so weak Android starts in [lite] with no
///    startup jank, while iOS (no deviceMemory) starts [full].
/// 2. **Runtime backstop (measured):** if a device guessed [full] then exhibits
///    *sustained* build-thread jank, demote it to [lite]. This catches devices
///    the heuristic couldn't classify (e.g. iOS with no deviceMemory, or an
///    Android that reports lots of RAM but still can't keep up).
///
/// The decision is **one-directional** (only full → lite) so the UI never
/// flip-flops mid-session: the heuristic's only "false positive" is being
/// conservative (a borderline device renders the lite card), which is safe.
final feedRenderModeProvider =
    StateNotifierProvider<FeedRenderModeNotifier, FeedRenderMode>(
      FeedRenderModeNotifier.new,
    );

class FeedRenderModeNotifier extends StateNotifier<FeedRenderMode> {
  FeedRenderModeNotifier(this.ref) : super(_initialMode()) {
    // Only watch frames if we might still demote. If we already started lite,
    // there's nothing left to decide.
    if (state == FeedRenderMode.full) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
    }
  }

  final Ref ref;

  // A frame whose build phase exceeds this (ms) counts as "heavy".
  static const double _heavyBuildMs = 40.0;
  // Number of (net) heavy frames that trips a demotion. Sustained, not a spike:
  // isolated heavy frames (e.g. the initial load) decay back down below.
  static const int _heavyFrameTrigger = 30;

  int _heavyFrames = 0;
  bool _watching = true;

  static FeedRenderMode _initialMode() {
    final lowEnd = webLowEndHint();
    if (lowEnd == true) {
      debugPrint('[renderMode] heuristic → LITE (browser reports low-end)');
      return FeedRenderMode.lite;
    }
    debugPrint('[renderMode] heuristic → FULL (lowEndHint=$lowEnd)');
    return FeedRenderMode.full;
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!_watching) return;
    for (final t in timings) {
      final buildMs = t.buildDuration.inMicroseconds / 1000.0;
      if (buildMs > _heavyBuildMs) {
        _heavyFrames++;
        if (_heavyFrames >= _heavyFrameTrigger) {
          _demoteToLite();
          return;
        }
      } else if (_heavyFrames > 0) {
        // Require *sustained* jank: a smooth frame walks the counter back so a
        // brief startup burst on a capable device never trips the trigger.
        _heavyFrames--;
      }
    }
  }

  void _demoteToLite() {
    debugPrint(
      '[renderMode] runtime → LITE (sustained build jank '
      '>${_heavyBuildMs}ms over $_heavyFrameTrigger frames)',
    );
    _stopWatching();
    if (mounted) state = FeedRenderMode.lite;
  }

  void _stopWatching() {
    if (!_watching) return;
    _watching = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    _stopWatching();
    super.dispose();
  }
}
