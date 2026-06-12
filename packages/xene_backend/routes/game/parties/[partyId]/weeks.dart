import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('game.weeks');

/// GET /game/parties/:partyId/weeks
///
/// Returns all distinct past week_start values (YYYY-MM-DD) for this party
/// that have at least one track, ordered most-recent first.
/// Excludes the current week — use the tracks endpoint for that.
Future<Response> onRequest(RequestContext context, String partyId) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final game = context.read<GameService>();

  _logger.info('[weeks] partyId=$partyId userId=$userId');

  final weeks = await game.getPartyWeeks(partyId, userId);
  return Response.json(body: weeks);
}
