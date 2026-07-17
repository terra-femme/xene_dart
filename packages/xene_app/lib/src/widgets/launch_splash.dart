import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

enum LaunchSplashVariant { loadingSplash, loadingLottie }

// Swap this to LaunchSplashVariant.loadingLottie to revert the launch loader.
const launchSplashVariant = LaunchSplashVariant.loadingSplash;

// Animated WebP frame sequence (NOT a Lottie). The original Splash_X.json was
// a 15 MB Lottie wrapping 83 embedded 1920x1080 raster frames; the lottie
// package pre-decodes every embedded image at load time (~660 MB of bitmaps),
// which fails on iOS devices and flashed the fallback. Flutter's Image widget
// decodes animated WebP frames on demand, so this stays cheap.
const _loadingSplashAsset = 'assets/animations/Splash_X.webp';
const _loadingSplashDuration = Duration(seconds: 5);
const _legacyLoadingLottieAsset = 'assets/animations/LoadingLottie.json';

class LaunchSplash extends StatelessWidget {
  const LaunchSplash({
    super.key,
    this.onPrimaryAnimationLoaded,
    this.onPrimaryAnimationFailed,
  });

  final ValueChanged<Duration>? onPrimaryAnimationLoaded;
  final VoidCallback? onPrimaryAnimationFailed;

  @override
  Widget build(BuildContext context) {
    return switch (launchSplashVariant) {
      LaunchSplashVariant.loadingSplash => _AnimatedWebpSplash(
        onLoaded: onPrimaryAnimationLoaded,
        onFailed: onPrimaryAnimationFailed,
      ),
      LaunchSplashVariant.loadingLottie => const _LegacyLottieSplash(),
    };
  }
}

class _AnimatedWebpSplash extends StatefulWidget {
  const _AnimatedWebpSplash({this.onLoaded, this.onFailed});

  final ValueChanged<Duration>? onLoaded;
  final VoidCallback? onFailed;

  @override
  State<_AnimatedWebpSplash> createState() => _AnimatedWebpSplashState();
}

class _AnimatedWebpSplashState extends State<_AnimatedWebpSplash> {
  bool _loadedReported = false;
  bool _failedReported = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[LaunchSplash] mounted asset=$_loadingSplashAsset');
  }

  @override
  void dispose() {
    debugPrint('[LaunchSplash] disposed asset=$_loadingSplashAsset');
    super.dispose();
  }

  void _reportLoaded() {
    if (_loadedReported) return;
    _loadedReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      debugPrint(
        '[LaunchSplash] animated webp first frame decoded '
        'asset=$_loadingSplashAsset '
        'duration=${_loadingSplashDuration.inMilliseconds}ms',
      );
      widget.onLoaded?.call(_loadingSplashDuration);
    });
  }

  void _reportFailed(Object error) {
    if (_failedReported) return;
    _failedReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      debugPrint(
        '[LaunchSplash] animated webp failed asset=$_loadingSplashAsset '
        'error=$error',
      );
      widget.onFailed?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.white),
        Image.asset(
          _loadingSplashAsset,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null) _reportLoaded();
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            _reportFailed(error);
            return const _ImmediateSplashLogo();
          },
        ),
      ],
    );
  }
}

class _ImmediateSplashLogo extends StatelessWidget {
  const _ImmediateSplashLogo();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortestSide = math.min(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final logoHeight = math.min(
            math.max(shortestSide * 0.34, 128.0),
            380.0,
          );
          final logoWidth = logoHeight * 0.62;
          final barWidth = math.min(
            math.max(shortestSide * 0.34, 112.0),
            188.0,
          );

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
                  height: 2,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'LOADING',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 7,
                  ),
                ),
              ],
            ),
          );
        },
      ),
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

    final stroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final path in _paths) {
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
