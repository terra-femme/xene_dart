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
        _logger.info('[analysis] already analyzed trackId=$trackId — skipping');
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
      _logger.info('[analysis] SC metadata fetched status=${resp.statusCode}');
      trackData = resp.data ?? {};
    } catch (e) {
      _logger.warning('[analysis] SC track fetch failed trackId=$trackId: $e');
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

    // BPM-derived beat grid
    final beatGridMs = <int>[];
    if (bpm != null && bpm > 0 && durationMs > 0) {
      final intervalMs = (60000 / bpm).round();
      for (var t = 0; t <= durationMs; t += intervalMs) {
        beatGridMs.add(t);
      }
      _logger.info(
        '[analysis] beat grid count=${beatGridMs.length} intervalMs=$intervalMs',
      );
    }

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
