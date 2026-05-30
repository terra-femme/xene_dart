import 'dart:math';

import 'package:flutter/material.dart';

class WinampVisualizer extends StatefulWidget {
  const WinampVisualizer({
    super.key,
    required this.isPlaying,
    required this.color,
    this.barCount = 24,
    this.height = 40.0,
  });

  final bool isPlaying;
  final Color color;
  final int barCount;
  final double height;

  @override
  State<WinampVisualizer> createState() => _WinampVisualizerState();
}

class _WinampVisualizerState extends State<WinampVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<double> _phaseOffsets;
  late final List<double> _amplitudes;

  @override
  void initState() {
    super.initState();
    final rng = Random(42); // fixed seed for consistent look

    // Each bar gets a unique phase and amplitude so they don't move in sync.
    _phaseOffsets = List.generate(
      widget.barCount,
      (i) => rng.nextDouble() * 2 * pi,
    );
    _amplitudes = List.generate(
      widget.barCount,
      (i) => 0.3 + rng.nextDouble() * 0.7,
    );

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _VisualizerPainter(
            barCount: widget.barCount,
            phaseOffsets: _phaseOffsets,
            amplitudes: _amplitudes,
            progress: widget.isPlaying ? _ctrl.value : 0.5,
            frozen: !widget.isPlaying,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  const _VisualizerPainter({
    required this.barCount,
    required this.phaseOffsets,
    required this.amplitudes,
    required this.progress,
    required this.frozen,
    required this.color,
  });

  final int barCount;
  final List<double> phaseOffsets;
  final List<double> amplitudes;
  final double progress; // 0..1 from AnimationController
  final bool frozen;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final barWidth = (size.width / barCount) * 0.6;
    final gap = (size.width / barCount) * 0.4;
    final t = progress * 2 * pi;

    for (var i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap) + gap / 2;
      final normalized = frozen
          ? 0.3 + amplitudes[i] * 0.2 // flat-ish when paused
          : (0.15 + 0.85 * ((sin(t + phaseOffsets[i]) + 1) / 2) * amplitudes[i]);

      final barH = (normalized * size.height).clamp(3.0, size.height);
      final top = size.height - barH;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, barWidth, barH),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_VisualizerPainter old) =>
      old.progress != progress || old.frozen != frozen || old.color != color;
}
