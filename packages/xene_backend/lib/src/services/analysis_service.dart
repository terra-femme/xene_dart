import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/api_analytics_service.dart';

final _logger = Logger('analysis_service');

class AnalysisService {
  AnalysisService(this._db, {ApiAnalyticsService? analytics})
    : _dio = analytics?.trackDio(_createDio(), 'analysis') ?? _createDio();

  final DatabaseService _db;
  final Dio _dio;

  // Dedupe concurrent analyze requests for the same track. A client polling
  // GET /track/analysis during the ~10s analysis window would otherwise spawn
  // one SoundCloud fetch + upsert per poll for a single track.
  final Set<String> _inFlight = {};

  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  Future<Map<String, dynamic>?> getAnalysis(
    String platform,
    String trackId,
  ) async {
    _logger.info('[analysis] getAnalysis platform=$platform trackId=$trackId');
    try {
      return await _db.client
          .from('track_analysis')
          .select()
          .eq('track_id', trackId)
          .eq('platform', platform)
          .maybeSingle();
    } catch (e) {
      _logger.severe('[analysis] getAnalysis failed trackId=$trackId: $e');
      return null;
    }
  }

  Future<void> analyzeTrack(String platform, String trackId) async {
    _logger.info('[analysis] analyzeTrack platform=$platform trackId=$trackId');

    final inFlightKey = '$platform:$trackId';
    if (_inFlight.contains(inFlightKey)) {
      _logger.info(
        '[analysis] analyzeTrack already in flight key=$inFlightKey — skipping',
      );
      return;
    }
    _inFlight.add(inFlightKey);

    try {
      if (platform != 'soundcloud') {
        _logger.warning('[analysis] unsupported platform=$platform — skipping');
        return;
      }

      // Skip if already stored
      try {
        final existing = await _db.client
            .from('track_analysis')
            .select('analyzed_at')
            .eq('track_id', trackId)
            .eq('platform', platform)
            .maybeSingle();
        if (existing != null) {
          _logger.info(
            '[analysis] already analyzed trackId=$trackId — skipping',
          );
          return;
        }
      } catch (e) {
        _logger.warning(
          '[analysis] existence check failed trackId=$trackId: $e — continuing',
        );
      }

      final token = await _getToken();
      if (token == null) {
        _logger.warning('[analysis] no SC token — skipping trackId=$trackId');
        return;
      }

      // Fetch SC track metadata
      Map<String, dynamic> trackData;
      try {
        final resp = await _dio.get<Map<String, dynamic>>(
          'https://api-v2.soundcloud.com/tracks/$trackId',
          options: Options(headers: {'Authorization': 'OAuth $token'}),
        );
        _logger.info(
          '[analysis] SC metadata fetched status=${resp.statusCode}',
        );
        trackData = resp.data ?? {};
      } catch (e) {
        _logger.warning(
          '[analysis] SC track fetch failed trackId=$trackId: $e',
        );
        return;
      }

      final bpmRaw = trackData['bpm'];
      final bpm = bpmRaw != null ? (bpmRaw as num).toInt() : null;
      final durationMs =
          ((trackData['full_duration'] ?? trackData['duration']) as num? ?? 0)
              .toInt();
      final waveformUrl = trackData['waveform_url'] as String?;
      _logger.info(
        '[analysis] trackId=$trackId bpm=$bpm durationMs=$durationMs waveformUrl=$waveformUrl',
      );

      // Fetch waveform JSON and normalise to 0–1
      List<double> amplitudeSamples = [];
      if (waveformUrl != null) {
        final jsonUrl = waveformUrl.replaceFirst(RegExp(r'_m\.png$'), '.json');
        try {
          final wResp = await _dio.get<String>(
            jsonUrl,
            options: Options(responseType: ResponseType.plain),
          );
          final body = wResp.data ?? '';
          final previewLen = min(200, body.length);
          _logger.fine(
            '[analysis] waveform JSON preview: ${body.substring(0, previewLen)}',
          );

          final parsed = jsonDecode(body) as Map<String, dynamic>;
          final raw = (parsed['samples'] as List? ?? [])
              .map((e) => (e as num).toDouble())
              .toList();

          if (raw.isNotEmpty) {
            final maxVal = raw.reduce((a, b) => a > b ? a : b);
            amplitudeSamples = maxVal > 0
                ? raw.map((v) => v / maxVal).toList()
                : raw;
          }
          _logger.info(
            '[analysis] amplitude samples count=${amplitudeSamples.length}',
          );
        } catch (e) {
          _logger.warning(
            '[analysis] waveform fetch failed url=$waveformUrl: $e',
          );
        }
      }

      // Beat grid: prefer SoundCloud's authoritative BPM. When it's absent
      // (common for indie/underground tracks), estimate a grid from the
      // amplitude envelope so the accessibility visualizer still pulses.
      var beatGridMs = <int>[];
      var beatSource = 'none';
      if (bpm != null && bpm > 0 && durationMs > 0) {
        final intervalMs = (60000 / bpm).round();
        for (var t = 0; t <= durationMs; t += intervalMs) {
          beatGridMs.add(t);
        }
        beatSource = 'soundcloud';
      } else {
        final est = estimateBeatGrid(amplitudeSamples, durationMs);
        beatGridMs = est.beatGridMs;
        beatSource = est.source;
      }
      _logger.info(
        '[analysis] beat grid count=${beatGridMs.length} source=$beatSource',
      );

      // Energy events — amplitude samples above 75th percentile
      final energyEventsMs = <int>[];
      if (amplitudeSamples.isNotEmpty && durationMs > 0) {
        final sorted = List<double>.from(amplitudeSamples)..sort();
        final p75 = sorted[(sorted.length * 0.75).floor()];
        _logger.info('[analysis] p75 threshold=$p75');
        final msByIndex = durationMs / amplitudeSamples.length;
        for (var i = 0; i < amplitudeSamples.length; i++) {
          if (amplitudeSamples[i] > p75) {
            energyEventsMs.add((i * msByIndex).round());
          }
        }
        _logger.info('[analysis] energy events count=${energyEventsMs.length}');
      }

      // Upsert result
      try {
        await _db.client.from('track_analysis').upsert({
          'track_id': trackId,
          'platform': platform,
          if (bpm != null) 'bpm': bpm,
          'beat_grid_ms': beatGridMs,
          'amplitude_samples': amplitudeSamples,
          'energy_events_ms': energyEventsMs,
          'analyzed_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'track_id,platform');
        _logger.info('[analysis] upserted trackId=$trackId platform=$platform');
      } catch (e) {
        _logger.severe('[analysis] upsert failed trackId=$trackId: $e');
      }
    } finally {
      _inFlight.remove(inFlightKey);
    }
  }

  /// Estimates a beat grid from the amplitude envelope when SoundCloud reports
  /// no BPM. Two-stage fallback:
  ///   1. Autocorrelation of the onset-novelty function finds the dominant
  ///      tempo, then beats are placed by snapping each expected beat to the
  ///      nearest real energy peak — periodic feel WITHOUT metronome drift.
  ///      → source 'estimated'
  ///   2. If no clear periodicity, peak-pick the novelty function directly with
  ///      a minimum spacing → irregular but audio-locked beats.
  ///      → source 'onset'
  ///
  /// The SoundCloud envelope is coarse (~60–200 ms/sample), so the tempo is a
  /// ballpark, not beat-accurate. That is an accepted trade for a *felt*
  /// accessibility pulse; the energy-peak snapping is what keeps it from
  /// drifting out of phase over a long track.
  ///
  /// Pure and `static` (depends only on its arguments, no instance state) so it
  /// can be unit-tested directly without constructing the service or a DB —
  /// same testability convention as the pure helpers on `GameService`.
  static ({List<int> beatGridMs, String source}) estimateBeatGrid(
    List<double> samples,
    int durationMs,
  ) {
    final n = samples.length;
    if (n < 16 || durationMs <= 0) {
      return (beatGridMs: <int>[], source: 'none');
    }
    final msPerSample = durationMs / n;

    // Onset-novelty: rectified first difference (positive energy increases).
    final nov = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      final d = samples[i] - samples[i - 1];
      nov[i] = d > 0 ? d : 0;
    }

    // Lag window for the musical tempo range 70–180 BPM.
    final minLag = (60000 / 180 / msPerSample).round().clamp(1, n - 1).toInt();
    final maxLag = (60000 / 70 / msPerSample)
        .round()
        .clamp(minLag + 1, n - 1)
        .toInt();

    // Autocorrelation of the novelty function over the lag window.
    var bestLag = 0;
    var bestScore = 0.0;
    var scoreSum = 0.0;
    var scoreCount = 0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      var score = 0.0;
      for (var i = lag; i < n; i++) {
        score += nov[i] * nov[i - lag];
      }
      scoreSum += score;
      scoreCount++;
      if (score > bestScore) {
        bestScore = score;
        bestLag = lag;
      }
    }
    final meanScore = scoreCount > 0 ? scoreSum / scoreCount : 0.0;
    // How strongly the best lag stands out from the average lag.
    final confidence = meanScore > 0 ? bestScore / meanScore : 0.0;

    // Stage 1 — clear periodicity: build an energy-anchored grid.
    if (bestLag > 0 && confidence >= 1.8) {
      final period = bestLag;
      final tol = (period * 0.3).round().clamp(1, period).toInt();

      // Anchor on the strongest onset so the grid locks to a real downbeat.
      var anchor = 0;
      var anchorVal = 0.0;
      for (var i = 0; i < n; i++) {
        if (nov[i] > anchorVal) {
          anchorVal = nov[i];
          anchor = i;
        }
      }

      final beats = <int>{};
      final span = (n ~/ period) + 1;
      for (var k = -span; k <= span; k++) {
        final expected = anchor + k * period;
        if (expected < 0 || expected >= n) continue;
        // Snap the expected beat to the nearest local novelty peak.
        final lo = (expected - tol).clamp(0, n - 1).toInt();
        final hi = (expected + tol).clamp(0, n - 1).toInt();
        var peak = expected;
        var peakVal = nov[expected];
        for (var j = lo; j <= hi; j++) {
          if (nov[j] > peakVal) {
            peakVal = nov[j];
            peak = j;
          }
        }
        beats.add((peak * msPerSample).round());
      }

      final grid = beats.toList()..sort();
      if (grid.length >= 4) {
        final estBpm = (60000 / (period * msPerSample)).round();
        _logger.info(
          '[analysis] tempo estimate bpm≈$estBpm '
          'confidence=${confidence.toStringAsFixed(2)} beats=${grid.length}',
        );
        return (beatGridMs: grid, source: 'estimated');
      }
    }

    // Stage 2 — onset proxy: adaptive-threshold peak-picking with min spacing.
    final mean = nov.reduce((a, b) => a + b) / n;
    var variance = 0.0;
    for (final v in nov) {
      variance += (v - mean) * (v - mean);
    }
    final std = variance > 0 ? sqrt(variance / n) : 0.0;
    final threshold = mean + std;
    final minSpacing = (60000 / 180 / msPerSample)
        .round()
        .clamp(1, n - 1)
        .toInt();

    final beats = <int>[];
    var last = -minSpacing;
    for (var i = 1; i < n - 1; i++) {
      final isLocalMax = nov[i] >= nov[i - 1] && nov[i] >= nov[i + 1];
      if (nov[i] > threshold && isLocalMax && (i - last) >= minSpacing) {
        beats.add((i * msPerSample).round());
        last = i;
      }
    }
    if (beats.length >= 4) {
      _logger.info('[analysis] onset-proxy beats=${beats.length}');
      return (beatGridMs: beats, source: 'onset');
    }

    _logger.info(
      '[analysis] no reliable beat estimate (beats=${beats.length})',
    );
    return (beatGridMs: <int>[], source: 'none');
  }

  Future<String?> _getToken() async {
    // Reuses the same cache key as SoundCloudService — shared OAuth token.
    const cacheKey = 'soundcloud_client_credentials';
    try {
      final cached = await _db.getSystemCache(cacheKey);
      if (cached != null) {
        final token = cached['access_token'] as String?;
        if (token != null) {
          _logger.fine('[analysis] SC token from cache');
          return token;
        }
      }

      final clientId = Platform.environment['SC_CLIENT_ID'] ?? '';
      final clientSecret = Platform.environment['SC_CLIENT_SECRET'] ?? '';
      if (clientId.isEmpty || clientSecret.isEmpty) {
        _logger.warning('[analysis] SC_CLIENT_ID/SC_CLIENT_SECRET not set');
        return null;
      }

      final resp = await _dio.post<Map<String, dynamic>>(
        'https://secure.soundcloud.com/oauth/token',
        data: 'grant_type=client_credentials',
        options: Options(
          headers: {
            'Authorization':
                'Basic ${base64.encode(utf8.encode('$clientId:$clientSecret'))}',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );

      final tokenData = resp.data ?? {};
      final expiresIn = (tokenData['expires_in'] as num?)?.toInt() ?? 3600;
      await _db.setSystemCache(
        cacheKey,
        tokenData,
        expiresAt: DateTime.now().toUtc().add(
          Duration(seconds: expiresIn - 60),
        ),
      );
      _logger.info('[analysis] SC token fetched and cached');
      return tokenData['access_token'] as String?;
    } catch (e) {
      _logger.severe('[analysis] _getToken failed: $e');
      return null;
    }
  }
}
