import 'dart:async';
import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/feed_cache.dart';
import 'package:xene_backend/src/services/bandcamp_service.dart';
import 'package:xene_backend/src/services/youtube_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/json_utils.dart';
import 'package:xene_backend/src/utils/url_utils.dart';

final _logger = Logger('presets.sources.id');

/// PATCH /presets/templates/{slug}/sources/{sourceId}
/// Updates platform links for the artist linked to the given source.
/// Also sets manually_verified=true — marking the artist as dev-curated.
Future<Response> onRequest(
  RequestContext context,
  String slug,
  String sourceId,
) async {
  if (context.request.method == HttpMethod.patch) {
    return _patchSource(context, slug, sourceId);
  }
  return Response(statusCode: 405);
}

Future<Response> _patchSource(
  RequestContext context,
  String slug,
  String sourceId,
) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final db = context.read<DatabaseService>();

  final profileRes = await db.client
      .from('profiles')
      .select('role')
      .eq('id', userId)
      .maybeSingle();
  if ((profileRes?['role'] as String?) != 'admin') {
    _logger.warning(
      '[presets.sources.id] Non-admin PATCH attempt userId=$userId sourceId=$sourceId',
    );
    return Response.json(statusCode: 403, body: {'error': 'Admin only'});
  }

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  final urlViolations = invalidPlatformUrls(body);
  if (urlViolations.isNotEmpty) {
    _logger.warning(
      '[presets.sources.id] Rejected disallowed URLs: $urlViolations userId=$userId',
    );
    return Response.json(
      statusCode: 422,
      body: {
        'error': 'One or more URLs point to a disallowed domain',
        'fields': urlViolations.keys.toList(),
      },
    );
  }

  const allowed = {
    'bandcamp_url',
    'youtube_url',
    'youtube_channel_id',
    'spotify_url',
    'website_url',
  };
  final patch = <String, dynamic>{
    for (final e in body.entries)
      if (allowed.contains(e.key) && e.value != null) e.key: e.value,
  };
  if (patch.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'No patchable platform link fields provided'},
    );
  }

  final source = await db.getPresetTemplateSource(sourceId);
  final artistId = source?['artist_id'] as String?;

  if (artistId == null) {
    // No linked artist row — write platform links directly to the source row.
    _logger.info(
      '[presets.sources.id] PATCH source=$sourceId (no artist) fields=${patch.keys.toList()}',
    );
    final updated = await db.updatePresetTemplateSource(sourceId, patch);
    if (updated == null) {
      return Response.json(
        statusCode: 500,
        body: {'error': 'Failed to update source'},
      );
    }
    unawaited(
      _warmNewPlatforms(
        db: db,
        bandcamp: context.read<BandcampService>(),
        youtube: context.read<YouTubeService>(),
        artist: {
          'name':
              updated['display_name'] ??
              updated['soundcloud_username'] ??
              'Unknown',
          'bandcamp_url': updated['bandcamp_url'],
          'youtube_url': updated['youtube_url'],
          'youtube_channel_id': updated['youtube_channel_id'],
        },
        patchKeys: patch.keys.toSet(),
      ),
    );
    return Response.json(body: toApiRow(updated));
  }

  // Has a linked artist row — write to artists table and mark as verified.
  patch['manually_verified'] = true;

  _logger.info(
    '[presets.sources.id] PATCH artist=$artistId fields=${patch.keys.toList()}',
  );

  final updated = await db.updateArtistAdmin(artistId, patch);
  if (updated == null) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Failed to update artist'},
    );
  }

  unawaited(
    _warmNewPlatforms(
      db: db,
      bandcamp: context.read<BandcampService>(),
      youtube: context.read<YouTubeService>(),
      artist: updated,
      patchKeys: patch.keys.toSet(),
    ),
  );

  return Response.json(body: toApiRow(updated));
}

Future<void> _warmNewPlatforms({
  required DatabaseService db,
  required BandcampService bandcamp,
  required YouTubeService youtube,
  required Map<String, dynamic> artist,
  required Set<String> patchKeys,
}) async {
  final name = artist['name'] as String? ?? 'Unknown';

  if (patchKeys.contains('bandcamp_url')) {
    final bcUrl = artist['bandcamp_url'] as String?;
    if (bcUrl != null && bcUrl.isNotEmpty) {
      _logger.info('[presets.sources.id] Warming Bandcamp feed for $name');
      try {
        await fetchWithCache(
          db,
          'bandcamp',
          name,
          Duration.zero,
          () => bandcamp.getFeed(bcUrl, name),
          cacheDays: 31,
        );
      } catch (e) {
        _logger.warning(
          '[presets.sources.id] Bandcamp warmup failed for $name: $e',
        );
      }
    }
  }

  if (patchKeys.contains('youtube_url') ||
      patchKeys.contains('youtube_channel_id')) {
    final ytChannelId = artist['youtube_channel_id'] as String?;
    final ytUrl = artist['youtube_url'] as String?;
    final ytId = (ytChannelId != null && ytChannelId.startsWith('UC'))
        ? ytChannelId
        : (ytUrl ?? ytChannelId);
    if (ytId != null && ytId.isNotEmpty) {
      _logger.info('[presets.sources.id] Warming YouTube feed for $name');
      try {
        await fetchWithCache(
          db,
          'youtube',
          name,
          Duration.zero,
          () => youtube.getVideos(ytId, name),
        );
      } catch (e) {
        _logger.warning(
          '[presets.sources.id] YouTube warmup failed for $name: $e',
        );
      }
    }
  }
}
