import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';

final _logger = Logger('presets/magazine-cover');

/// GET /presets/magazine-cover
/// Returns the currently active magazine cover for the editorial feed,
/// or 204 No Content when no cover is configured.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final userId = context.read<String>();
  _logger.info('[magazine-cover] userId=$userId');

  final db = context.read<DatabaseService>();
  final cover = await db.getActiveMagazineCover();

  if (cover == null) {
    _logger.info('[magazine-cover] No active cover found');
    return Response(statusCode: 204);
  }

  _logger.info(
    '[magazine-cover] Returning cover id=${cover['id']} title=${cover['title']}',
  );
  return Response.json(body: cover);
}
