import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/database.dart';

/// GET /connections/status?platform=soundcloud
/// Auth: JWT (userId from context, not query param)
/// Returns {"connected": true/false} — polled by the Flutter app after OAuth.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final userId = context.read<String>();
  final params = context.request.uri.queryParameters;
  final platform = params['platform'];

  if (platform == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'platform query parameter required'},
    );
  }

  final db = context.read<DatabaseService>();
  final connection = await db.getPlatformConnection(userId, platform);

  return Response.json(body: {'connected': connection != null});
}
