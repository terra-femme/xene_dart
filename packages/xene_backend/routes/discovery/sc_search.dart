import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';

final _logger = Logger('discovery.sc_search');

/// GET /discovery/sc-search?q={query}
/// Searches SoundCloud users by name — the source-of-truth lookup before LLM discovery.
/// Returns SC user profiles in the same shape as /connections/soundcloud/following candidates.
/// Does NOT call the LLM or write to the database.
/// Anonymous users are allowed — searching is read-only. Real-user gate is on save_discovery.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final userId = context.read<String>();
  final rateLimited = checkRateLimit(discoveryRateLimiter, userId);
  if (rateLimited != null) return rateLimited;

  final query = context.request.uri.queryParameters['q']?.trim() ?? '';
  if (query.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Query param "q" is required'},
    );
  }

  _logger.info('[sc_search] q="$query"');
  final soundcloud = context.read<SoundCloudService>();

  final results = await soundcloud.searchUsers(query);

  // Map to the same candidate shape used by the following endpoint
  final candidates = results
      .map(
        (u) => {
          'name': (u['username'] as String?) ?? 'Unknown',
          'soundcloud_username': u['permalink'] as String?,
          'soundcloud_url': u['permalink_url'] as String?,
          'avatar_url': u['avatar_url'] as String?,
          'followers_count': u['followers_count'] as int? ?? 0,
          'description': u['description'] as String?,
        },
      )
      .where((c) => c['soundcloud_username'] != null)
      .toList();

  // Annotate each candidate with the preset(s) it is already a source in, so
  // the playground can show an "already added" badge. One DB round trip for the
  // whole result set; failures are swallowed inside the DB helper so search
  // still returns even if the lookup fails.
  final db = context.read<DatabaseService>();
  final usernames = candidates
      .map((c) => c['soundcloud_username'] as String?)
      .whereType<String>()
      .toList();
  final presetsByUsername = await db.getPresetsForSoundCloudUsernames(
    usernames,
  );
  for (final candidate in candidates) {
    final username = candidate['soundcloud_username'] as String?;
    candidate['in_presets'] = username == null
        ? const <Map<String, String>>[]
        : (presetsByUsername[username] ?? const <Map<String, String>>[]);
  }

  _logger.info(
    '[sc_search] Returning ${candidates.length} candidates for "$query" '
    '(${presetsByUsername.length} already in a preset)',
  );

  return Response.json(
    body: {
      'collection': candidates,
      'query': query,
      'total_count': candidates.length,
    },
  );
}
