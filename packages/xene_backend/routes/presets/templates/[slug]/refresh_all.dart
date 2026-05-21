import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/bandcamp_service.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/youtube_service.dart';

final _logger = Logger('presets.refresh_all');
final _runningRefreshes = <String>{};

/// POST /presets/templates/{slug}/refresh_all
///
/// Bulk-refreshes every enabled source in the preset:
///   • SC + YT tasks run in parallel (up to 12 concurrent)
///   • BC tasks run sequentially (rate-limit safety)
///
/// Returns aggregate summary:
/// {
///   "sources_total": N,
///   "sources_refreshed": N,
///   "by_platform": { "soundcloud": {ok, items_fetched, window_items}, ... },
///   "source_results": [ {artist, platform, ok, window_items, ...}, ... ],
///   "elapsed_ms": N,
///   "errors": ["<artist>/<platform>: <msg>", ...]
/// }
Future<Response> onRequest(RequestContext context, String slug) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final lockKey = slug.trim().toLowerCase();
  if (!_runningRefreshes.add(lockKey)) {
    _logger.info('[refresh_all] slug=$slug skipped: already running');
    return Response.json(
      statusCode: 409,
      body: {
        'slug': slug,
        'ok': false,
        'error': 'Refresh already running for preset $slug',
        'code': 'refresh_already_running',
      },
    );
  }

  try {
    return await _runRefreshAll(context, slug);
  } finally {
    _runningRefreshes.remove(lockKey);
  }
}

Future<Response> _runRefreshAll(RequestContext context, String slug) async {
  final db = context.read<DatabaseService>();
  final sources = await db.getPresetTemplateSourcesForAdmin(slug);
  if (sources.isEmpty) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'No sources found for preset $slug'},
    );
  }

  _logger.info('[refresh_all] slug=$slug total_sources=${sources.length}');
  final wallStart = DateTime.now().toUtc();

  // ── Resolve artist name + platform tasks per source ──────────────────────
  final tasks = <_RefreshTask>[];
  for (final source in sources) {
    if (source['enabled'] == false) continue;

    final artist = source['artist'] as Map<String, dynamic>?;
    final artistName = _firstString([
      artist?['name'],
      source['display_name'],
      source['soundcloud_username'],
    ]);
    if (artistName == null || artistName.isEmpty) continue;

    final scUrl = _firstString([
      artist?['soundcloud_url'],
      source['soundcloud_url'],
      artist?['soundcloud_username'],
      source['soundcloud_username'],
    ]);
    if (scUrl != null && scUrl.isNotEmpty) {
      tasks.add(
        _RefreshTask(
          artistName: artistName,
          platform: 'soundcloud',
          fetch: () => context.read<SoundCloudService>().getTracks(
            scUrl,
            artistName,
            bypassMemoryCache: true,
          ),
        ),
      );
    }

    final ytInput = _firstString([
      artist?['youtube_channel_id'],
      artist?['youtube_url'],
      source['youtube_channel_id'],
      source['youtube_url'],
    ]);
    if (ytInput != null && ytInput.isNotEmpty) {
      tasks.add(
        _RefreshTask(
          artistName: artistName,
          platform: 'youtube',
          fetch: () =>
              context.read<YouTubeService>().getVideos(ytInput, artistName),
        ),
      );
    }

    final bcUrl = _firstString([
      artist?['bandcamp_url'],
      source['bandcamp_url'],
    ]);
    if (bcUrl != null && bcUrl.isNotEmpty) {
      tasks.add(
        _RefreshTask(
          artistName: artistName,
          platform: 'bandcamp',
          isBandcamp: true,
          fetch: () => context.read<BandcampService>().getFeed(
            bcUrl,
            artistName,
            bypassMemoryCache: true,
          ),
        ),
      );
    }
  }

  if (tasks.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'No enabled sources with refreshable platform links'},
    );
  }

  // ── Batch: SC+YT parallel (concurrency=12), BC sequential ────────────────
  final nonBcTasks = tasks.where((t) => !t.isBandcamp).toList();
  final bcTasks = tasks.where((t) => t.isBandcamp).toList();

  final allResults = <Map<String, dynamic>>[];

  // SC + YT — parallel with concurrency cap of 12
  const _kConcurrency = 12;
  for (var i = 0; i < nonBcTasks.length; i += _kConcurrency) {
    final batch = nonBcTasks.skip(i).take(_kConcurrency).toList();
    final batchResults = await Future.wait(
      batch.map(
        (t) => _refreshPlatform(
          db: db,
          artistName: t.artistName,
          platform: t.platform,
          fetch: t.fetch,
        ),
      ),
    );
    allResults.addAll(batchResults);
  }

  // BC — sequential to avoid 429s
  for (final t in bcTasks) {
    allResults.add(
      await _refreshPlatform(
        db: db,
        artistName: t.artistName,
        platform: t.platform,
        fetch: t.fetch,
      ),
    );
  }

  // ── Build aggregate summary ───────────────────────────────────────────────
  final byPlatform = <String, Map<String, dynamic>>{};
  final errors = <String>[];

  for (final r in allResults) {
    final platform = r['platform'] as String;
    final ok = r['ok'] as bool;
    if (!ok) {
      errors.add('${r['artist']}/$platform: ${r['error']}');
      continue;
    }
    final agg = byPlatform.putIfAbsent(
      platform,
      () => {'ok': 0, 'items_fetched': 0, 'window_items': 0},
    );
    agg['ok'] = (agg['ok'] as int) + 1;
    agg['items_fetched'] =
        (agg['items_fetched'] as int) + (r['items_fetched'] as int? ?? 0);
    agg['window_items'] =
        (agg['window_items'] as int) + (r['window_items'] as int? ?? 0);
  }

  // Count distinct artist names — a source with SC+YT+BC is one artist, not three.
  final allArtists = tasks.map((t) => t.artistName).toSet();
  final refreshedArtists = allResults
      .where((r) => r['ok'] == true)
      .map((r) => r['artist'] as String)
      .toSet();

  _logger.info(
    '[refresh_all] slug=$slug done: ${allArtists.length} artists, '
    '${allResults.length} platform tasks, ${refreshedArtists.length} artists ok, '
    '${errors.length} errors, '
    '${DateTime.now().toUtc().difference(wallStart).inMilliseconds}ms',
  );

  return Response.json(
    body: {
      'slug': slug,
      'artists_total': allArtists.length,
      'artists_refreshed': refreshedArtists.length,
      'tasks_total': tasks.length,
      'by_platform': byPlatform,
      'source_results': allResults,
      'elapsed_ms': DateTime.now().toUtc().difference(wallStart).inMilliseconds,
      'refreshed_at': DateTime.now().toUtc().toIso8601String(),
      if (errors.isNotEmpty) 'errors': errors,
    },
  );
}

// ── Internal helpers ─────────────────────────────────────────────────────────

class _RefreshTask {
  const _RefreshTask({
    required this.artistName,
    required this.platform,
    required this.fetch,
    this.isBandcamp = false,
  });

  final String artistName;
  final String platform;
  final Future<List<dynamic>> Function() fetch;
  final bool isBandcamp;
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
      '[refresh_all] $platform/$artistName: ${items.length} fetched, '
      '$windowItems in 31d window',
    );

    return {
      'artist': artistName,
      'platform': platform,
      'ok': true,
      'items_fetched': items.length,
      'window_items': windowItems,
      if (newest != null) 'newest_published_at': newest.toIso8601String(),
      'elapsed_ms': DateTime.now().toUtc().difference(started).inMilliseconds,
    };
  } catch (e) {
    _logger.warning('[refresh_all] $platform/$artistName failed: $e');
    return {
      'artist': artistName,
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
