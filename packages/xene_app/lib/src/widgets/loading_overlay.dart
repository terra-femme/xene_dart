import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:xene_app/src/providers/app_state_provider.dart';
import 'package:xene_app/src/providers/feed_provider.dart';

class LoadingOverlay extends ConsumerStatefulWidget {
  const LoadingOverlay({super.key});

  @override
  ConsumerState<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends ConsumerState<LoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  bool _revealed = false;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _startReveal() {
    if (_revealed) return;
    _revealed = true;

    _fade.reverse();

    // Stagger each UI layer in after the overlay starts fading.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) ref.read(appRevealProvider.notifier).state = 1;
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) ref.read(appRevealProvider.notifier).state = 2;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) ref.read(appRevealProvider.notifier).state = 3;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) ref.read(appRevealProvider.notifier).state = 4;
    });
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) {
        ref.read(appRevealProvider.notifier).state = 5;
        setState(() => _removed = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_removed) return const SizedBox.shrink();

    final feedAsync = ref.watch(feedProvider);

    // Trigger on data OR error so an API failure doesn't leave overlay forever.
    if ((feedAsync.hasValue || feedAsync.hasError) && !_revealed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startReveal();
      });
    }

    return AbsorbPointer(
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          color: Colors.black,
          child: Center(
            child: Lottie.asset(
              'assets/animations/LoadingLottie.json',
              width: 140,
              height: 140,
              repeat: true,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
