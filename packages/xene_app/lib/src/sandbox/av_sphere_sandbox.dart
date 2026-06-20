import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';

import '../providers/accessibility_provider.dart';
import '../providers/track_analysis_provider.dart';
import '../theme/xene_theme.dart';
// Conditional facade: real iframe player on web, no-op stub elsewhere.
import '../widgets/soundcloud_embed.dart';

final _logger = Logger('av_sphere_sandbox');

/// Dev-only viability test for audioreactive visuals.
///
/// Plays an already-analyzed SoundCloud track and renders a point-sphere that
/// reacts to the track's REAL amplitude/beat data (from `TrackAnalysis`),
/// synced to live playback position via [scPlayPositionStream]. Nothing here is
/// synthesized — if a value moves, it came from the actual waveform/BPM.
///
/// Limits (honest): SoundCloud's data is an amplitude envelope only, so the
/// sphere reacts to loudness + beat hits, NOT to bass-vs-treble separation.
class AvSphereSandbox extends ConsumerStatefulWidget {
  const AvSphereSandbox({super.key});

  @override
  ConsumerState<AvSphereSandbox> createState() => _AvSphereSandboxState();
}

class _AvSphereSandboxState extends ConsumerState<AvSphereSandbox> {
  final _controller = TextEditingController();
  String? _trackId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _load() {
    final id = _controller.text.trim();
    _logger.info('[avSandbox] load requested trackId="$id"');
    if (id.isEmpty) return;
    setState(() => _trackId = id);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = ref.watch(
      accessibilityProvider.select((s) => s.reduceMotion),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: GoogleFonts.dmMono(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'SoundCloud numeric track ID (already analyzed)',
                    hintStyle: GoogleFonts.dmMono(
                      fontSize: 12,
                      color: XeneTheme.muted,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _load,
                  child: Text(
                    'LOAD',
                    style: GoogleFonts.teko(letterSpacing: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Paste the numeric track ID of a SoundCloud track you have already '
            'played/queued in the app (so its analysis exists). The sphere '
            'reacts to real amplitude + beats; it cannot separate bass from '
            'treble — that needs the raw audio file.',
            style: GoogleFonts.dmMono(
              fontSize: 10,
              height: 1.6,
              color: XeneTheme.muted,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _body(reduceMotion)),
      ],
    );
  }

  Widget _body(bool reduceMotion) {
    final trackId = _trackId;
    if (trackId == null) {
      return _centerNote('Enter a track ID above and press LOAD.');
    }

    final analysisAsync = ref.watch(
      trackAnalysisProvider(('soundcloud', trackId)),
    );

    return analysisAsync.when(
      loading: () => const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) {
        _logger.warning(
          '[avSandbox] analysis fetch error trackId=$trackId: $e',
        );
        return _centerNote('Fetch error: $e');
      },
      data: (analysis) {
        if (analysis == null) {
          _logger.info('[avSandbox] no analysis for trackId=$trackId');
          return _centerNote(
            'No analysis found for this track.\n\n'
            'Play/queue it once in the app first so the backend analyzes it, '
            'then come back and load it here.',
          );
        }
        return _SphereStage(
          key: ValueKey(trackId),
          trackId: trackId,
          analysis: analysis,
          reduceMotion: reduceMotion,
        );
      },
    );
  }

  Widget _centerNote(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.dmMono(
          fontSize: 12,
          height: 1.7,
          color: XeneTheme.muted,
        ),
      ),
    ),
  );
}

// ─── Stage: plays the embed + drives the sphere ────────────────────────────────
class _SphereStage extends StatefulWidget {
  const _SphereStage({
    super.key,
    required this.trackId,
    required this.analysis,
    required this.reduceMotion,
  });

  static const pointCount = 540;

  final String trackId;
  final TrackAnalysis analysis;
  final bool reduceMotion;

  @override
  State<_SphereStage> createState() => _SphereStageState();
}

class _SphereStageState extends State<_SphereStage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final List<_P3> _points;
  late final int _durationMs;
  final _model = _SphereModel();

  StreamSubscription<int>? _posSub;
  Duration _lastElapsed = Duration.zero;
  int _lastBeatIndex = -1;
  int _lastEnergyIndex = -1;

  @override
  void initState() {
    super.initState();
    _points = _fibonacciSphere(_SphereStage.pointCount);
    _durationMs = _estimateDurationMs(widget.analysis);
    _logger.info(
      '[avSandbox] stage init trackId=${widget.trackId} '
      'durationMs=$_durationMs beats=${widget.analysis.beatGridMs.length} '
      'amps=${widget.analysis.amplitudeSamples.length} '
      'energy=${widget.analysis.energyEventsMs.length} bpm=${widget.analysis.bpm}',
    );
    if (_durationMs <= 0 || widget.analysis.amplitudeSamples.isEmpty) {
      _logger.warning(
        '[avSandbox] analysis missing duration/amplitude — sphere will idle '
        '(durationMs=$_durationMs amps=${widget.analysis.amplitudeSamples.length})',
      );
    }
    _posSub = scPlayPositionStream.listen((ms) => _model.positionMs = ms);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _posSub?.cancel();
    _model.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dtMs = (elapsed - _lastElapsed).inMicroseconds / 1000.0;
    _lastElapsed = elapsed;
    // Skip the first tick and any post-hitch jump so decay/rotation stay stable.
    if (dtMs <= 0 || dtMs > 200) return;

    // Constant slow spin so the sphere reads as 3D even when audio is quiet.
    _model.rotation += dtMs * 0.00035;

    // Breathe toward the real amplitude at the current playback position.
    final target = _amplitudeAt(
      widget.analysis,
      _model.positionMs,
      _durationMs,
    );
    _model.amp += (target - _model.amp) * (1 - math.exp(-dtMs / 80));

    _detectEvents(_model.positionMs);

    // Decay the impulse pulses.
    _model.beatPulse = math.max(0, _model.beatPulse - dtMs / 320);
    _model.energyPulse = math.max(0, _model.energyPulse - dtMs / 200);

    _model.tick();
  }

  void _detectEvents(int posMs) {
    if (widget.reduceMotion) return;
    final a = widget.analysis;

    // Beat pulse — jolt + haptic. Heavy on downbeat (every 4th), light off-beat.
    for (var i = 0; i < a.beatGridMs.length; i++) {
      if ((a.beatGridMs[i] - posMs).abs() <= 40) {
        if (i != _lastBeatIndex) {
          _lastBeatIndex = i;
          _model.beatIndex = i;
          _model.beatPulse = 1.0;
          if (i % 4 == 0) {
            HapticFeedback.heavyImpact();
          } else {
            HapticFeedback.lightImpact();
          }
        }
        break;
      }
    }

    // Energy shimmer — visual only. Energy events are dense, so firing haptics
    // here would be a constant buzz; we drive the point shimmer instead.
    for (var i = 0; i < a.energyEventsMs.length; i++) {
      if ((a.energyEventsMs[i] - posMs).abs() <= 50) {
        if (i != _lastEnergyIndex) {
          _lastEnergyIndex = i;
          _model.energyPulse = 1.0;
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The official SC player — this is what actually plays the audio and
        // emits the position stream the sphere syncs to.
        Container(
          height: 120,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: XeneTheme.border),
          ),
          clipBehavior: Clip.hardEdge,
          child: SoundCloudEmbed(trackId: widget.trackId),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SpherePainter(model: _model, points: _points),
                    size: Size.infinite,
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 12,
                child: _DebugOverlay(model: _model, durationMs: _durationMs),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Live, mutable state shared with the painter (drives repaint) ──────────────
class _SphereModel extends ChangeNotifier {
  double rotation = 0;
  double amp = 0.35;
  double beatPulse = 0;
  double energyPulse = 0;
  int positionMs = 0;
  int beatIndex = -1;

  /// Notify listeners (the painter + overlay) that a frame's values changed.
  void tick() => notifyListeners();
}

// ─── Painter ───────────────────────────────────────────────────────────────────
class _SpherePainter extends CustomPainter {
  _SpherePainter({required this.model, required this.points})
    : super(repaint: model);

  final _SphereModel model;
  final List<_P3> points;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final base = math.min(size.width, size.height) * 0.34;
    // Radius breathes with amplitude and pops on the beat.
    final radius = base * (0.80 + model.amp * 0.30 + model.beatPulse * 0.16);

    final rot = model.rotation;
    final cosR = math.cos(rot);
    final sinR = math.sin(rot);
    final color = Color.lerp(XeneTheme.orange, XeneTheme.teal, model.amp)!;
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in points) {
      // Rotate around the Y axis, then orthographically project to 2D.
      final x = p.x * cosR + p.z * sinR;
      final z = -p.x * sinR + p.z * cosR;
      final sx = cx + x * radius;
      final sy = cy + p.y * radius;

      // depth: 0 = back of sphere, 1 = facing the viewer.
      final depth = (z + 1) / 2;
      final dotSize =
          (0.6 + depth * 2.6) *
          (1 + model.energyPulse * 0.7 + model.beatPulse * 0.3);
      paint.color = color.withValues(alpha: 0.12 + depth * 0.78);
      canvas.drawCircle(Offset(sx, sy), dotSize, paint);
    }
  }

  // Repaint is driven by the model Listenable, not by constructor identity.
  @override
  bool shouldRepaint(_SpherePainter oldDelegate) => false;
}

// ─── Debug overlay ─────────────────────────────────────────────────────────────
class _DebugOverlay extends StatelessWidget {
  const _DebugOverlay({required this.model, required this.durationMs});

  final _SphereModel model;
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        final line =
            'pos ${model.positionMs}ms / ${durationMs}ms   '
            'beat #${model.beatIndex}   '
            'amp ${model.amp.toStringAsFixed(2)}   '
            'beatP ${model.beatPulse.toStringAsFixed(2)}   '
            'enP ${model.energyPulse.toStringAsFixed(2)}';
        return Text(
          line,
          style: GoogleFonts.dmMono(
            fontSize: 10,
            color: XeneTheme.muted,
            height: 1.5,
          ),
        );
      },
    );
  }
}

// ─── Geometry + analysis helpers ───────────────────────────────────────────────
class _P3 {
  const _P3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// Evenly distribute [n] points on a unit sphere (Fibonacci spiral) so the
/// surface looks uniform with no clustering at the poles.
List<_P3> _fibonacciSphere(int n) {
  final pts = <_P3>[];
  final phi = math.pi * (3 - math.sqrt(5)); // golden angle
  for (var i = 0; i < n; i++) {
    final y = 1 - (i / (n - 1)) * 2; // 1 → -1
    final r = math.sqrt(1 - y * y);
    final theta = phi * i;
    pts.add(_P3(math.cos(theta) * r, y, math.sin(theta) * r));
  }
  return pts;
}

/// The analysis has no duration field, but the beat grid / energy events span
/// the full track, so their last timestamp is a faithful duration estimate.
int _estimateDurationMs(TrackAnalysis a) {
  var d = 0;
  if (a.beatGridMs.isNotEmpty) d = math.max(d, a.beatGridMs.last);
  if (a.energyEventsMs.isNotEmpty) d = math.max(d, a.energyEventsMs.last);
  return d;
}

/// Real amplitude (0–1) at the current playback position, indexed straight into
/// SoundCloud's waveform samples.
double _amplitudeAt(TrackAnalysis a, int posMs, int durMs) {
  if (a.amplitudeSamples.isEmpty || durMs <= 0) return 0.35;
  final frac = (posMs / durMs).clamp(0.0, 1.0);
  final idx = (frac * (a.amplitudeSamples.length - 1)).round().clamp(
    0,
    a.amplitudeSamples.length - 1,
  );
  return a.amplitudeSamples[idx].clamp(0.0, 1.0);
}
