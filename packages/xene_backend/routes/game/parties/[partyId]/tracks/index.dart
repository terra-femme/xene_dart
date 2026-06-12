import 'dart:async';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/audit_logger.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('game.tracks');

/// GET  /game/parties/:partyId/tracks?week=YYYY-MM-DD
/// POST /game/parties/:partyId/tracks
Future<Response> onRequest(RequestContext context, String partyId) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  switch (context.request.method) {
    case HttpMethod.get:
      return _getWeeklyTracks(context, partyId);
    case HttpMethod.post:
      return _submitTrack(context, partyId);
    default:
      return Response(statusCode: 405);
  }
}

Future<Response> _getWeeklyTracks(
  RequestContext context,
  String partyId,
) async {
  final userId = context.read<String>();
  final game = context.read<GameService>();
  final week =
      context.request.uri.queryParameters['week'] ??
      GameService.currentWeekStart();

  final tracks = await game.getWeeklyTracks(partyId, week, userId);
  return Response.json(
    body: {
      'week_start': week,
      'is_week_closed': GameService.isWeekClosed(week),
      'is_results_visible': GameService.isResultsVisible(week),
      'members': tracks,
    },
  );
}

Future<Response> _submitTrack(RequestContext context, String partyId) async {
  final userId = context.read<String>();
  final game = context.read<GameService>();

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON'});
  }

  final requiredKeys = ['sc_track_id', 'sc_track_url', 'sc_title'];
  for (final k in requiredKeys) {
    if ((body[k] as String?)?.isEmpty ?? true) {
      return Response.json(statusCode: 400, body: {'error': '$k is required'});
    }
  }

  try {
    final track = await game.submitTrack(partyId, userId, body);
    _logger.info('[tracks] submitted trackId=${track['id']} partyId=$partyId');
    final db = context.read<DatabaseService>();
    unawaited(
      logSecurityEvent(
        db.client,
        action: 'track_submitted',
        userId: userId,
        targetId: partyId,
        metadata: {
          'track_id': track['id'],
          'sc_track_id': track['sc_track_id'],
          'track_type': track['track_type'],
        },
      ),
    );
    return Response.json(statusCode: 201, body: track);
  } on ArgumentError catch (e) {
    return Response.json(statusCode: 400, body: {'error': e.message});
  } on StateError catch (e) {
    return Response.json(statusCode: 422, body: {'error': e.message});
  }
}
