import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

/// GET /game/parties/:partyId/scores — all-time leaderboard
Future<Response> onRequest(RequestContext context, String partyId) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final game = context.read<GameService>();
  final leaderboard = await game.getLeaderboard(partyId, userId);

  return Response.json(body: leaderboard);
}
