import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';

final _logger = Logger('presets.sources.id.articles');

/// POST /presets/templates/{slug}/sources/{sourceId}/articles
/// Saves a manually curated press article for the artist linked to this source.
Future<Response> onRequest(
  RequestContext context,
  String slug,
  String sourceId,
) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  final title = (body['title'] as String?)?.trim() ?? '';
  final url = (body['url'] as String?)?.trim() ?? '';
  if (title.isEmpty || url.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': '"title" and "url" are required'},
    );
  }

  final db = context.read<DatabaseService>();
  final source = await db.getPresetTemplateSource(sourceId);
  final artistId = source?['artist_id'] as String?;
  if (artistId == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'No linked artist for source $sourceId'},
    );
  }

  final artistName = source?['display_name'] as String?;

  _logger.info(
    '[presets.sources.id.articles] Adding article for artist=$artistId name=$artistName preset=$slug title="$title"',
  );

  final saved = await db.saveArtistArticles([
    {
      'artist_id': artistId,
      if (artistName != null && artistName.isNotEmpty)
        'artist_name': artistName,
      'title': title,
      'url': url,
      if ((body['snippet'] as String?)?.trim().isNotEmpty == true)
        'snippet': (body['snippet'] as String?)!.trim(),
      'source': body['source'],
      'published_at': body['published_at'],
      'preset_slug': slug,
    },
  ]);

  if (!saved) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Failed to save article'},
    );
  }

  _logger.info(
    '[presets.sources.id.articles] ✓ Article saved for artist=$artistId',
  );
  return Response.json(statusCode: 201, body: {'ok': true});
}
