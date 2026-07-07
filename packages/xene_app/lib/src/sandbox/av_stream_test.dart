import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';

import '../providers/dio_provider.dart';
import '../theme/xene_theme.dart';
import 'av_cors_probe.dart';

final _logger = Logger('av_stream_test');

/// Step-0 viability test for the **no-iframe** AV pipeline.
///
/// This is a throwaway diagnostic, NOT the real feature. It exists to answer
/// the open questions before we build the full "feel the music" page:
///
///   1. **Sourcing** — does the backend resolve an official MP3 stream URL for a
///      given track?  `GET /soundcloud/stream/{id}` → `{ "stream_url": ... }`
///   2. **Playback** — does `just_audio` actually PLAY that URL on the current
///      platform (esp. the web build — no CORS / format wall)?
///   3. **Live-FFT CORS** — can Web Audio READ that stream for real-time FFT?
///      The Dancing Points visual reacts via `AnalyserNode`, which only sees
///      real signal if the stream is CORS-readable. A SoundCloud CDN stream can
///      PLAY fine yet feed the analyser silence (cross-origin, no CORS headers).
///      The PROBE FFT button measures the peak RMS Web Audio actually sees.
///
/// It plays audio with **no SoundCloud iframe**, and surfaces the player state +
/// live position. That position is the clock that will later drive the visuals
/// and haptics — so if it ticks here, the whole pipeline is viable.
class AvStreamTest extends ConsumerStatefulWidget {
  const AvStreamTest({super.key});

  @override
  ConsumerState<AvStreamTest> createState() => _AvStreamTestState();
}

class _AvStreamTestState extends ConsumerState<AvStreamTest> {
  final _controller = TextEditingController();
  final _player = AudioPlayer();

  final _subs = <StreamSubscription<dynamic>>[];

  bool _resolving = false;
  bool _searching = false;
  List<Map<String, dynamic>> _results = [];
  String? _nowPlayingLabel;
  String? _streamUrl;
  String? _error;
  Duration _position = Duration.zero;
  Duration? _duration;
  ProcessingState _processing = ProcessingState.idle;
  bool _playing = false;

  // CORS-for-FFT probe state (the live-FFT viability check).
  bool _probing = false;
  CorsProbeResult? _cors;

  @override
  void initState() {
    super.initState();
    // Player state → drives the on-screen status so you can see buffering/ready/
    // playing/completed without reading the console.
    _subs.add(
      _player.playerStateStream.listen((s) {
        if (!mounted) return;
        setState(() {
          _processing = s.processingState;
          _playing = s.playing;
        });
        _logger.info(
          '[avStreamTest] playerState playing=${s.playing} '
          'processing=${s.processingState}',
        );
      }),
    );
    // Position stream — THE clock. If this ticks, visuals/haptics can ride it.
    _subs.add(
      _player.positionStream.listen((p) {
        if (!mounted) return;
        setState(() => _position = p);
      }),
    );
    _subs.add(
      _player.durationStream.listen((d) {
        if (!mounted) return;
        setState(() => _duration = d);
        _logger.info('[avStreamTest] duration=$d');
      }),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Search SoundCloud's catalog by words (artist/title), e.g.
  /// "alina baraz - alone with you". Populates the tappable results list; the
  /// chosen result's numeric id then feeds the existing resolve-and-play flow.
  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(
        () => _error = 'Enter a search, e.g. "alina baraz - alone with you".',
      );
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });
    final dio = ref.read(authenticatedDioProvider);
    try {
      _logger.info('[avStreamTest] GET /soundcloud/track_search?q="$q"');
      final resp = await dio.get<Map<String, dynamic>>(
        '/soundcloud/track_search',
        queryParameters: {'q': q},
      );
      final collection = (resp.data?['collection'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      _logger.info(
        '[avStreamTest] search "$q" -> ${collection.length} results',
      );
      setState(() {
        _results = collection;
        if (collection.isEmpty) _error = 'No SoundCloud tracks matched "$q".';
      });
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      _logger.warning(
        '[avStreamTest] search failed status=$code: ${e.message}',
      );
      setState(() {
        _error = switch (code) {
          401 => 'Unauthorized — sign in with a real account first.',
          400 => 'Empty query.',
          _ => 'Search error (status=$code): ${e.message}',
        };
      });
    } catch (e) {
      _logger.warning('[avStreamTest] search error: $e');
      setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Resolve a chosen track's official MP3 URL from the backend, then hand it to
  /// just_audio.
  Future<void> _resolveAndPlay(String id, {String? label}) async {
    _logger.info('[avStreamTest] resolveAndPlay requested trackId="$id"');

    if (int.tryParse(id) == null) {
      setState(() => _error = 'Track id must be numeric (the SoundCloud id).');
      return;
    }

    setState(() {
      _resolving = true;
      _error = null;
      _streamUrl = null;
      _nowPlayingLabel = label;
    });

    final dio = ref.read(authenticatedDioProvider);
    try {
      _logger.info('[avStreamTest] GET /soundcloud/stream/$id');
      final resp = await dio.get<Map<String, dynamic>>(
        '/soundcloud/stream/$id',
      );
      final url = resp.data?['stream_url'] as String?;
      if (url == null || url.isEmpty) {
        _logger.warning('[avStreamTest] empty stream_url for trackId=$id');
        setState(() => _error = 'Backend returned no stream_url.');
        return;
      }
      _logger.info(
        '[avStreamTest] resolved stream_url len=${url.length} for trackId=$id',
      );
      setState(() => _streamUrl = url);

      // The actual playback attempt — this is the CORS / format moment of truth.
      _logger.info('[avStreamTest] just_audio setUrl + play');
      await _player.setUrl(url);
      await _player.play();
      _logger.info('[avStreamTest] play() returned (audio should be audible)');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      _logger.warning(
        '[avStreamTest] resolve failed status=$code: ${e.message}',
      );
      setState(() {
        _error = switch (code) {
          404 =>
            'Not API-streamable (SoundCloud exposes no MP3 for this track).',
          401 => 'Unauthorized — sign in with a real account first.',
          400 => 'Invalid track id.',
          _ => 'Resolve error (status=$code): ${e.message}',
        };
      });
    } catch (e) {
      // just_audio throws here on a playback/format/CORS failure.
      _logger.warning('[avStreamTest] playback error: $e');
      setState(() => _error = 'Playback failed (CORS/format?): $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  /// Probe whether Web Audio can read the resolved stream for live FFT.
  /// Plays a throwaway `<audio crossorigin>` + AnalyserNode for ~2.5s and
  /// reports the peak RMS the analyser actually saw. (Pause just_audio first so
  /// you don't hear it twice.)
  Future<void> _probeCors() async {
    final url = _streamUrl;
    if (url == null) return;
    _logger.info('[avStreamTest] CORS-for-FFT probe starting');
    await _player.pause();
    setState(() {
      _probing = true;
      _cors = null;
    });
    final result = await probeCorsForFft(url);
    _logger.info(
      '[avStreamTest] CORS probe ok=${result.ok} maxRms=${result.maxRms} '
      'played=${result.played} samples=${result.samples} error=${result.error}',
    );
    if (mounted) {
      setState(() {
        _probing = false;
        _cors = result;
      });
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// One-line verdict for the probe result.
  (String, Color) _corsVerdict(CorsProbeResult r) {
    if (r.ok) {
      return (
        '✅ Live FFT WORKS — Web Audio read real signal (peak RMS '
            '${r.maxRms.toStringAsFixed(4)}). Dancing Points can react live.',
        XeneTheme.teal,
      );
    }
    if (r.played && r.error == null) {
      return (
        '⚠️ Plays but FFT is SILENT (peak RMS ${r.maxRms.toStringAsFixed(4)}). '
            'Stream is cross-origin without CORS headers → need a same-origin '
            'proxy or the precomputed-analysis fallback.',
        XeneTheme.orange,
      );
    }
    return (
      '❌ Could not read for FFT: ${r.error ?? "unknown"}',
      XeneTheme.orange,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'STEP-0 — no-iframe stream playback test',
            style: GoogleFonts.teko(fontSize: 22, letterSpacing: 1),
          ),
          const SizedBox(height: 6),
          Text(
            'Search SoundCloud, tap a result, and confirm (1) the backend '
            'resolves its official MP3 URL and (2) just_audio plays it with no '
            'iframe. If audio is audible and POSITION ticks below, the pipeline '
            'is viable.',
            style: GoogleFonts.dmMono(
              fontSize: 11,
              height: 1.6,
              color: XeneTheme.muted,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: GoogleFonts.dmMono(fontSize: 13),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText:
                        'Search SoundCloud, e.g. alina baraz - alone with you',
                    hintStyle: GoogleFonts.dmMono(
                      fontSize: 11,
                      color: XeneTheme.muted,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'SEARCH',
                          style: GoogleFonts.teko(letterSpacing: 1),
                        ),
                ),
              ),
            ],
          ),

          // ── Search results ──────────────────────────────────────────────
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._results.map((t) {
              final id = t['id'] as String? ?? '';
              final title = t['title'] as String? ?? 'Unknown';
              final user = t['username'] as String? ?? 'Unknown';
              final art = t['artwork_url'] as String?;
              final dur = t['duration_seconds'] as int? ?? 0;
              final label = '$user — $title';
              return _ResultRow(
                title: title,
                username: user,
                artworkUrl: art,
                durationSeconds: dur,
                busy: _resolving && _nowPlayingLabel == label,
                onTap: id.isEmpty
                    ? null
                    : () => _resolveAndPlay(id, label: label),
              );
            }),
          ],

          const SizedBox(height: 16),

          // ── Transport ───────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 34,
                icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle),
                color: XeneTheme.teal,
                onPressed: _streamUrl == null
                    ? null
                    : () => _playing ? _player.pause() : _player.play(),
              ),
              const SizedBox(width: 12),
              IconButton(
                iconSize: 28,
                icon: const Icon(Icons.stop_circle_outlined),
                color: XeneTheme.muted,
                onPressed: _streamUrl == null ? null : () => _player.stop(),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Live-FFT CORS probe ─────────────────────────────────────────
          SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              onPressed: (_streamUrl == null || _probing) ? null : _probeCors,
              icon: _probing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.graphic_eq, size: 18),
              label: Text(
                _probing ? 'PROBING…' : 'PROBE FFT (CORS)',
                style: GoogleFonts.teko(letterSpacing: 1),
              ),
            ),
          ),
          if (_cors != null) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (_) {
                final (msg, color) = _corsVerdict(_cors!);
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color),
                  ),
                  child: Text(
                    msg,
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      height: 1.5,
                      color: color,
                    ),
                  ),
                );
              },
            ),
          ],

          const SizedBox(height: 14),

          // ── Live diagnostics ────────────────────────────────────────────
          _kv('TRACK', _nowPlayingLabel ?? '—'),
          _kv('PROCESSING', _processing.name),
          _kv('PLAYING', _playing.toString()),
          _kv(
            'POSITION',
            '${_fmt(_position)}  (${_position.inMilliseconds} ms)',
          ),
          _kv('DURATION', _duration == null ? '—' : _fmt(_duration!)),
          _kv(
            'STREAM URL',
            _streamUrl == null
                ? '—'
                : '${_streamUrl!.substring(0, _streamUrl!.length.clamp(0, 64))}…',
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: XeneTheme.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: XeneTheme.orange),
              ),
              child: Text(
                _error!,
                style: GoogleFonts.dmMono(
                  fontSize: 11,
                  height: 1.5,
                  color: XeneTheme.orange,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            k,
            style: GoogleFonts.dmMono(
              fontSize: 10,
              color: XeneTheme.muted,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: GoogleFonts.dmMono(fontSize: 11, color: Colors.black),
          ),
        ),
      ],
    ),
  );
}

/// A single SoundCloud search result — artwork, title, artist + duration, and a
/// play affordance. Tapping resolves its stream and plays it.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.title,
    required this.username,
    required this.artworkUrl,
    required this.durationSeconds,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final String username;
  final String? artworkUrl;
  final int durationSeconds;
  final bool busy;
  final VoidCallback? onTap;

  String get _dur {
    final m = (durationSeconds ~/ 60).toString();
    final s = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: (artworkUrl != null && artworkUrl!.isNotEmpty)
                  ? Image.network(
                      artworkUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _ArtPlaceholder(),
                    )
                  : const _ArtPlaceholder(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$username · $_dur',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      color: XeneTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.play_circle_outline,
                    color: XeneTheme.teal,
                    size: 24,
                  ),
          ],
        ),
      ),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    color: const Color(0xFFE0E0E0),
    child: const Icon(Icons.music_note, size: 18, color: Color(0xFF999999)),
  );
}
