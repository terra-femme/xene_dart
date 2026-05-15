import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';

final _logger = Logger('presets/articles');

/// GET /presets/articles?preset={slug}&limit={n}
/// Returns press articles for the artists in the given preset.
/// Uses getArtistsForPreset so both template and custom presets are supported.
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

  final params = context.request.uri.queryParameters;
  final presetSlug = params['preset']?.trim() ?? 'custom';
  final limit = int.tryParse(params['limit'] ?? '') ?? 12;

  _logger.info(
    '[presets/articles] userId=$userId preset=$presetSlug limit=$limit',
  );

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
    '[presets/articles] Returning ${articles.length} articles spread across ${artistIds.length} artists for preset=$presetSlug',
  );
  return Response.json(body: articles);
}
