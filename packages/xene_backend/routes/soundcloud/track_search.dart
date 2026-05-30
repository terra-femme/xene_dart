import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('soundcloud.track_search');

/// GET /soundcloud/track_search?q={query}
/// Searches SoundCloud tracks by title/artist.
/// Returns up to 10 results shaped for party track submission.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final q = context.request.uri.queryParameters['q']?.trim() ?? '';
  if (q.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Query param "q" is required'},
    );
  }

  _logger.info('[track_search] q="$q"');
  final soundcloud = context.read<SoundCloudService>();
  final results = await soundcloud.searchTracks(q);

  _logger.info('[track_search] Returning ${results.length} tracks for "$q"');
  return Response.json(body: {'collection': results, 'query': q});
}
