import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

enum LaunchSplashVariant { loadingSplash, loadingLottie }

// Swap this to LaunchSplashVariant.loadingLottie to revert the launch loader.
const launchSplashVariant = LaunchSplashVariant.loadingSplash;

const _loadingSplashAsset = 'assets/animations/Splash_X.json';
const _legacyLoadingLottieAsset = 'assets/animations/LoadingLottie.json';

class LaunchSplash extends StatelessWidget {
  const LaunchSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return switch (launchSplashVariant) {
      LaunchSplashVariant.loadingSplash => const _NewLottieSplash(),
      LaunchSplashVariant.loadingLottie => const _LegacyLottieSplash(),
    };
  }
}

class _NewLottieSplash extends StatelessWidget {
  const _NewLottieSplash();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Lottie.asset(
            _loadingSplashAsset,
            repeat: true,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        );
      },
    );
  }
}

class _LegacyLottieSplash extends StatelessWidget {
  const _LegacyLottieSplash();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Lottie.asset(
        _legacyLoadingLottieAsset,
        width: 140,
        height: 140,
        repeat: true,
        fit: BoxFit.contain,
      ),
    );
  }
}
