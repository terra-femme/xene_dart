import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xene_domain/xene_domain.dart';

import '../theme/xene_theme.dart';

/// Data-driven audio-reactive visualizer for deaf/hard-of-hearing users.
///
/// When [analysis] is available and [reduceMotion] is false:
///   Layer 1 — Amplitude envelope: scrolling waveform bars, gradient orange→teal
///   Layer 2 — Energy burst: teal overlay on transient hits (snare/attack)
///   Layer 3 — Beat pulse: orange full-width flash on beat-grid hits
///   Side effect: frequency-mapped HapticFeedback on beat/energy events
///
/// Fallback to WinampVisualizer when [analysis] is null or [reduceMotion] is true.
class TrackVisualizerWidget extends StatefulWidget {
  const TrackVisualizerWidget({
    super.key,
    this.analysis,
    required this.playPositionStream,
    required this.isPlaying,
    required this.durationMs,
    required this.reduceMotion,
    this.barCount = 24,
    this.height = 40.0,
  });

  final TrackAnalysis? analysis;
  final Stream<int> playPositionStream;
  final bool isPlaying;
  final int durationMs;
  final bool reduceMotion;
  final int barCount;
  final double height;

  @override
  State<TrackVisualizerWidget> createState() => _TrackVisualizerState();
}

class _TrackVisualizerState extends State<TrackVisualizerWidget> {
  StreamSubscription<int>? _sub;
  int _positionMs = 0;
  int _lastBeatIndex = -1;
  int _lastEnergyIndex = -1;

  @override
  void initState() {
    super.initState();
    _sub = widget.playPositionStream.listen(_onPosition);
  }

  @override
  void didUpdateWidget(TrackVisualizerWidget old) {
    super.didUpdateWidget(old);
    if (!identical(old.playPositionStream, widget.playPositionStream)) {
      _sub?.cancel();
      _positionMs = 0;
      _lastBeatIndex = -1;
      _lastEnergyIndex = -1;
      _sub = widget.playPositionStream.listen(_onPosition);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onPosition(int positionMs) {
    _positionMs = positionMs;
    _checkHaptics(positionMs);
    if (mounted) setState(() {});
  }

  void _checkHaptics(int positionMs) {
    if (!widget.isPlaying || widget.reduceMotion || widget.analysis == null)
      return;
    final analysis = widget.analysis!;

    // Beat: heavy on every 4th (downbeat), light on off-beats
    for (var i = 0; i < analysis.beatGridMs.length; i++) {
      if ((analysis.beatGridMs[i] - positionMs).abs() <= 20) {
        if (i != _lastBeatIndex) {
          _lastBeatIndex = i;
          if (i % 4 == 0) {
            HapticFeedback.heavyImpact();
          } else {
            HapticFeedback.lightImpact();
          }
        }
        break;
      }
    }

    // Energy: medium on transient hits
    for (var i = 0; i < analysis.energyEventsMs.length; i++) {
      if ((analysis.energyEventsMs[i] - positionMs).abs() <= 30) {
        if (i != _lastEnergyIndex) {
          _lastEnergyIndex = i;
          HapticFeedback.mediumImpact();
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.analysis == null || widget.reduceMotion) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: widget.height,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _AnalysisPainter(
            positionMs: _positionMs,
            analysis: widget.analysis!,
            durationMs: widget.durationMs,
            isPlaying: widget.isPlaying,
            barCount: widget.barCount,
          ),
        ),
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────
class _AnalysisPainter extends CustomPainter {
  const _AnalysisPainter({
    required this.positionMs,
    required this.analysis,
    required this.durationMs,
    required this.isPlaying,
    required this.barCount,
  });

  final int positionMs;
  final TrackAnalysis analysis;
  final int durationMs;
  final bool isPlaying;
  final int barCount;

  static const _beatWindowMs = 20;
  static const _energyWindowMs = 30;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = (size.width / barCount) * 0.6;
    final gap = (size.width / barCount) * 0.4;
    final paint = Paint()..style = PaintingStyle.fill;

    final isBeatHit = analysis.beatGridMs.any(
      (b) => (b - positionMs).abs() <= _beatWindowMs,
    );
    final isEnergyHit = analysis.energyEventsMs.any(
      (e) => (e - positionMs).abs() <= _energyWindowMs,
    );

    final window = _buildWindow();
    final count = min(window.length, barCount);

    // Layer 1 — amplitude envelope, gradient orange→teal by amplitude
    for (var i = 0; i < count; i++) {
      final amp = window[i].clamp(0.0, 1.0);
      final x = i * (barWidth + gap) + gap / 2;
      final normalized = !isPlaying
          ? 0.3
          : isBeatHit
          ? (amp * 0.5 + 0.5).clamp(0.0, 1.0)
          : (amp * 0.8 + 0.1).clamp(0.0, 1.0);
      final barH = (normalized * size.height).clamp(3.0, size.height);
      paint.color = Color.lerp(XeneTheme.orange, XeneTheme.teal, amp)!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - barH, barWidth, barH),
          const Radius.circular(2),
        ),
        paint,
      );
    }

    if (!isPlaying) return;

    // Layer 2 — energy burst: 60%-width teal overlay on transient hits
    if (isEnergyHit) {
      paint.color = XeneTheme.teal.withValues(alpha: 0.6);
      final burstW = barWidth * 0.6;
      final burstOffset = (barWidth - burstW) / 2;
      for (var i = 0; i < count; i++) {
        final amp = (window[i] * 0.9).clamp(0.0, 1.0);
        final barH = (amp * size.height).clamp(3.0, size.height);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              i * (barWidth + gap) + gap / 2 + burstOffset,
              size.height - barH,
              burstW,
              barH,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
    }

    // Layer 3 — beat pulse: full-width orange flash
    if (isBeatHit) {
      paint.color = XeneTheme.orange.withValues(alpha: 0.3);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    }
  }

  List<double> _buildWindow() {
    if (analysis.amplitudeSamples.isEmpty) return List.filled(barCount, 0.5);
    final totalSamples = analysis.amplitudeSamples.length;
    final effectiveDuration = durationMs > 0 ? durationMs : 1;
    final center = ((positionMs / effectiveDuration) * totalSamples)
        .toInt()
        .clamp(0, totalSamples - 1);
    final half = barCount ~/ 2;
    final start = (center - half).clamp(0, totalSamples);
    final end = (center + half).clamp(0, totalSamples);
    final window = analysis.amplitudeSamples.sublist(start, end);
    if (window.length < barCount) {
      return [...window, ...List.filled(barCount - window.length, 0.0)];
    }
    return window;
  }

  @override
  bool shouldRepaint(_AnalysisPainter old) =>
      old.positionMs != positionMs ||
      old.isPlaying != isPlaying ||
      old.durationMs != durationMs;
}
