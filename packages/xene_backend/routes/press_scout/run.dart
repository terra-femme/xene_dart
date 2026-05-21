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

  final scout = context.read<PressScoutService>();
  final presetId = context.request.uri.queryParameters['preset_id']?.trim();

  // Fire and forget — scout can take several minutes for 10 artists.
  if (presetId != null && presetId.isNotEmpty) {
    _logger.info(
      '[press_scout/run] Manual preset scout triggered for "$presetId"',
    );
    unawaited(
      scout
          .scoutArticlesForPreset(presetId)
          .then((_) {
            _logger.info(
              '[press_scout/run] Preset scout completed for "$presetId"',
            );
          })
          .catchError((Object e) {
            _logger.severe(
              '[press_scout/run] Preset scout failed for "$presetId": $e',
            );
          }),
    );
    return Response.json(
      body: {
        'status': 'started',
        'preset': presetId,
        'message':
            'Press scout running for preset "$presetId" — check server logs',
      },
    );
  }

  _logger.info('[press_scout/run] Manual full scout triggered');
  unawaited(
    scout
        .scoutArticlesForActiveArtists()
        .then((_) {
          _logger.info('[press_scout/run] Manual scout completed');
        })
        .catchError((Object e) {
          _logger.severe('[press_scout/run] Manual scout failed: $e');
        }),
  );

  return Response.json(
    body: {
      'status': 'started',
      'message':
          'Press scout running in background — check server logs for progress',
    },
  );
}
