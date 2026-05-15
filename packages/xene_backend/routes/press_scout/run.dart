import 'dart:async';
import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/press_scout_service.dart';

final _logger = Logger('press_scout/run');

/// POST /press-scout/run
/// Manually triggers a full press scout run immediately.
/// Useful during development when you don't want to wait for the 12-hour cron.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  _logger.info('[press_scout/run] Manual scout triggered');

  final scout = context.read<PressScoutService>();

  // Fire and forget — don't block the HTTP response.
  // The scout can take several minutes for 10 artists.
  unawaited(scout.scoutArticlesForActiveArtists().then((_) {
    _logger.info('[press_scout/run] Manual scout completed');
  }).catchError((Object e) {
    _logger.severe('[press_scout/run] Manual scout failed: $e');
  }));

  return Response.json(
    body: {
      'status': 'started',
      'message': 'Press scout running in background — check server logs for progress',
    },
  );
}
