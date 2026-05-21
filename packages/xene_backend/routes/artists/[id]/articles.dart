import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/database.dart';

/// GET /artists/:id/articles
/// Returns cached press articles for a specific artist.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final db = context.read<DatabaseService>();
  final articles = await db.getArtistArticles(id);
  return Response.json(body: articles);
}
