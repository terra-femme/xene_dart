import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';

final _logger = Logger('connections.soundcloud.disconnect');

/// DELETE /connections/soundcloud/disconnect
/// Removes the stored SC OAuth token row, effectively disconnecting the user.
/// Auth: JWT (userId injected via middleware)
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405);
  }

  final userId = context.read<String>();
  _logger.info('[disconnect] Disconnecting SC for userId=$userId');

  final db = context.read<DatabaseService>();

  try {
    await db.client
        .from('platform_connections')
        .delete()
        .eq('user_id', userId)
        .eq('platform', 'soundcloud');

    await db.deleteSystemCache('sc_following:$userId');
    _logger.info('[disconnect] SC following cache cleared for userId=$userId');

    _logger.info('[disconnect] SC connection removed for userId=$userId');
    return Response.json(body: {'disconnected': true});
  } catch (e) {
    _logger.severe('[disconnect] Error removing connection: $e');
    return Response.json(
      statusCode: 500,
      body: {'error': 'Failed to disconnect: $e'},
    );
  }
}
