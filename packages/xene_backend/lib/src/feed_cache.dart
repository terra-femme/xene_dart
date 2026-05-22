import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';
import 'database.dart';

final _logger = Logger('feed_cache');

// In-process coalescing: prevents concurrent requests from each launching an
// independent live scrape for the same platform/artist.
final _inFlight = <String, Future<List<FeedItem>>>{};

final _random = Random();

// Bandcamp background-refresh concurrency cap.
// At ~2,000 unique BC artists, all going stale simultaneously (cold start /
// overnight idle) would otherwise fire 2,000 concurrent scrapes from one IP.
// This semaphore limits how many background BC scrapes run at the same time.
const _kBcBackgroundMaxConcurrent = 3;
final _bcBackgroundSemaphore = _Semaphore(_kBcBackgroundMaxConcurrent);

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
  bool backgroundOnMiss = false,
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
    final secondsSincePolled = now.difference(lastPolled).inSeconds;
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

    _logger.info('[feed_cache] Cache MISS $platform/$artistName');
  }

  // Live fetch - coalesced so concurrent requests share one scrape.
  final inflightKey = '$platform:$artistName';
  if (_inFlight.containsKey(inflightKey)) {
    _logger.info(
      '[feed_cache] Coalescing in-flight fetch for $platform/$artistName',
    );
    return await _inFlight[inflightKey]!;
  }

  final leaseKey = _refreshLeaseCacheKey(platform, artistName);
  final leaseOwner = await db.tryClaimSystemCacheLease(
    leaseKey,
    ttl: _refreshLeaseTtl(platform),
    metadata: {
      'platform': platform,
      'artist_name': artistName,
      'cache_days': cacheDays,
      'background_on_miss': backgroundOnMiss,
    },
  );
  if (leaseOwner == null) {
    final rows = await db.getCachedFeedItems(
      platform: platform,
      artistName: artistName,
      days: cacheDays,
    );
    if (rows.isNotEmpty) {
      _logger.info(
        '[feed_cache] Refresh lease BUSY $platform/$artistName - serving ${rows.length} cached rows',
      );
      return rows.map(feedItemFromRow).whereType<FeedItem>().toList();
    }
    _logger.info(
      '[feed_cache] Refresh lease BUSY $platform/$artistName - no cached rows, returning empty',
    );
    return [];
  }

  _logger.info(
    '[feed_cache] Refresh lease CLAIMED $platform/$artistName '
    'ttl=${_refreshLeaseTtl(platform).inSeconds}s backgroundOnMiss=$backgroundOnMiss',
  );

  if (backgroundOnMiss) {
    _backgroundRefresh(
      db,
      platform,
      artistName,
      fetchLive,
      cacheDays,
      ttl,
      leaseKey: leaseKey,
      leaseOwner: leaseOwner,
      releaseLease: true,
    );
    return [];
  }

  final liveWork = _runLiveFetch(
    db,
    platform,
    artistName,
    fetchLive,
    cacheDays,
    ttl,
    leaseKey: leaseKey,
    leaseOwner: leaseOwner,
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
  Duration ttl, {
  String? leaseKey,
  String? leaseOwner,
}) async {
  final now = DateTime.now().toUtc();
  var completed = false;
  try {
    final items = await fetchLive();
    await db.setLastPolled(
      platform,
      artistName,
      at: DateTime.now().toUtc().subtract(_jitterFor(platform)),
    );
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
    completed = true;
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
  } finally {
    if (completed && leaseKey != null && leaseOwner != null) {
      await db.releaseSystemCacheLease(leaseKey, leaseOwner);
      _logger.info('[feed_cache] Refresh lease RELEASED $platform/$artistName');
    } else if (leaseKey != null && leaseOwner != null) {
      _logger.warning(
        '[feed_cache] Refresh lease RETAINED $platform/$artistName until expiry after failed live fetch',
      );
    }
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
  Duration ttl, {
  String? leaseKey,
  String? leaseOwner,
  bool releaseLease = false,
}) {
  // Skip if a synchronous live fetch is already in flight for this key.
  final inflightKey = '$platform:$artistName';
  if (_inFlight.containsKey(inflightKey)) {
    _logger.fine(
      '[feed_cache] Background refresh skipped - live fetch already in flight for $platform/$artistName',
    );
    return;
  }

  Future(() async {
    var claimedHere = false;
    var completed = false;
    var bcSemaphoreAcquired = false;
    try {
      if (leaseKey == null || leaseOwner == null) {
        final claimKey = _refreshLeaseCacheKey(platform, artistName);
        final owner = await db.tryClaimSystemCacheLease(
          claimKey,
          ttl: _refreshLeaseTtl(platform),
          metadata: {
            'platform': platform,
            'artist_name': artistName,
            'cache_days': cacheDays,
            'background': true,
          },
        );
        if (owner == null) {
          _logger.info(
            '[feed_cache] Refresh lease BUSY $platform/$artistName - background refresh skipped',
          );
          return;
        }
        leaseKey = claimKey;
        leaseOwner = owner;
        claimedHere = true;
        releaseLease = true;
        _logger.info(
          '[feed_cache] Refresh lease CLAIMED $platform/$artistName '
          'ttl=${_refreshLeaseTtl(platform).inSeconds}s background=true',
        );
      }
      _logger.fine(
        '[feed_cache] Background refresh started: $platform/$artistName',
      );
      if (platform == 'bandcamp') {
        await _bcBackgroundSemaphore.acquire();
        bcSemaphoreAcquired = true;
        _logger.fine(
          '[feed_cache] BC background semaphore acquired: $artistName',
        );
      }
      final items = await fetchLive();
      await db.setLastPolled(
        platform,
        artistName,
        at: DateTime.now().toUtc().subtract(_jitterFor(platform)),
      );
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
      completed = true;
    } catch (e) {
      _logger.warning(
        '[feed_cache] Background refresh failed: $platform/$artistName - $e',
      );
    } finally {
      if (bcSemaphoreAcquired) {
        _bcBackgroundSemaphore.release();
        _logger.fine(
          '[feed_cache] BC background semaphore released: $artistName',
        );
      }
      if (completed && releaseLease && leaseKey != null && leaseOwner != null) {
        await db.releaseSystemCacheLease(leaseKey!, leaseOwner!);
        _logger.info(
          '[feed_cache] Refresh lease RELEASED $platform/$artistName '
          'background=${claimedHere || releaseLease}',
        );
      } else if (releaseLease && leaseKey != null && leaseOwner != null) {
        _logger.warning(
          '[feed_cache] Refresh lease RETAINED $platform/$artistName until expiry after failed background refresh',
        );
      }
    }
  });
}

String _refreshLeaseCacheKey(String platform, String artistName) =>
    'feed_refresh_lock:$platform:$artistName';

Duration _refreshLeaseTtl(String platform) {
  switch (platform) {
    case 'bandcamp':
      return const Duration(minutes: 5);
    case 'soundcloud':
      return const Duration(minutes: 3);
    case 'youtube':
      return const Duration(minutes: 2);
    default:
      return const Duration(minutes: 3);
  }
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
      body: _bodyWithRepostAttribution(row),
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

String? _bodyWithRepostAttribution(Map<String, dynamic> row) {
  final body = (row['body'] as String?)?.trim();
  final repostedBy = (row['reposted_by_name'] as String?)?.trim();
  if (row['is_repost'] != true || repostedBy == null || repostedBy.isEmpty) {
    return body?.isEmpty == true ? null : body;
  }

  final attribution = '\u21bb by $repostedBy';
  if (body == null || body.isEmpty) return attribution;
  if (body.startsWith(attribution)) return body;
  return '$attribution\n$body';
}

// Jitter window per platform. Bandcamp gets 0\u20134 hours so 2,000 artists spread
// their expiry times across the window rather than all going stale at once.
Duration _jitterFor(String platform) {
  if (platform != 'bandcamp') return Duration.zero;
  return Duration(minutes: _random.nextInt(240));
}

// Counting semaphore using a Completer queue \u2014 Dart stdlib has no built-in.
class _Semaphore {
  _Semaphore(int permits) : _available = permits;

  int _available;
  final _queue = <Completer<void>>[];

  Future<void> acquire() async {
    if (_available > 0) {
      _available--;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _available++;
    }
  }
}
