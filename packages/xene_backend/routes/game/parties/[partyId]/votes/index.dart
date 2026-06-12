import 'dart:async';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/audit_logger.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('game.votes');

/// GET  /game/parties/:partyId/votes?week=YYYY-MM-DD
/// POST /game/parties/:partyId/votes
Future<Response> onRequest(RequestContext context, String partyId) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  switch (context.request.method) {
    case HttpMethod.get:
      return _getVotes(context, partyId);
    case HttpMethod.post:
      return _castVote(context, partyId);
    default:
      return Response(statusCode: 405);
  }
}

Future<Response> _getVotes(RequestContext context, String partyId) async {
  final userId = context.read<String>();
  final game = context.read<GameService>();
  final week =
      context.request.uri.queryParameters['week'] ??
      GameService.currentWeekStart();

  final votes = await game.getWeekVotes(partyId, week, userId);
  return Response.json(body: votes);
}

Future<Response> _castVote(RequestContext context, String partyId) async {
  final userId = context.read<String>();
  final game = context.read<GameService>();

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON'});
  }

  final votedForId = (body['voted_for_id'] as String?)?.trim() ?? '';
  if (votedForId.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'voted_for_id is required'},
    );
  }

  final week = GameService.currentWeekStart();

  try {
    final result = await game.castVote(partyId, userId, votedForId, week);
    _logger.info(
      '[votes] vote cast partyId=$partyId voter=$userId for=$votedForId',
    );
    final db = context.read<DatabaseService>();
    unawaited(
      logSecurityEvent(
        db.client,
        action: 'vote_cast',
        userId: userId,
        targetId: partyId,
        metadata: {'voted_for_id': votedForId, 'week_start': week},
      ),
    );
    return Response.json(body: result);
  } on ArgumentError catch (e) {
    return Response.json(statusCode: 400, body: {'error': e.message});
  } on StateError catch (e) {
    return Response.json(statusCode: 422, body: {'error': e.message});
  }
}
