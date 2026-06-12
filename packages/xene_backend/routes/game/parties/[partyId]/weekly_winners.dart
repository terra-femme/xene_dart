import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('game.parties.weekly_winners');

/// GET /game/parties/:partyId/weekly_winners
///
/// Returns one entry per closed + results-visible week for this party:
///   [{ "week_start": "YYYY-MM-DD", "winner_user_id": "...", "winner_username": "..." }, ...]
///
/// Used by the monthly progress widget on the party screen.
Future<Response> onRequest(RequestContext context, String partyId) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final game = context.read<GameService>();

  _logger.info('[weekly_winners] partyId=$partyId user=$userId');

  final winners = await game.getWeeklyWinners(partyId, userId);
  return Response.json(body: winners);
}
