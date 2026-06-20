import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';

import 'dio_provider.dart';

final _logger = Logger('track_analysis_provider');

/// How many times to re-check for analysis before giving up, and the delay
/// between checks.
///
/// Analysis is computed fire-and-forget when a track is added to the queue
/// (see `routes/user/queue/index.dart` → `AnalysisService.analyzeTrack`), so on
/// the first playback the `track_analysis` row often does not exist yet. Polling
/// on 404 lets the visualizer light up as soon as the backend finishes instead
/// of staying blank for the whole session. 6 attempts × 2s ≈ a 10s window,
/// which comfortably covers the typical SC-metadata + waveform-fetch + upsert
/// latency.
const _maxAttempts = 6;
const _pollInterval = Duration(seconds: 2);

/// Fetches pre-computed beat/amplitude analysis for a track from the backend.
///
/// Behaviour:
///   - Non-SoundCloud platforms are never analyzed server-side, so this returns
///     null immediately without a network round-trip.
///   - On 404 ("not analyzed yet") it polls up to [_maxAttempts] times, waiting
///     [_pollInterval] between attempts, then returns null. This fixes the race
///     where playback starts before the queue-add analysis has landed.
///   - Any other error returns null without retrying (no hammering).
///
/// Auto-disposes when the caller widget unmounts; the poll loop bails out on
/// dispose so stale analyses don't accumulate across track changes.
final trackAnalysisProvider = FutureProvider.family
    .autoDispose<TrackAnalysis?, (String platform, String trackId)>((
      ref,
      args,
    ) async {
      final (platform, trackId) = args;
      _logger.info('[trackAnalysis] fetch platform=$platform trackId=$trackId');

      // Only SoundCloud tracks are analyzed server-side; skip the round-trip.
      if (platform != 'soundcloud') {
        _logger.info(
          '[trackAnalysis] platform=$platform not analyzed — returning null',
        );
        return null;
      }

      final dio = ref.watch(authenticatedDioProvider);

      // Stop polling immediately if the widget unmounts mid-wait.
      var disposed = false;
      ref.onDispose(() => disposed = true);

      for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
        if (disposed) return null;
        try {
          final resp = await dio.get<Map<String, dynamic>>(
            '/track/analysis/$platform/$trackId',
          );
          _logger.info(
            '[trackAnalysis] received trackId=$trackId on attempt=$attempt',
          );
          return TrackAnalysis.fromJson(resp.data!);
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) {
            if (attempt == _maxAttempts) {
              _logger.info(
                '[trackAnalysis] still not analyzed after $attempt attempts '
                'trackId=$trackId — giving up',
              );
              return null;
            }
            _logger.fine(
              '[trackAnalysis] not ready (404) trackId=$trackId '
              'attempt=$attempt — retrying in ${_pollInterval.inSeconds}s',
            );
            await Future<void>.delayed(_pollInterval);
            continue;
          }
          _logger.warning(
            '[trackAnalysis] fetch error trackId=$trackId: ${e.message}',
          );
          return null;
        } catch (e) {
          _logger.warning(
            '[trackAnalysis] unexpected error trackId=$trackId: $e',
          );
          return null;
        }
      }
      return null;
    });
