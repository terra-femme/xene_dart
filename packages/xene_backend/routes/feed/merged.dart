import 'dart:math';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/feed_cache.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/youtube_service.dart';
import 'package:xene_backend/src/services/bandcamp_service.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';
import 'package:xene_domain/xene_domain.dart';

final _logger = Logger('feed.merged');

// Mirrors feed.py TTL constants per platform.
const _platformTtls = {
  'soundcloud': Duration(hours: 6),
  'bandcamp': Duration(hours: 24),
  'youtube': Duration(hours: 24),
};

// Bandcamp cache window aligned with the 31-day UI archive window.
const _bandcampCacheDays = 31;
const _archiveFallbackSlots = 100;

/// GET /feed/merged
/// Fetches and merges feed items for all of the user's saved artists.
/// Two-tier cache: DB last_polled check → feed_items table → live fetch.
/// Optional `zone` param: 'recent' (≤7d), 'archive' (8–31d), or omitted (both).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final ip = extractClientIp(context);
  final rateLimited = checkRateLimit(feedMergedRateLimiter, ip);
  if (rateLimited != null) return rateLimited;

  final userId = context.read<String>();
  final params = context.request.uri.queryParameters;
  final page = int.tryParse(params['page'] ?? '1') ?? 1;
  final limit = int.tryParse(params['limit'] ?? '30') ?? 30;
  final seedDateParam = params['seed_date'];
  final presetSlug = params['preset_id'] ?? params['preset_slug'];
  // Fix C: zone=recent returns only ≤7d items; zone=archive returns 8–31d;
  // no zone returns both (backward-compatible default).
  final zoneParam = params['zone'];
  // When true: bypass the daily carousel and return all archive items newest-first (full-greed mode).
  final fullArchive = params['full_archive'] == 'true';
  // Optional platform filter — comma-separated list of platforms to include.
  // e.g. platforms=soundcloud,youtube  → skips BC tasks (phase-1 fast path)
  //      platforms=bandcamp            → skips SC+YT tasks (phase-2 slow path)
  // null (omitted) = all platforms (backward-compatible default).
  final platformsParam = params['platforms'];
  final platformFilter = platformsParam != null
      ? platformsParam.split(',').map((p) => p.trim().toLowerCase()).toSet()
      : null;
  // When force_refresh=true: clears Supabase cache markers + bypasses the
  // BandcampService in-memory cache for all BC artists in this preset.
  // Use sparingly — triggers a full live scrape for every BC artist.
  final forceRefresh = params['force_refresh'] == 'true';
  if (forceRefresh) {
    final forceRateLimited = checkRateLimit(forceRefreshRateLimiter, ip);
    if (forceRateLimited != null) return forceRateLimited;
  }
  final searchQuery = params['q']?.trim();

  final effectiveDate = seedDateParam != null
      ? DateTime.tryParse(seedDateParam)?.toUtc() ?? DateTime.now().toUtc()
      : DateTime.now().toUtc();

  _logger.info(
    '[feed.merged] userId=$userId page=$page limit=$limit '
    'seed_date=${seedDateParam ?? 'today'} preset=${presetSlug ?? 'following'} '
    'zone=${zoneParam ?? 'both'} platforms=${platformsParam ?? 'all'} '
    'full_archive=$fullArchive',
  );
  if (platformFilter != null) {
    _logger.info(
      '[feed.merged] platformFilter active: ${platformFilter.join(',')}',
    );
  }

  final db = context.read<DatabaseService>();
  final scService = context.read<SoundCloudService>();
  final ytService = context.read<YouTubeService>();
  final bcService = context.read<BandcampService>();

  // ── Search path ──────────────────────────────────────────────────────────
  // When q= is present, bypass zone/carousel/exposure logic entirely.
  // Returns a flat newest-first list of up to 50 matching DB rows.
  if (searchQuery != null && searchQuery.isNotEmpty) {
    final searchLimit = int.tryParse(params['limit'] ?? '50') ?? 50;
    Set<String>? artistNames;
    if (presetSlug != null && presetSlug.trim().isNotEmpty) {
      final artists = await db.getArtistsForPreset(userId, presetSlug.trim());
      artistNames = artists
          .map((artist) => artist['name'] as String?)
          .whereType<String>()
          .toSet();
      if (artistNames.isEmpty) {
        _logger.info(
          '[feed.merged] search q="$searchQuery" preset=$presetSlug has no source artists',
        );
        return Response.json(body: <dynamic>[]);
      }
    }
    final rows = await db.searchFeedItems(
      searchQuery,
      limit: searchLimit,
      artistNames: artistNames,
    );
    final items = rows.map(feedItemFromRow).whereType<FeedItem>().toList();
    _logger.info(
      '[feed.merged] search q="$searchQuery" returning ${items.length} items',
    );
    return Response.json(body: items.map((i) => i.toJson()).toList());
  }
  // ─────────────────────────────────────────────────────────────────────────

  final artists = presetSlug == null || presetSlug.trim().isEmpty
      ? await db.getArtists(userId)
      : await db.getArtistsForPreset(userId, presetSlug.trim());
  _logger.info(
    '[feed.merged] ${artists.length} source artists for user=$userId '
    'preset=${presetSlug ?? 'following'}',
  );

  if (artists.isEmpty) {
    _logger.info('[feed.merged] No source artists — returning empty feed');
    return Response.json(body: <dynamic>[]);
  }

  // force_refresh: delete Supabase last_polled + feed_empty_window markers so
  // fetchWithCache falls through to a live scrape for affected artists/platforms.
  if (forceRefresh) {
    for (final artist in artists) {
      final name = artist['name'] as String? ?? 'Unknown';

      final scIdentifier =
          (artist['soundcloud_url'] as String? ?? '').isNotEmpty
          ? artist['soundcloud_url'] as String
          : artist['soundcloud_username'] as String?;
      if (scIdentifier != null &&
          scIdentifier.isNotEmpty &&
          (platformFilter == null || platformFilter.contains('soundcloud'))) {
        await db.deleteSystemCache('last_polled:soundcloud:$name');
        await db.deleteSystemCache('feed_empty_window:soundcloud:$name:31d');
        await db.deleteSystemCache('feed_refresh_lock:soundcloud:$name');
        _logger.info(
          '[feed.merged] force_refresh: cleared SC cache markers for $name',
        );
      }

      final ytId = (artist['youtube_channel_id'] as String? ?? '').isNotEmpty
          ? artist['youtube_channel_id'] as String
          : artist['youtube_url'] as String?;
      if (ytId != null &&
          ytId.isNotEmpty &&
          (platformFilter == null || platformFilter.contains('youtube'))) {
        await db.deleteSystemCache('last_polled:youtube:$name');
        await db.deleteSystemCache('feed_empty_window:youtube:$name:31d');
        await db.deleteSystemCache('feed_refresh_lock:youtube:$name');
        _logger.info(
          '[feed.merged] force_refresh: cleared YT cache markers for $name',
        );
      }

      final bcUrl = artist['bandcamp_url'] as String?;
      if (bcUrl != null &&
          bcUrl.isNotEmpty &&
          (platformFilter == null || platformFilter.contains('bandcamp'))) {
        await db.deleteSystemCache(
          'feed_empty_window:bandcamp:$name:${_bandcampCacheDays}d',
        );
        await db.deleteSystemCache('last_polled:bandcamp:$name');
        await db.deleteSystemCache('feed_refresh_lock:bandcamp:$name');
        _logger.info(
          '[feed.merged] force_refresh: cleared BC cache markers for $name',
        );
      }
    }
  }

  // Fix A: Separate Bandcamp (scraper) tasks from SC/YT (API) tasks.
  // SC/YT run in parallel at concurrency=12; Bandcamp tasks run sequentially
  // (concurrency=1) to prevent simultaneous grid scrapes triggering 429s.
  final fastTaskFactories = <Future<List<FeedItem>> Function()>[];
  final bcTaskFactories = <Future<List<FeedItem>> Function()>[];

  for (final artist in artists) {
    final name = artist['name'] as String? ?? 'Unknown';

    final scUsername = artist['soundcloud_username'] as String?;
    final scUrl = artist['soundcloud_url'] as String?;
    final ytChannelId = artist['youtube_channel_id'] as String?;
    final ytUrl = artist['youtube_url'] as String?;
    final bcUrl = artist['bandcamp_url'] as String?;

    _logger.info(
      '[feed.merged] $name — sc_username=$scUsername '
      'sc_url=$scUrl '
      'yt_channel=$ytChannelId yt_url=$ytUrl '
      'bandcamp=$bcUrl',
    );

    final scIdentifier = (scUrl != null && scUrl.isNotEmpty)
        ? scUrl
        : scUsername;
    if (scIdentifier != null && scIdentifier.isNotEmpty) {
      if (platformFilter == null || platformFilter.contains('soundcloud')) {
        _logger.info('[feed.merged] → SC task: $scIdentifier ($name)');
        fastTaskFactories.add(
          () => fetchWithCache(
            db,
            'soundcloud',
            name,
            _platformTtls['soundcloud']!,
            () => scService.getTracks(scIdentifier, name),
            backgroundOnMiss: true,
          ),
        );
      } else {
        _logger.fine(
          '[feed.merged] SC skipped for $name (platformFilter=${platformFilter.join(',')})',
        );
      }
    }

    if (bcUrl != null && bcUrl.isNotEmpty) {
      if (platformFilter == null || platformFilter.contains('bandcamp')) {
        _logger.info('[feed.merged] → Bandcamp task: $bcUrl ($name)');
        bcTaskFactories.add(
          () => fetchWithCache(
            db,
            'bandcamp',
            name,
            _platformTtls['bandcamp']!,
            () =>
                bcService.getFeed(bcUrl, name, bypassMemoryCache: forceRefresh),
            cacheDays: _bandcampCacheDays,
            backgroundOnMiss: true,
          ),
        );
      } else {
        _logger.fine(
          '[feed.merged] Bandcamp skipped for $name (platformFilter=${platformFilter.join(',')})',
        );
      }
    }

    // Prefer a UC-format channel ID (direct RSS access).
    // If the stored channel_id is a bare handle (LLM guess like 'PLANETVTV'),
    // use youtube_url from SC web-profiles instead — it's artist-verified.
    final ytId = (ytChannelId != null && ytChannelId.startsWith('UC'))
        ? ytChannelId
        : (ytUrl ?? ytChannelId);
    if (ytId != null && ytId.isNotEmpty) {
      if (platformFilter == null || platformFilter.contains('youtube')) {
        _logger.info('[feed.merged] → YouTube task: $ytId ($name)');
        fastTaskFactories.add(
          () => fetchWithCache(
            db,
            'youtube',
            name,
            _platformTtls['youtube']!,
            () => ytService.getVideos(ytId, name),
            backgroundOnMiss: true,
          ),
        );
      } else {
        _logger.fine(
          '[feed.merged] YouTube skipped for $name (platformFilter=${platformFilter.join(',')})',
        );
      }
    }
  }

  _logger.info(
    '[feed.merged] Task factories — fast=${fastTaskFactories.length} '
    'bc=${bcTaskFactories.length} (platforms=${platformsParam ?? 'all'})',
  );
  if (fastTaskFactories.isEmpty && bcTaskFactories.isEmpty) {
    if (platformFilter != null) {
      _logger.warning(
        '[feed.merged] No tasks built — platformFilter=${platformFilter.join(',')} '
        'produced zero tasks for ${artists.length} artists',
      );
    } else {
      _logger.warning(
        '[feed.merged] Saved artists have no platform links — feed will be empty',
      );
    }
    return Response.json(body: <dynamic>[]);
  }

  _logger.info(
    '[feed.merged] Running fast=${fastTaskFactories.length} '
    'bc=${bcTaskFactories.length} platform tasks',
  );

  // SC/YT and Bandcamp groups run in parallel with each other, but within
  // the BC group tasks execute one at a time (concurrency=1).
  final bothResults = await Future.wait([
    _runBatched(fastTaskFactories, concurrency: 12),
    _runBatched(bcTaskFactories, concurrency: 1),
  ]);
  final results = [...bothResults[0], ...bothResults[1]];

  // Calendar-day windows, aligned with the Flutter providers:
  // recent includes the whole day from 7 calendar days ago.
  final recentCutoff = _midnightCutoff(effectiveDate, 7);
  final archiveCutoff = _midnightCutoff(effectiveDate, 31);
  final allItems = <FeedItem>[];
  for (final sublist in results) {
    for (final item in sublist) {
      if (!item.publishedAt.toLocal().isBefore(archiveCutoff)) {
        allItems.add(item);
      }
    }
  }

  final scCount = allItems.where((i) => i.platform == 'soundcloud').length;
  final ytCount = allItems.where((i) => i.platform == 'youtube').length;
  final bcCount = allItems.where((i) => i.platform == 'bandcamp').length;
  _logger.info(
    '[feed.merged] 31d pool — SC=$scCount YT=$ytCount BC=$bcCount total=${allItems.length}',
  );

  // Dedup by platform_id
  final seenIds = <String>{};
  final uniqueItems = <FeedItem>[];
  for (final item in allItems) {
    if (seenIds.add('${item.platform}_${item.id}')) uniqueItems.add(item);
  }
  _logger.info('[feed.merged] Unique after dedup: ${uniqueItems.length}');

  final recentItems = _sortNewestFirst(
    uniqueItems
        .where((item) => !item.publishedAt.toLocal().isBefore(recentCutoff))
        .toList(),
  );
  final archiveItems = uniqueItems
      .where(
        (item) =>
            item.publishedAt.toLocal().isBefore(recentCutoff) &&
            !item.publishedAt.toLocal().isBefore(archiveCutoff),
      )
      .toList();

  if (recentItems.isEmpty && archiveItems.isEmpty) {
    _logger.warning('[feed.merged] Empty pool — returning empty feed');
    return Response.json(body: <dynamic>[]);
  }

  // Fix C: Build pools only for the requested zone.
  final serveRecent = zoneParam == null || zoneParam == 'recent';
  final serveArchive = zoneParam == null || zoneParam == 'archive';

  final recentPool = serveRecent ? recentItems : <FeedItem>[];

  final archivePool = !serveArchive
      ? <FeedItem>[]
      : () {
          final int archiveSlots;
          if (!serveRecent) {
            // zone=archive: dedicate the full limit to archive items
            archiveSlots = limit;
          } else {
            // no zone: fill remaining slots; fall back to 100 if recent fills budget
            final remaining = (limit - recentPool.length).clamp(0, limit);
            archiveSlots = remaining > 0
                ? remaining
                : (recentPool.length >= limit ? _archiveFallbackSlots : 0);
          }
          if (archiveItems.isEmpty || archiveSlots == 0) return <FeedItem>[];
          // Full-greed mode: skip the daily carousel, return all items newest-first.
          if (fullArchive) {
            return _archiveFullPage(archiveItems, page, archiveSlots);
          }
          final shuffled = List<FeedItem>.from(archiveItems)
            ..shuffle(Random(0xFEED_FACE));
          final start = _archiveStartIndex(
            effectiveDate,
            archiveItems.length,
            archiveSlots,
          );
          final pageIndex = page <= 1 ? 0 : page - 1;
          final pageOffset = pageIndex * archiveSlots;
          final pageItems = !serveRecent
              ? _carouselPage(shuffled, start, pageOffset, archiveSlots)
              : _carouselWindow(shuffled, start, archiveSlots);
          return _sortNewestFirst(pageItems);
        }();

  final responsePool = [...recentPool, ...archivePool];

  // Day number since fixed epoch
  final epoch = DateTime.utc(2026, 1, 1);
  final dayNumber = effectiveDate.toUtc().difference(epoch).inDays;

  // Teal is zone-aware: a card is teal when it is newly visible to this user
  // in this part of the feed experience. Recent and archive exposures are
  // tracked separately so a release can be teal once in recent, then teal
  // again later when it first enters the archive rotation.
  Set<String> normalZoneIds;
  if (seedDateParam == null) {
    // Fix C: Only read/record exposure for zones we're serving.
    final seenRecentIds = serveRecent
        ? await _readFeedExposureIds(db, userId, presetSlug, 'recent')
        : const <String>{};
    final seenArchiveIds = serveArchive
        ? await _readFeedExposureIds(db, userId, presetSlug, 'archive')
        : const <String>{};

    // Fix D: Per-zone first-open baseline — no teal on the very first exposure.
    // When a zone's seen set is empty this is the first time we serve it to
    // this user. All served items become "normal" (not teal), establishing the
    // Day 0 baseline. Day 1+ onwards only genuinely new items become teal.
    final isFirstOpenRecent = serveRecent && seenRecentIds.isEmpty;
    final isFirstOpenArchive = serveArchive && seenArchiveIds.isEmpty;

    final recentNewIds = (serveRecent && !isFirstOpenRecent)
        ? recentPool
              .map(_itemExposureId)
              .where((id) => !seenRecentIds.contains(id))
              .toSet()
        : <String>{};
    final archiveNewIds = (serveArchive && !isFirstOpenArchive)
        ? archivePool
              .map(_itemExposureId)
              .where((id) => !seenArchiveIds.contains(id))
              .toSet()
        : <String>{};

    normalZoneIds = {
      if (serveRecent)
        ...(isFirstOpenRecent
            ? recentPool.map(
                (i) => _zoneExposureId('recent', _itemExposureId(i)),
              )
            : recentPool
                  .map(_itemExposureId)
                  .where((id) => !recentNewIds.contains(id))
                  .map((id) => _zoneExposureId('recent', id))),
      if (serveArchive)
        ...(isFirstOpenArchive
            ? archivePool.map(
                (i) => _zoneExposureId('archive', _itemExposureId(i)),
              )
            : archivePool
                  .map(_itemExposureId)
                  .where((id) => !archiveNewIds.contains(id))
                  .map((id) => _zoneExposureId('archive', id))),
    };

    if (serveRecent) {
      await _recordFeedExposureIds(
        db,
        userId,
        presetSlug,
        'recent',
        recentPool.map(_itemExposureId),
      );
    }
    if (serveArchive) {
      await _recordFeedExposureIds(
        db,
        userId,
        presetSlug,
        'archive',
        archivePool.map(_itemExposureId),
      );
    }
  } else {
    // TEST button — compute real today's baseline (non-mutating).
    final realNow = DateTime.now().toUtc();
    final realRecentCutoff = _midnightCutoff(realNow, 7);
    final realArchiveCutoff = _midnightCutoff(realNow, 31);
    final realRecentPool = _sortNewestFirst(
      uniqueItems
          .where(
            (item) => !item.publishedAt.toLocal().isBefore(realRecentCutoff),
          )
          .toList(),
    ).take(limit).toList();
    final realArchiveSlots = (limit - realRecentPool.length)
        .clamp(0, limit)
        .toInt();
    final realArchiveItems = uniqueItems
        .where(
          (item) =>
              item.publishedAt.toLocal().isBefore(realRecentCutoff) &&
              !item.publishedAt.toLocal().isBefore(realArchiveCutoff),
        )
        .toList();
    final realArchiveIds = realArchiveItems.isEmpty || realArchiveSlots == 0
        ? <String>[]
        : _carouselWindow(
            List<FeedItem>.from(realArchiveItems)..shuffle(Random(0xFEED_FACE)),
            _archiveStartIndex(
              realNow,
              realArchiveItems.length,
              realArchiveSlots,
            ),
            realArchiveSlots,
          ).map(_itemExposureId);
    normalZoneIds = {
      ...realRecentPool
          .map(_itemExposureId)
          .map((id) => _zoneExposureId('recent', id)),
      ...realArchiveIds.map((id) => _zoneExposureId('archive', id)),
    };
  }

  final itemZones = <String, String>{
    for (final item in recentPool) _itemExposureId(item): 'recent',
    for (final item in archivePool) _itemExposureId(item): 'archive',
  };

  final newCount = responsePool.where((i) {
    final id = _itemExposureId(i);
    final zone = itemZones[id] ?? 'recent';
    return !normalZoneIds.contains(_zoneExposureId(zone, id));
  }).length;
  _logger.info(
    '[feed.merged] day=$dayNumber recentTotal=${recentItems.length} '
    'recentReturning=${recentPool.length} '
    'archiveTotal=${archiveItems.length} archiveReturning=${archivePool.length} '
    'newToday=$newCount returning=${responsePool.length}',
  );

  return Response.json(
    body: responsePool.map((item) {
      final json = item.toJson();
      final id = _itemExposureId(item);
      final zone = itemZones[id] ?? 'recent';
      json['isNew'] = !normalZoneIds.contains(_zoneExposureId(zone, id));
      return json;
    }).toList(),
  );
}

String _feedExposureCacheKey(String userId, String? presetSlug, String zone) {
  final preset = presetSlug == null || presetSlug.trim().isEmpty
      ? 'following'
      : presetSlug.trim();
  return 'feed_${zone}_seen:$userId:$preset';
}

DateTime _midnightCutoff(DateTime effectiveDate, int daysBack) {
  final local = effectiveDate.toLocal();
  return DateTime(
    local.year,
    local.month,
    local.day,
  ).subtract(Duration(days: daysBack));
}

String _itemExposureId(FeedItem item) => '${item.platform}:${item.id}';

String _zoneExposureId(String zone, String itemId) => '$zone:$itemId';

Future<Set<String>> _readFeedExposureIds(
  DatabaseService db,
  String userId,
  String? presetSlug,
  String zone,
) async {
  final cached = await db.getSystemCache(
    _feedExposureCacheKey(userId, presetSlug, zone),
  );
  final ids = cached?['ids'] as List? ?? const [];
  return ids.map((id) => id.toString()).toSet();
}

Future<void> _recordFeedExposureIds(
  DatabaseService db,
  String userId,
  String? presetSlug,
  String zone,
  Iterable<String> ids,
) async {
  final newIds = ids.toSet();
  if (newIds.isEmpty) return;

  final cacheKey = _feedExposureCacheKey(userId, presetSlug, zone);
  final existing = await _readFeedExposureIds(db, userId, presetSlug, zone);
  final allIds = {...existing, ...newIds};

  await db.setSystemCache(cacheKey, {
    'ids': allIds.toList()..sort(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  }, expiresAt: DateTime.now().toUtc().add(const Duration(days: 45)));
}

Future<List<List<FeedItem>>> _runBatched(
  List<Future<List<FeedItem>> Function()> taskFactories, {
  int concurrency = 24,
}) async {
  final results = <List<FeedItem>>[];
  for (var i = 0; i < taskFactories.length; i += concurrency) {
    final batch = taskFactories.skip(i).take(concurrency).map((run) => run());
    results.addAll(await Future.wait(batch, eagerError: false));
  }
  return results;
}

int _archiveStartIndex(DateTime effectiveDate, int total, int limit) {
  if (total <= 0 || limit <= 0) return 0;
  final newPerDay = (limit * limit / total).floor().clamp(1, limit).toInt();
  final epoch = DateTime.utc(2026, 1, 1);
  final dayNumber = effectiveDate.toUtc().difference(epoch).inDays;
  return (dayNumber * newPerDay) % total;
}

/// Returns [count] items from [src] starting at [start], wrapping around.
List<FeedItem> _carouselWindow(List<FeedItem> src, int start, int count) {
  final out = <FeedItem>[];
  final n = src.length;
  for (var i = 0; i < count && i < n; i++) {
    out.add(src[(start + i) % n]);
  }
  return out;
}

/// Returns one non-wrapping page from the daily rotated archive order.
List<FeedItem> _carouselPage(
  List<FeedItem> src,
  int start,
  int offset,
  int count,
) {
  if (src.isEmpty || count <= 0) return [];
  final rotated = [...src.skip(start), ...src.take(start)];
  return rotated.skip(offset).take(count).toList();
}

/// Full-greed mode: simple newest-first pagination over ALL archive items.
/// No carousel rotation or daily shuffle — just a chronological page window.
List<FeedItem> _archiveFullPage(List<FeedItem> items, int page, int count) {
  if (items.isEmpty || count <= 0) return [];
  final sorted = _sortNewestFirst(items);
  final offset = (page - 1) * count;
  return sorted.skip(offset).take(count).toList();
}

List<FeedItem> _sortNewestFirst(List<FeedItem> items) {
  return List<FeedItem>.from(items)..sort((a, b) {
    final byDate = b.publishedAt.compareTo(a.publishedAt);
    if (byDate != 0) return byDate;

    final byArtist = a.artistName.compareTo(b.artistName);
    if (byArtist != 0) return byArtist;

    return a.id.compareTo(b.id);
  });
}

// Cache logic lives in lib/src/feed_cache.dart for testability.
// fetchWithCache and feedItemFromRow are imported from there.
