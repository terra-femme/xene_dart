import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('game.scene');

/// GET /game/scene?week=YYYY-MM-DD
///
/// Returns the active scene text for the given week.
/// Response: { "text": "IN A DARK FOGGY CLUB..." } or { "text": null } if unset.
///
/// The scene is global — every party sees the same scene for a given week.
/// Admin sets the scene via the dashboard (POST to game_week_scenes in Supabase).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final game = context.read<GameService>();
  final week =
      context.request.uri.queryParameters['week']?.trim() ??
      GameService.currentWeekStart();

  _logger.info('[scene] fetching scene for week=$week');

  final text = await game.getWeekScene(week);
  return Response.json(body: {'text': text});
}
