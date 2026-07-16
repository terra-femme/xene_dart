import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

enum LaunchSplashVariant { loadingSplash, loadingLottie }

// Swap this to LaunchSplashVariant.loadingLottie to revert the launch loader.
const launchSplashVariant = LaunchSplashVariant.loadingSplash;

const _legacyLoadingLottieAsset = 'assets/animations/LoadingLottie.json';

class LaunchSplash extends StatelessWidget {
  const LaunchSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return switch (launchSplashVariant) {
      LaunchSplashVariant.loadingSplash => const _CenteredSplashVisual(),
      LaunchSplashVariant.loadingLottie => const _LegacyLottieSplash(),
    };
  }
}

class _CenteredSplashVisual extends StatelessWidget {
  const _CenteredSplashVisual();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final logoHeight = math.min(
          math.max(shortestSide * 0.32, 104.0),
          152.0,
        );
        final logoWidth = logoHeight * 0.58;
        final barWidth = math.min(math.max(shortestSide * 0.36, 120.0), 172.0);

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: logoWidth,
                height: logoHeight,
                child: const CustomPaint(painter: _SplashLogoPainter()),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: barWidth,
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    color: Colors.white,
                    minHeight: 3,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SplashLogoPainter extends CustomPainter {
  const _SplashLogoPainter();

  static final Rect _sourceBounds = Rect.fromLTWH(32, 52, 144, 204);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / _sourceBounds.width,
      size.height / _sourceBounds.height,
    );
    final dx = (size.width - _sourceBounds.width * scale) / 2;
    final dy = (size.height - _sourceBounds.height * scale) / 2;

    canvas
      ..save()
      ..translate(dx, dy)
      ..scale(scale)
      ..translate(-_sourceBounds.left, -_sourceBounds.top);

    final glow = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final path in _paths) {
      canvas.drawPath(path, glow);
      canvas.drawPath(path, stroke);
    }

    canvas.restore();
  }

  static final List<Path> _paths = [
    _path([const Offset(36.43, 55.57), const Offset(104.15, 92.38)]),
    _path([
      const Offset(35.70, 132.10),
      const Offset(106.32, 174.61),
      const Offset(105.57, 213.81),
      const Offset(106.70, 174.61),
    ]),
    _path([const Offset(104.86, 133.44), const Offset(171.91, 173.95)]),
    _path([const Offset(171.32, 172.79), const Offset(171.69, 249.80)]),
    _path([const Offset(37.15, 173.33), const Offset(37.01, 251.23)]),
    _path([const Offset(106.46, 214.03), const Offset(36.45, 252.62)]),
    _path([const Offset(36.61, 174.55), const Offset(70.02, 153.92)]),
    _path([const Offset(105.59, 214.29), const Offset(172.36, 251.26)]),
    _path([const Offset(137.46, 152.01), const Offset(171.77, 132.75)]),
    _path([const Offset(171.24, 60.77), const Offset(170.98, 134.15)]),
    _path([const Offset(172.11, 59.41), const Offset(106.09, 93.68)]),
    _path([const Offset(35.08, 55.95), const Offset(105.23, 93.06)]),
    _path([const Offset(35.88, 57.41), const Offset(36.43, 133.41)]),
    _path([const Offset(106.12, 91.75), const Offset(105.70, 134.86)]),
  ];

  static Path _path(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
