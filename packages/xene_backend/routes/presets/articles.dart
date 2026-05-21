import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/repositories/publication_repository.dart';

final _logger = Logger('presets/articles');

/// GET /presets/articles?preset={slug}&limit={n}
/// For preset='custom': returns recent publication_articles from all enabled
/// press publications (editorial feed).
/// For all other presets: returns artist press articles spread across the
/// preset's artist roster.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final userId = context.read<String>();

  final params = context.request.uri.queryParameters;
  final presetSlug = params['preset']?.trim() ?? 'custom';
  final limit = int.tryParse(params['limit'] ?? '') ?? 12;

  _logger.info(
    '[presets/articles] userId=$userId preset=$presetSlug limit=$limit',
  );

  if (presetSlug == 'custom') {
    return _publicationArticles(context, limit);
  }
  return _artistArticles(context, userId, presetSlug, limit);
}

Future<Response> _publicationArticles(RequestContext context, int limit) async {
  final repo = context.read<PublicationRepository>();
  final pubs = await repo.getEnabledPublications();
  final pubIds = pubs.map((p) => p['id'] as String).toList();

  _logger.info(
    '[presets/articles] custom slot — fetching from ${pubIds.length} publications',
  );

  if (pubIds.isEmpty) {
    return Response.json(body: <dynamic>[]);
  }

  final rows = await repo.getArticlesForPublications(pubIds, limit: limit);
  _logger.info(
    '[presets/articles] custom slot — ${rows.length} publication articles',
  );

  final result = rows.map((a) {
    final pub = a['press_publications'] as Map<String, dynamic>?;
    return {
      'title': a['title'] ?? '',
      'url': a['url'] ?? '',
      'snippet': a['snippet'] ?? '',
      'source': pub?['name'],
      'published_at': a['published_at'],
    };
  }).toList();

  return Response.json(body: result);
}

Future<Response> _artistArticles(
  RequestContext context,
  String userId,
  String presetSlug,
  int limit,
) async {
  final db = context.read<DatabaseService>();

  final artists = await db.getArtistsForPreset(userId, presetSlug);
  if (artists.isEmpty) {
    _logger.warning(
      '[presets/articles] No artists resolved for preset=$presetSlug',
    );
    return Response.json(body: <dynamic>[]);
  }

  final artistIds = artists
      .map((a) => a['id'] as String?)
      .whereType<String>()
      .toList();

  _logger.info(
    '[presets/articles] ${artistIds.length} artist IDs for preset=$presetSlug',
  );

  if (artistIds.isEmpty) {
    _logger.warning(
      '[presets/articles] Artists had no id fields for preset=$presetSlug',
    );
    return Response.json(body: <dynamic>[]);
  }

  final articles = await db.getSpreadArtistArticles(
    artistIds,
    totalLimit: limit,
    perArtist: 3,
  );
  _logger.info(
    '[presets/articles] ${articles.length} articles for ${artistIds.length} artists preset=$presetSlug',
  );
  return Response.json(body: articles);
}
