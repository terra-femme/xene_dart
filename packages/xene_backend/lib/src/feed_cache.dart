import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';
import 'database.dart';

final _logger = Logger('feed_cache');

// In-process coalescing: prevents concurrent requests from each launching an
// independent live scrape for the same platform/artist.
final _inFlight = <String, Future<List<FeedItem>>>{};

/// Check last_polled TTL. If fresh -> return from feed_items DB.
/// If stale -> serve stale rows immediately and kick off a background refresh.
/// On live-fetch failure -> serve stale cache rather than returning empty.
///
/// Mirrors feed.py :: fetch_platform_items cache logic.
Future<List<FeedItem>> fetchWithCache(
  DatabaseService db,
  String platform,
  String artistName,
  Duration ttl,
  Future<List<FeedItem>> Function() fetchLive, {
  int cacheDays = 31,
}) async {
  final lastPolled = await db.getLastPolled(platform, artistName);
  final now = DateTime.now().toUtc();
  final isFresh = lastPolled != null && now.difference(lastPolled) < ttl;

  if (isFresh) {
    final rows = await db.getCachedFeedItems(
      platform: platform,
      artistName: artistName,
      days: cacheDays,
    );
    if (rows.isNotEmpty) {
      _logger.info(
        '[feed_cache] Cache HIT $platform/$artistName - ${rows.length} rows '
        '(age=${now.difference(lastPolled).inMinutes}min / ttl=${ttl.inHours}h)',
      );
      return rows.map(feedItemFromRow).whereType<FeedItem>().toList();
    }

    final emptyWindow = await db.getSystemCache(
      _emptyWindowCacheKey(platform, artistName, cacheDays),
    );
    if (emptyWindow != null) {
      _logger.info(
        '[feed_cache] Cache HIT (verified empty) $platform/$artistName - no content in ${cacheDays}d window '
        '(age=${now.difference(lastPolled).inMinutes}min / ttl=${ttl.inHours}h)',
      );
      return [];
    }

    // Only hydrate if the last successful poll was more than 30 seconds ago.
    // This prevents rapid-fire retry loops when saveFeedItems fails non-fatally
    // (save logged, last_polled stamped, but 0 rows in DB) while keeping the
    // empty window short so users see real data quickly after cache resets.
    final secondsSincePolled = now.difference(lastPolled!).inSeconds;
    if (secondsSincePolled < 30) {
      _logger.warning(
        '[feed_cache] Cache HIT but 0 rows for $platform/$artistName — '
        'skipping hydration (polled ${secondsSincePolled}s ago, save may have failed)',
      );
      return [];
    }
    _logger.info(
      '[feed_cache] Cache HIT but 0 rows and no verified-empty marker for $platform/$artistName — fetching live to hydrate',
    );
  } else {
    // STALE: if there are rows from a previous fetch, serve them immediately
    // and kick off a background refresh so the caller isn't blocked.
    if (lastPolled != null) {
      final staleRows = await db.getCachedFeedItems(
        platform: platform,
        artistName: artistName,
        days: cacheDays,
      );
      if (staleRows.isNotEmpty) {
        _logger.info(
          '[feed_cache] Stale HIT $platform/$artistName - '
          'serving ${staleRows.length} stale rows, background refresh queued '
          '(age=${now.difference(lastPolled).inMinutes}min / ttl=${ttl.inHours}h)',
        );
        // Stamp now so concurrent requests don't stack up live fetches.
        await db.setLastPolled(platform, artistName);
        _backgroundRefresh(db, platform, artistName, fetchLive, cacheDays, ttl);
        return staleRows.map(feedItemFromRow).whereType<FeedItem>().toList();
      }
    }

    _logger.info(
      '[feed_cache] Cache MISS $platform/$artistName - fetching live',
    );
  }

  // Live fetch - coalesced so concurrent requests share one scrape.
  final inflightKey = '$platform:$artistName';
  if (_inFlight.containsKey(inflightKey)) {
    _logger.info(
      '[feed_cache] Coalescing in-flight fetch for $platform/$artistName',
    );
    return await _inFlight[inflightKey]!;
  }

  final liveWork = _runLiveFetch(
    db,
    platform,
    artistName,
    fetchLive,
    cacheDays,
    ttl,
  );
  _inFlight[inflightKey] = liveWork;
  try {
    return await liveWork;
  } finally {
    _inFlight.remove(inflightKey);
  }
}

/// Execute a live fetch, persist results, and stamp the cache markers.
Future<List<FeedItem>> _runLiveFetch(
  DatabaseService db,
  String platform,
  String artistName,
  Future<List<FeedItem>> Function() fetchLive,
  int cacheDays,
  Duration ttl,
) async {
  final now = DateTime.now().toUtc();
  try {
    final items = await fetchLive();
    await db.setLastPolled(platform, artistName);
    final cutoff = _cacheWindowCutoff(cacheDays);
    final hasWindowItems = items.any(
      (item) => item.publishedAt.isAfter(cutoff),
    );
    final emptyWindowKey = _emptyWindowCacheKey(
      platform,
      artistName,
      cacheDays,
    );
    if (hasWindowItems) {
      await db.deleteSystemCache(emptyWindowKey);
    } else {
      await db.setSystemCache(emptyWindowKey, {
        'timestamp': now.toIso8601String(),
        'reason': 'successful_live_fetch_returned_no_window_items',
      }, expiresAt: now.add(ttl));
    }
    return items;
  } catch (e) {
    _logger.severe(
      '[feed_cache] Live fetch failed for $platform/$artistName: $e',
    );
    // Serve stale cache rather than returning empty on transient failure.
    final rows = await db.getCachedFeedItems(
      platform: platform,
      artistName: artistName,
      days: cacheDays,
    );
    if (rows.isNotEmpty) {
      _logger.warning(
        '[feed_cache] Serving stale cache for $platform/$artistName after live failure (${rows.length} rows)',
      );
      return rows.map(feedItemFromRow).whereType<FeedItem>().toList();
    }
    return [];
  }
}

String _emptyWindowCacheKey(
  String platform,
  String artistName,
  int cacheDays,
) => 'feed_empty_window:$platform:$artistName:${cacheDays}d';

DateTime _cacheWindowCutoff(int days) {
  final now = DateTime.now().toLocal();
  return DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: days)).toUtc();
}

/// Fire-and-forget live refresh. Returns immediately; errors are logged only.
/// last_polled must be stamped by the caller before invoking this.
void _backgroundRefresh(
  DatabaseService db,
  String platform,
  String artistName,
  Future<List<FeedItem>> Function() fetchLive,
  int cacheDays,
  Duration ttl,
) {
  // Skip if a synchronous live fetch is already in flight for this key.
  final inflightKey = '$platform:$artistName';
  if (_inFlight.containsKey(inflightKey)) {
    _logger.fine(
      '[feed_cache] Background refresh skipped - live fetch already in flight for $platform/$artistName',
    );
    return;
  }

  Future(() async {
    try {
      _logger.fine(
        '[feed_cache] Background refresh started: $platform/$artistName',
      );
      final items = await fetchLive();
      final now = DateTime.now().toUtc();
      final cutoff = _cacheWindowCutoff(cacheDays);
      final emptyWindowKey = _emptyWindowCacheKey(
        platform,
        artistName,
        cacheDays,
      );
      if (items.any((item) => item.publishedAt.isAfter(cutoff))) {
        await db.deleteSystemCache(emptyWindowKey);
      } else {
        await db.setSystemCache(emptyWindowKey, {
          'timestamp': now.toIso8601String(),
          'reason': 'background_refresh_no_window_items',
        }, expiresAt: now.add(ttl));
      }
      _logger.info(
        '[feed_cache] Background refresh done: $platform/$artistName '
        '(${items.length} items)',
      );
    } catch (e) {
      _logger.warning(
        '[feed_cache] Background refresh failed: $platform/$artistName - $e',
      );
    }
  });
}

/// Convert a feed_items DB row (snake_case columns) to a FeedItem domain object.
FeedItem? feedItemFromRow(Map<String, dynamic> row) {
  try {
    return FeedItem(
      id: row['internal_id'] as String,
      platform: row['platform'] as String,
      artistName: row['artist_name'] as String,
      contentType: row['content_type'] as String,
      title: row['title'] as String?,
      body: row['body'] as String?,
      mediaUrl: row['media_url'] as String?,
      artworkUrl: row['artwork_url'] as String?,
      externalUrl: row['external_url'] as String,
      publishedAt: DateTime.parse(row['published_at'] as String),
      durationSeconds: row['duration_seconds'] as int?,
      playCount: row['play_count'] as int?,
      likeCount: row['like_count'] as int?,
      waveformUrl: row['waveform_url'] as String?,
      trackCount: row['track_count'] as int?,
    );
  } catch (e) {
    _logger.warning('[feed_cache] Failed to map DB row to FeedItem: $e');
    return null;
  }
}
