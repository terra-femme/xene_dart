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
  late final AnimationController _fade;

  // Reveal fires only when BOTH conditions are true:
  // 1. Minimum hold time has elapsed (JIT warm-up + HTTP parse spike absorbed)
  // 2. Feed data (or error) has arrived
  bool _minimumElapsed = false;
  bool _dataReady = false;
  bool _revealed = false;
  bool _removed = false;

  Timer? _minimumTimer;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 1.0,
    );

    // Guarantee at least 2500ms of Lottie playback.
    // This absorbs the JIT cold-start (~300ms) and any HTTP JSON parse spike
    // so neither event can interrupt the Lottie mid-animation.
    _minimumTimer = Timer(const Duration(milliseconds: 2500), () {
      _minimumElapsed = true;
      _checkRevealConditions();
    });
  }

  @override
  void dispose() {
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

  void _startReveal() {
    if (_revealed) return;
    _revealed = true;

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
        _fade.reverse();

        // Step 4: After fade completes, remove overlay and unlock the crawl ticker.
        Future.delayed(const Duration(milliseconds: 750), () {
          if (!mounted) return;
          ref.read(revealCompleteProvider.notifier).state = true;
          setState(() => _removed = true);
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_removed) return const SizedBox.shrink();

    final feedAsync = ref.watch(feedProvider);

    // Trigger on data OR error so a network failure never leaves the overlay up.
    if ((feedAsync.hasValue || feedAsync.hasError) && !_dataReady) {
      _dataReady = true;
      _checkRevealConditions();
    }

    return AbsorbPointer(
      child: FadeTransition(
        opacity: _fade,
        child: Container(color: Colors.black, child: const LaunchSplash()),
      ),
    );
  }
}
