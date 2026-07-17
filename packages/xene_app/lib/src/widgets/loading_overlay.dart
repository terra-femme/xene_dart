import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_app/src/providers/app_state_provider.dart';
import 'package:xene_app/src/providers/feed_provider.dart';
import 'package:xene_app/src/widgets/launch_splash.dart';

class LoadingOverlay extends ConsumerStatefulWidget {
  const LoadingOverlay({super.key});

  @override
  ConsumerState<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends ConsumerState<LoadingOverlay>
    with SingleTickerProviderStateMixin {
  static const _fallbackFullSplashDuration = Duration(milliseconds: 5000);

  late final AnimationController _fade;
  late final Stopwatch _visibleStopwatch;
  bool _firstBuildLogged = false;

  // Reveal fires only when BOTH conditions are true:
  // 1. Minimum hold time has elapsed (JIT warm-up + HTTP parse spike absorbed)
  // 2. Feed data (or error) has arrived
  bool _minimumElapsed = false;
  bool _dataReady = false;
  bool _revealed = false;
  bool _removed = false;

  Timer? _minimumTimer;
  bool _primarySplashLoaded = false;

  @override
  void initState() {
    super.initState();
    _visibleStopwatch = Stopwatch()..start();
    debugPrint('[LoadingOverlay] Flutter splash shown at t=0ms');
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 1.0,
    );

    // Safety fallback only. The normal path is set by LaunchSplash.onLoaded,
    // which holds the overlay for the authored Lottie's full composition.
    _scheduleMinimumHold(_fallbackFullSplashDuration, reason: 'fallback');
  }

  @override
  void dispose() {
    debugPrint(
      '[LoadingOverlay] disposed at '
      't=${_visibleStopwatch.elapsedMilliseconds}ms '
      'removed=$_removed revealed=$_revealed dataReady=$_dataReady',
    );
    _minimumTimer?.cancel();
    _fade.dispose();
    super.dispose();
  }

  void _checkRevealConditions() {
    if (_dataReady && _minimumElapsed && !_revealed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startReveal();
      });
    }
  }

  void _handleSplashAnimationLoaded(Duration duration) {
    if (_primarySplashLoaded || _revealed || _removed) return;
    _primarySplashLoaded = true;
    _scheduleMinimumHold(duration, reason: 'lottie-full-duration');
  }

  void _handleSplashAnimationFailed() {
    if (_primarySplashLoaded || _revealed || _removed) return;
    debugPrint(
      '[LoadingOverlay] primary splash failed; using fallback hold '
      '${_fallbackFullSplashDuration.inMilliseconds}ms',
    );
    _scheduleMinimumHold(_fallbackFullSplashDuration, reason: 'lottie-failed');
  }

  void _scheduleMinimumHold(Duration duration, {required String reason}) {
    _minimumElapsed = false;
    _minimumTimer?.cancel();
    debugPrint(
      '[LoadingOverlay] full splash hold scheduled reason=$reason '
      'duration=${duration.inMilliseconds}ms '
      'at t=${_visibleStopwatch.elapsedMilliseconds}ms',
    );
    _minimumTimer = Timer(duration, () {
      _minimumElapsed = true;
      debugPrint(
        '[LoadingOverlay] full splash hold elapsed reason=$reason '
        'at t=${_visibleStopwatch.elapsedMilliseconds}ms',
      );
      _checkRevealConditions();
    });
  }

  void _startReveal() {
    if (_revealed) return;
    _revealed = true;
    debugPrint(
      '[LoadingOverlay] reveal starting at '
      't=${_visibleStopwatch.elapsedMilliseconds}ms',
    );

    // Step 1: Pre-warm — jump all UI layers to fully visible WHILE the overlay
    // is still fully opaque. The user never sees this; it lets Flutter build and
    // paint every first frame silently under the black overlay.
    ref.read(appRevealProvider.notifier).state = 5;

    // Step 2: Wait two frames so all pre-warmed widgets settle their first build
    // (first PostFrameCallback = layout pass, second = paint pass).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        // Step 3: Single clean fade — no competing animations, no concurrent
        // full-tree rebuilds. The UI behind is already fully built and idle.
        debugPrint(
          '[LoadingOverlay] fade-out started at '
          't=${_visibleStopwatch.elapsedMilliseconds}ms',
        );
        _fade.reverse();

        // Step 4: After fade completes, remove overlay and unlock the crawl ticker.
        Future.delayed(const Duration(milliseconds: 750), () {
          if (!mounted) return;
          ref.read(revealCompleteProvider.notifier).state = true;
          setState(() => _removed = true);
          _visibleStopwatch.stop();
          debugPrint(
            '[LoadingOverlay] splash removed after '
            '${_visibleStopwatch.elapsedMilliseconds}ms',
          );
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_removed) return const SizedBox.shrink();

    if (!_firstBuildLogged) {
      _firstBuildLogged = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        debugPrint(
          '[LoadingOverlay] first Flutter splash frame painted at '
          't=${_visibleStopwatch.elapsedMilliseconds}ms',
        );
      });
    }

    final feedAsync = ref.watch(feedProvider);

    // Trigger on data OR error so a network failure never leaves the overlay up.
    if ((feedAsync.hasValue || feedAsync.hasError) && !_dataReady) {
      _dataReady = true;
      debugPrint(
        '[LoadingOverlay] feed ${feedAsync.hasError ? 'error' : 'data'} ready '
        'at t=${_visibleStopwatch.elapsedMilliseconds}ms',
      );
      _checkRevealConditions();
    }

    return AbsorbPointer(
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          color: Colors.black,
          child: LaunchSplash(
            onPrimaryAnimationLoaded: _handleSplashAnimationLoaded,
            onPrimaryAnimationFailed: _handleSplashAnimationFailed,
          ),
        ),
      ),
    );
  }
}
