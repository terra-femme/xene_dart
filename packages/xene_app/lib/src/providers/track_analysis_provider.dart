import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';

import 'dio_provider.dart';

final _logger = Logger('track_analysis_provider');

/// Fetches pre-computed beat/amplitude analysis for a track from the backend.
///
/// Returns null when the track has not yet been analyzed (404) or the platform
/// is not SoundCloud. Auto-disposes when the caller widget unmounts so stale
/// analyses don't accumulate across track changes.
final trackAnalysisProvider = FutureProvider.family
    .autoDispose<TrackAnalysis?, (String platform, String trackId)>((
      ref,
      args,
    ) async {
      final (platform, trackId) = args;
      _logger.info('[trackAnalysis] fetch platform=$platform trackId=$trackId');

      final dio = ref.watch(authenticatedDioProvider);
      try {
        final resp = await dio.get<Map<String, dynamic>>(
          '/track/analysis/$platform/$trackId',
        );
        _logger.info('[trackAnalysis] received trackId=$trackId');
        return TrackAnalysis.fromJson(resp.data!);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          _logger.info('[trackAnalysis] not yet analyzed trackId=$trackId');
          return null;
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
    });
