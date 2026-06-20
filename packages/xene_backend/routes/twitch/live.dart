import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/twitch_service.dart';

final _logger = Logger('twitch.live');

/// GET /twitch/live?logins=login1,login2,...
/// Returns which of the given Twitch logins are currently live.
/// Results are cached for 2 minutes.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final loginsParam = context.request.uri.queryParameters['logins'] ?? '';
  final logins = loginsParam
      .split(',')
      .map((l) => l.trim().toLowerCase())
      .where((l) => l.isNotEmpty)
      .toList();

  if (logins.isEmpty) {
    return Response.json(body: <dynamic>[]);
  }

  final twitch = context.read<TwitchService>();

  try {
    final streams = await twitch.getLiveStatus(logins);
    return Response.json(body: streams);
  } catch (e) {
    // Log detail server-side; return a generic message so internal error text
    // (request URLs, params) isn't disclosed to the client.
    _logger.warning('[twitch/live] getLiveStatus failed: $e');
    return Response.json(
      statusCode: 502,
      body: {'error': 'Twitch API unavailable'},
    );
  }
}
