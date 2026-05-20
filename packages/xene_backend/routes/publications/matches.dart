import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/database.dart';

/// GET /publications/matches?preset={slug}&limit={n}
/// Resolves publication pipes for a preset using deterministic matching only.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final userId = context.request.headers['x-user-id'] ?? 'local_user';
  final params = context.request.uri.queryParameters;
  final presetSlug = params['preset']?.trim() ?? 'custom';
  final limit = int.tryParse(params['limit'] ?? '') ?? 8;

  final db = context.read<DatabaseService>();
  final matches = await db.getPublicationMatchesForPreset(
    userId,
    presetSlug,
    limit: limit.clamp(1, 25).toInt(),
  );

  return Response.json(body: matches);
}
