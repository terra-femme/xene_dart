import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/analysis_service.dart';

final _logger = Logger('track.analysis');

Future<Response> onRequest(
  RequestContext context,
  String platform,
  String trackId,
) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  _logger.info('[analysis] GET platform=$platform trackId=$trackId');

  final analysis = context.read<AnalysisService>();
  final row = await analysis.getAnalysis(platform, trackId);

  if (row == null) {
    // Lazy-trigger: kick off analysis on a miss so tracks never analyzed at
    // queue-add time (history, saved, game playback) still get a row. Fire-and-
    // forget — the client polls and picks it up on a later GET. analyzeTrack is
    // idempotent (skips if stored) and in-flight de-duped, so repeated polls
    // during the analysis window won't spawn duplicate work.
    _logger.info(
      '[analysis] miss — triggering analyzeTrack platform=$platform '
      'trackId=$trackId',
    );
    unawaited(
      analysis.analyzeTrack(platform, trackId).catchError((Object e) {
        _logger.warning(
          '[analysis] lazy analyzeTrack failed trackId=$trackId: $e',
        );
      }),
    );
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {
        'error': 'Analysis not found for platform=$platform trackId=$trackId',
      },
    );
  }

  return Response.json(body: row);
}
