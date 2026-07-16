import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';

enum LaunchSplashVariant { loadingSplash, loadingLottie }

// Swap this to LaunchSplashVariant.loadingLottie to revert the launch loader.
const launchSplashVariant = LaunchSplashVariant.loadingLottie;

const _loadingSplashAsset = 'assets/animations/LoadingSplash.svg';
const _legacyLoadingLottieAsset = 'assets/animations/LoadingLottie.json';

class LaunchSplash extends StatelessWidget {
  const LaunchSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return switch (launchSplashVariant) {
      LaunchSplashVariant.loadingSplash => const _CenteredSvgSplash(),
      LaunchSplashVariant.loadingLottie => const _LegacyLottieSplash(),
    };
  }
}

class _CenteredSvgSplash extends StatelessWidget {
  const _CenteredSvgSplash();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final width = math.min(shortestSide * 0.72, 360.0);
        final height = math.min(constraints.maxHeight * 0.58, 520.0);

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: SvgPicture.asset(
              _loadingSplashAsset,
              fit: BoxFit.contain,
              alignment: Alignment.center,
            ),
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
