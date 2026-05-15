import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/database.dart';

/// GET /artists/articles
/// Returns all press articles for the user's current follow list.
/// Only articles for artists currently followed are returned — articles for
/// removed artists are retained in the DB (flashback feature) but filtered here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final userId = context.request.headers['x-user-id'];
  if (userId == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'X-User-Id header required'},
    );
  }

  final limitStr = context.request.uri.queryParameters['limit'];
  final limit = int.tryParse(limitStr ?? '') ?? 15;

  final db = context.read<DatabaseService>();

  // 1. Get user's current artist IDs
  final artists = await db.getArtists(userId);
  if (artists.isEmpty) {
    return Response.json(body: <dynamic>[]);
  }

  final artistIds = artists.map((a) => a['id'] as String).toList();

  // 2. Fetch articles only for those artists
  final articles = await db.getAllArtistArticles(artistIds, limit: limit);
  return Response.json(body: articles);
}
