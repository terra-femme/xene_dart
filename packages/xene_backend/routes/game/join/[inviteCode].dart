import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';

final _logger = Logger('game.join');

/// POST /game/join/:inviteCode
Future<Response> onRequest(RequestContext context, String inviteCode) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();

  final rateLimited = checkRateLimit(gameJoinRateLimiter, userId);
  if (rateLimited != null) return rateLimited;

  final game = context.read<GameService>();

  _logger.info('[join] userId=$userId code=$inviteCode');

  try {
    final party = await game.joinParty(userId, inviteCode);
    _logger.info('[join] joined partyId=${party['id']}');
    return Response.json(body: party);
  } on ArgumentError catch (e) {
    return Response.json(statusCode: 404, body: {'error': e.message});
  } on StateError catch (e) {
    return Response.json(statusCode: 422, body: {'error': e.message});
  }
}
