import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/bandcamp_service.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/youtube_service.dart';

final _logger = Logger('presets.sources.refresh_feed');

/// POST /presets/templates/{slug}/sources/{sourceId}/refresh_feed
///
/// Developer-only Preset Playground utility: force-refresh the linked artist's
/// feed rows for every configured platform, bypassing in-memory/API-window
/// guards that are useful during normal app traffic.
Future<Response> onRequest(
  RequestContext context,
  String slug,
  String sourceId,
) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final db = context.read<DatabaseService>();
  final source = await db.getPresetTemplateSource(sourceId);
  if (source == null) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Preset source not found'},
    );
  }

  final artist = await _resolveArtist(db, source);
  final artistName = _firstString([
    artist?['name'],
    source['display_name'],
    source['soundcloud_username'],
  ]);
  if (artistName == null || artistName.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Source is missing an artist name'},
    );
  }

  _logger.info(
    '[presets.sources.refresh_feed] Refresh requested slug=$slug '
    'source=$sourceId artist=$artistName',
  );

  final platformResults = <Map<String, dynamic>>[];
  final soundcloudUrl = _firstString([
    artist?['soundcloud_url'],
    source['soundcloud_url'],
    artist?['soundcloud_username'],
    source['soundcloud_username'],
  ]);
  if (soundcloudUrl != null && soundcloudUrl.isNotEmpty) {
    platformResults.add(
      await _refreshPlatform(
        db: db,
        artistName: artistName,
        platform: 'soundcloud',
        fetch: () => context.read<SoundCloudService>().getTracks(
          soundcloudUrl,
          artistName,
          bypassMemoryCache: true,
        ),
      ),
    );
  }

  final bandcampUrl = _firstString([
    artist?['bandcamp_url'],
    source['bandcamp_url'],
  ]);
  if (bandcampUrl != null && bandcampUrl.isNotEmpty) {
    platformResults.add(
      await _refreshPlatform(
        db: db,
        artistName: artistName,
        platform: 'bandcamp',
        fetch: () => context.read<BandcampService>().getFeed(
          bandcampUrl,
          artistName,
          bypassMemoryCache: true,
        ),
      ),
    );
  }

  final youtubeInput = _firstString([
    artist?['youtube_channel_id'],
    artist?['youtube_url'],
    source['youtube_channel_id'],
    source['youtube_url'],
  ]);
  if (youtubeInput != null && youtubeInput.isNotEmpty) {
    platformResults.add(
      await _refreshPlatform(
        db: db,
        artistName: artistName,
        platform: 'youtube',
        fetch: () =>
            context.read<YouTubeService>().getVideos(youtubeInput, artistName),
      ),
    );
  }

  if (platformResults.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Source has no refreshable platform links'},
    );
  }

  return Response.json(
    body: {
      'artist': artistName,
      'source_id': sourceId,
      'platforms': platformResults,
      'refreshed_at': DateTime.now().toUtc().toIso8601String(),
    },
  );
}

Future<Map<String, dynamic>?> _resolveArtist(
  DatabaseService db,
  Map<String, dynamic> source,
) async {
  final artistId = source['artist_id'] as String?;
  if (artistId == null || artistId.isEmpty) return null;
  return db.getArtistById(artistId);
}

Future<Map<String, dynamic>> _refreshPlatform({
  required DatabaseService db,
  required String artistName,
  required String platform,
  required Future<List<dynamic>> Function() fetch,
}) async {
  final started = DateTime.now().toUtc();
  try {
    await db.deleteFeedItemsForArtistPlatform(artistName, platform);
    await db.deleteSystemCache('last_polled:$platform:$artistName');
    await db.deleteSystemCache('feed_empty_window:$platform:$artistName:31d');

    final items = await fetch();
    await db.setLastPolled(platform, artistName);

    final windowCutoff = _cacheWindowCutoff(31);
    final windowItems = items
        .where((item) => _publishedAt(item)?.isBefore(windowCutoff) == false)
        .length;
    final newest = items
        .map(_publishedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (best, next) {
          if (best == null || next.isAfter(best)) return next;
          return best;
        });

    _logger.info(
      '[presets.sources.refresh_feed] $platform/$artistName refreshed: '
      '${items.length} fetched, $windowItems in 31d window',
    );

    return {
      'platform': platform,
      'ok': true,
      'items_fetched': items.length,
      'window_items': windowItems,
      if (newest != null) 'newest_published_at': newest.toIso8601String(),
      'elapsed_ms': DateTime.now().toUtc().difference(started).inMilliseconds,
    };
  } catch (e) {
    _logger.warning(
      '[presets.sources.refresh_feed] $platform/$artistName failed: $e',
    );
    return {
      'platform': platform,
      'ok': false,
      'error': e.toString(),
      'elapsed_ms': DateTime.now().toUtc().difference(started).inMilliseconds,
    };
  }
}

String? _firstString(Iterable<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}

DateTime _cacheWindowCutoff(int days) {
  final now = DateTime.now().toLocal();
  return DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: days)).toUtc();
}

DateTime? _publishedAt(dynamic item) {
  final value = item.publishedAt;
  if (value is DateTime) return value.toUtc();
  return null;
}
