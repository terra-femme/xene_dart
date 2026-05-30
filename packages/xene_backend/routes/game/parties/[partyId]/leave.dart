import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

/// DELETE /game/parties/:partyId/leave
Future<Response> onRequest(RequestContext context, String partyId) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final game = context.read<GameService>();
  await game.leaveParty(partyId, userId);

  return Response.json(body: {'ok': true});
}
