import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

/// DELETE /game/parties/:partyId/tracks/:trackId
Future<Response> onRequest(
  RequestContext context,
  String partyId,
  String trackId,
) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final game = context.read<GameService>();

  try {
    await game.deleteTrack(trackId, userId);
    return Response.json(body: {'ok': true});
  } on StateError catch (e) {
    return Response.json(statusCode: 422, body: {'error': e.message});
  }
}
