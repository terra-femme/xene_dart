import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('game.tracks.check');

/// GET /game/parties/:partyId/tracks/check?sc_track_id=xxx
///
/// Returns whether another party member has already submitted this track,
/// across all weeks. Used to show a confirmation dialog before submission.
///
/// Response when found:    { "found": true, "username": "...", "submitted_at": "...", "week_start": "..." }
/// Response when not found:{ "found": false }
Future<Response> onRequest(RequestContext context, String partyId) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final game = context.read<GameService>();

  final scTrackId =
      context.request.uri.queryParameters['sc_track_id']?.trim() ?? '';

  if (scTrackId.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'sc_track_id query param is required'},
    );
  }

  _logger.info('[check] partyId=$partyId userId=$userId scTrackId=$scTrackId');

  final match = await game.findTrackInParty(partyId, userId, scTrackId);
  return Response.json(body: match ?? {'found': false});
}
