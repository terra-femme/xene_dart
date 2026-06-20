import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';
import 'auth_provider.dart';
import 'dio_provider.dart';
import 'feed_frontend_cache.dart';
import 'preset_provider.dart';
import '../utils/artwork_proxy.dart';

// Recent feed: 30 items is enough for the initial above-fold view.
// Archive is fetched separately on sheet open (lazy hydration).
const _kFeedWindowLimit = 30;
const _kArchivePageLimit = 16;
// Full-greed mode: larger pages so the whole 31-day window lazy-loads quickly.
const _kFullArchivePageLimit = 50;

enum FeedMode { methodical, fullFeed }

final feedProvider = AsyncNotifierProvider<FeedNotifier, List<FeedItem>>(
  FeedNotifier.new,
);

final feedModeProvider = StateProvider<FeedMode>((ref) => FeedMode.methodical);

// Lazy-loaded archive feed. Build returns [] immediately; data is fetched only
// when the draggable sheet first opens via ArchiveFetchNotifier.fetchOnce().
final archiveFetchProvider =
    AsyncNotifierProvider<ArchiveFetchNotifier, List<FeedItem>>(
      ArchiveFetchNotifier.new,
    );

final platformFilterProvider = StateProvider<String?>((ref) => null);
final artistFilterProvider = StateProvider<String?>((ref) => null);
final feedEffectiveDateProvider = StateProvider<DateTime?>((ref) => null);

// Holds composite IDs ('platform_id') of feed items just appended by BC phase-2.
// _AnimatingFeedCard widgets read this once on initState to decide whether to animate.
// Each ID is removed from the set after its card's animation completes.
final newFeedItemIdsProvider = StateProvider<Set<String>>((ref) => const {});

// Search query — null means search is inactive.
final searchQueryProvider = StateProvider<String?>((ref) => null);

// Cross-platform full-31d search via backend ilike.
// Auto-disposes when search is cleared so stale results don't linger.
final searchFeedProvider = FutureProvider.autoDispose<List<FeedItem>>((
  ref,
) async {
  final q = ref.watch(searchQueryProvider);
  if (q == null || q.trim().length < 2) return const [];

  ref.watch(currentUserIdProvider);
  final presetSlug = ref.watch(activePresetSlugProvider);
  final queryParams = <String, dynamic>{
    'q': q.trim(),
    'limit': 50,
    if (presetSlug.isNotEmpty) 'preset_id': presetSlug,
  };

  debugPrint('[feedProvider] search GET /feed/merged q=$q');
  final dio = ref.watch(authenticatedDioProvider);
  final response = await dio.get<dynamic>(
    '/feed/merged',
    queryParameters: queryParams,
  );

  final data = response.data as List<dynamic>;
  debugPrint('[feedProvider] search returned ${data.length} items');
  final items = _parseFeedItems(data, 'searchFeedProvider');
  debugPrint('[feedProvider] search parsed ${items.length} items');
  return items;
});

// Midnight-anchored cutoff: calendar days, not 24h windows.
DateTime _midnightCutoff(DateTime effectiveDate, int daysBack) {
  final local = effectiveDate.toLocal();
  return DateTime(
    local.year,
    local.month,
    local.day,
  ).subtract(Duration(days: daysBack));
}

// Items ≤ 7 calendar days old (main feed).
final recentFeedProvider = Provider<AsyncValue<List<FeedItem>>>((ref) {
  final effectiveDate = ref.watch(feedEffectiveDateProvider) ?? DateTime.now();
  final cutoff = _midnightCutoff(effectiveDate, 7);
  return ref.watch(feedProvider).whenData((items) {
    final filtered = _sortNewestFirst(
      items.where((i) => !i.publishedAt.toLocal().isBefore(cutoff)).toList(),
    );
    debugPrint(
      '[recentFeedProvider] total=${items.length} passed7d=${filtered.length} '
      'cutoff=${cutoff.toLocal().toIso8601String().substring(0, 10)} '
      '${items.isNotEmpty ? "newest=${items.first.publishedAt.toLocal().toIso8601String().substring(0, 10)}" : ""}',
    );
    return filtered;
  });
});

List<FeedItem> _sortNewestFirst(List<FeedItem> items) {
  return List<FeedItem>.from(items)..sort((a, b) {
    final byDate = b.publishedAt.compareTo(a.publishedAt);
    if (byDate != 0) return byDate;

    final byArtist = a.artistName.compareTo(b.artistName);
    if (byArtist != 0) return byArtist;

    return a.id.compareTo(b.id);
  });
}

final feedArtistsProvider = Provider<List<String>>((ref) {
  final feedAsync = ref.watch(feedProvider);
  return feedAsync.maybeWhen(
    data: (items) => items.map((e) => e.artistName).toSet().toList()..sort(),
    orElse: () => [],
  );
});

// Main feed with filters — wraps recentFeedProvider (≤ 7 days only).
final filteredFeedProvider = Provider<AsyncValue<List<FeedItem>>>((ref) {
  final feedAsync = ref.watch(recentFeedProvider);
  final platform = ref.watch(platformFilterProvider);
  final artist = ref.watch(artistFilterProvider);

  return feedAsync.whenData(
    (items) => _applyFeedFilters(items, platform, artist),
  );
});

// Archive feed with filters — wraps archiveFetchProvider (8–31 days).
final filteredArchiveFeedProvider = Provider<AsyncValue<List<FeedItem>>>((ref) {
  final feedAsync = ref.watch(archiveFetchProvider);
  final platform = ref.watch(platformFilterProvider);
  final artist = ref.watch(artistFilterProvider);

  return feedAsync.whenData(
    (items) => _applyFeedFilters(items, platform, artist),
  );
});

List<FeedItem> _applyFeedFilters(
  List<FeedItem> items,
  String? platform,
  String? artist,
) {
  final effectivePlatform =
      platform != null &&
          items.any(
            (item) => item.platform.toLowerCase() == platform.toLowerCase(),
          )
      ? platform
      : null;
  final effectiveArtist =
      artist != null && items.any((item) => item.artistName == artist)
      ? artist
      : null;

  return items.where((item) {
    final matchesPlatform =
        effectivePlatform == null ||
        item.platform.toLowerCase() == effectivePlatform.toLowerCase();
    final matchesArtist =
        effectiveArtist == null || item.artistName == effectiveArtist;
    return matchesPlatform && matchesArtist;
  }).toList();
}

/// Parses a raw JSON list into FeedItems, applying the artwork proxy transform.
List<FeedItem> _parseFeedItems(List<dynamic> data, String logTag) {
  final items = <FeedItem>[];
  for (var i = 0; i < data.length; i++) {
    try {
      final parsed = FeedItem.fromJson(data[i] as Map<String, dynamic>);
      items.add(
        parsed.copyWith(artworkUrl: proxyArtworkUrl(parsed.artworkUrl)),
      );
    } catch (e) {
      debugPrint('[$logTag] ERROR parsing item[$i]: $e');
      debugPrint('[$logTag] Raw item[$i]: ${data[i]}');
    }
  }
  return items;
}

/// Sentinel thrown by [FeedNotifier._fetchFeed] on HTTP 429.
/// Lets callers differentiate rate-limit from real network errors and
/// fall back to stale cache rather than propagating an error state.
class _RateLimitedException implements Exception {
  const _RateLimitedException();
  @override
  String toString() => 'Rate limit exceeded — try again shortly.';
}

class FeedNotifier extends AsyncNotifier<List<FeedItem>> {
  Dio? _dio;
  String _userId = '';

  // Track items for each phase so background refreshes can merge correctly
  // without filtering state by platform (which would break if platforms change).
  List<FeedItem> _fastItems = const []; // SC + YT
  List<FeedItem> _bcItems = const []; // Bandcamp

  @override
  Future<List<FeedItem>> build() async {
    _userId = ref.watch(currentUserIdProvider);
    _dio = ref.watch(authenticatedDioProvider);
    final currentPreset = ref.watch(activePresetSlugProvider);
    final cache = ref.read(feedFrontendCacheProvider);

    // Suspend until presetDialProvider has resolved.
    // Returning [] would set _dataReady=true in LoadingOverlay immediately,
    // causing it to dismiss at 2500ms before real feed content is ready.
    // Awaiting the future keeps feedProvider in AsyncLoading until the preset
    // is known. In practice this build is cancelled/restarted by Riverpod
    // the moment presetDialProvider resolves.
    final presetAsync = ref.watch(presetDialProvider);
    if (!presetAsync.hasValue) {
      debugPrint(
        '[feedProvider] presetDialProvider loading — suspending build',
      );
      try {
        await ref.read(presetDialProvider.future);
      } catch (_) {}
      return const <FeedItem>[];
    }

    // Reset per-preset phase tracking so background refreshes always merge
    // against data that belongs to this build's preset.
    _fastItems = const [];
    _bcItems = const [];

    // Debounce rapid preset switches: each notch click invalidates feedProvider,
    // queuing multiple concurrent build() calls. The dispose flag fires when
    // this scope is superseded so in-flight work can be abandoned early.
    var cancelled = false;
    ref.onDispose(() => cancelled = true);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (cancelled) return const <FeedItem>[];

    debugPrint(
      '[feedProvider] Initialised - baseUrl=$kBackendUrl user=$_userId preset=$currentPreset',
    );
    dev.log(
      '[feedProvider] build preset=$currentPreset user=$_userId',
      name: 'FeedProvider',
      level: 800,
    );

    // ── Phase-1: SoundCloud + YouTube ─────────────────────────────────────────
    final fastResult = cache.get(currentPreset, CacheZone.recentFast);

    if (fastResult.hasData) {
      // Cache hit (fresh or stale) — use immediately, no HTTP.
      _fastItems = List<FeedItem>.from(fastResult.items);
      debugPrint(
        '[feedProvider] Phase-1 ${fastResult.isStale ? "STALE-HIT" : "HIT"}: '
        '${_fastItems.length} SC+YT items from cache',
      );
      if (fastResult.isStale && !fastResult.isRefreshing) {
        debugPrint(
          '[feedProvider] Phase-1 stale — scheduling background refresh',
        );
        _scheduleBackgroundRefresh(
          presetSlug: currentPreset,
          zone: CacheZone.recentFast,
          platforms: 'soundcloud,youtube',
          isCancelledFn: () => cancelled,
          cache: cache,
        );
      }
    } else {
      // Cache miss — fetch from backend.
      debugPrint(
        '[feedProvider] Phase-1 MISS — fetching: platforms=soundcloud,youtube zone=recent',
      );
      try {
        _fastItems = await _fetchFeed(
          page: 1,
          presetSlug: currentPreset,
          zone: 'recent',
          platforms: 'soundcloud,youtube',
        );
        cache.set(currentPreset, CacheZone.recentFast, _fastItems);
        debugPrint(
          '[feedProvider] Phase-1 complete: ${_fastItems.length} SC+YT items — rendering feed now',
        );
      } on _RateLimitedException {
        debugPrint(
          '[feedProvider] Phase-1 rate-limited (429) — no stale cache, showing empty',
        );
        dev.log(
          '[feedProvider] Phase-1 rate-limited preset=$currentPreset',
          name: 'FeedProvider',
          level: 900,
        );
        _fastItems = const [];
      }
    }

    // Guard: if the preset changed while phase-1 was in flight, abandon.
    if (cancelled || ref.read(activePresetSlugProvider) != currentPreset) {
      debugPrint('[feedProvider] Phase-1 result discarded — preset changed');
      return const <FeedItem>[];
    }

    // ── Phase-2: Bandcamp ─────────────────────────────────────────────────────
    final bcResult = cache.get(currentPreset, CacheZone.recentBc);

    if (bcResult.hasData) {
      // BC also cached — merge and return immediately. Zero HTTP calls total.
      _bcItems = List<FeedItem>.from(bcResult.items);
      debugPrint(
        '[feedProvider] Phase-2 ${bcResult.isStale ? "STALE-HIT" : "HIT"}: '
        '${_bcItems.length} BC items from cache — returning merged feed',
      );
      dev.log(
        '[feedProvider] full cache hit: fast=${_fastItems.length} bc=${_bcItems.length} '
        'preset=$currentPreset',
        name: 'FeedProvider',
        level: 800,
      );
      if (bcResult.isStale && !bcResult.isRefreshing) {
        debugPrint(
          '[feedProvider] Phase-2 stale — scheduling background refresh',
        );
        _scheduleBackgroundRefresh(
          presetSlug: currentPreset,
          zone: CacheZone.recentBc,
          platforms: 'bandcamp',
          isCancelledFn: () => cancelled,
          cache: cache,
        );
      }
      return _sortNewestFirst([..._fastItems, ..._bcItems]);
    }

    // BC cache miss — fetch async and append when ready (non-blocking).
    debugPrint(
      '[feedProvider] Phase-2 MISS — fetching BC async (non-blocking append)',
    );
    _fetchFeed(
          page: 1,
          presetSlug: currentPreset,
          zone: 'recent',
          platforms: 'bandcamp',
        )
        .then((bcItems) {
          if (cancelled ||
              ref.read(activePresetSlugProvider) != currentPreset) {
            debugPrint(
              '[feedProvider] Phase-2 DISCARDED — preset changed from $currentPreset '
              'to ${ref.read(activePresetSlugProvider)} while BC was loading',
            );
            return;
          }
          cache.set(currentPreset, CacheZone.recentBc, bcItems);
          _bcItems = bcItems;
          debugPrint(
            '[feedProvider] Phase-2 BC response: ${bcItems.length} items',
          );
          if (bcItems.isEmpty) {
            debugPrint(
              '[feedProvider] Phase-2 WARNING: BC returned 0 items — nothing to append',
            );
            return;
          }
          final current = state.valueOrNull ?? [];
          final existingIds = current
              .map((i) => '${i.platform}_${i.id}')
              .toSet();
          final newBcItems = bcItems
              .where((i) => !existingIds.contains('${i.platform}_${i.id}'))
              .toList();
          debugPrint(
            '[feedProvider] Phase-2 dedup — current=${current.length} '
            'bcItems=${bcItems.length} newBcItems=${newBcItems.length} '
            'duplicatesSkipped=${bcItems.length - newBcItems.length}',
          );
          if (newBcItems.isNotEmpty) {
            final newIds = newBcItems
                .map((i) => '${i.platform}_${i.id}')
                .toSet();
            ref.read(newFeedItemIdsProvider.notifier).state = newIds;
            state = AsyncData(_sortNewestFirst([...current, ...newBcItems]));
            debugPrint(
              '[feedProvider] Phase-2 state updated — total=${(state.valueOrNull ?? []).length} '
              'newAnimatingIds=${newIds.length}',
            );
            dev.log(
              '[feedProvider] Phase-2 appended ${newBcItems.length} BC items preset=$currentPreset',
              name: 'FeedProvider',
              level: 800,
            );
          }
        })
        .catchError((Object e) {
          if (e is _RateLimitedException) {
            debugPrint(
              '[feedProvider] Phase-2 rate-limited (429) — BC not appended, feed shows SC+YT only',
            );
            dev.log(
              '[feedProvider] Phase-2 rate-limited preset=$currentPreset',
              name: 'FeedProvider',
              level: 900,
            );
          } else {
            debugPrint(
              '[feedProvider] Phase-2 ERROR (feed still showing SC+YT): $e',
            );
          }
        });

    return _fastItems;
  }

  Dio _getDio() {
    _dio ??= ref.read(authenticatedDioProvider);
    return _dio!;
  }

  Future<void> fetchWithSeedDate(String seedDate) async {
    final parsedSeed = DateTime.tryParse(seedDate);
    final presetSlug = ref.read(activePresetSlugProvider);
    ref.read(feedEffectiveDateProvider.notifier).state = parsedSeed;
    state = const AsyncLoading();
    // TEST mode: no zone — returns both recent + archive for full simulation.
    state = await AsyncValue.guard(
      () => _fetchFeed(page: 1, presetSlug: presetSlug, seedDate: seedDate),
    );
  }

  Future<void> refresh() async {
    final effectiveDate = ref.read(feedEffectiveDateProvider);
    final seedDate = effectiveDate?.toIso8601String().substring(0, 10);
    final presetSlug = ref.read(activePresetSlugProvider);

    // Bust frontend cache so fresh data is fetched instead of the stale entry.
    ref.read(feedFrontendCacheProvider).invalidatePreset(presetSlug);
    debugPrint('[feedProvider] refresh() — cache invalidated for $presetSlug');

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        return await _fetchFeed(
          page: 1,
          presetSlug: presetSlug,
          seedDate: seedDate,
          zone: seedDate == null ? 'recent' : null,
        );
      } on _RateLimitedException {
        debugPrint(
          '[feedProvider] refresh() rate-limited — keeping current state',
        );
        dev.log(
          '[feedProvider] refresh rate-limited preset=$presetSlug',
          name: 'FeedProvider',
          level: 900,
        );
        return state.valueOrNull ?? const <FeedItem>[];
      }
    });
  }

  Future<List<FeedItem>> _fetchFeed({
    required int page,
    required String presetSlug,
    String? seedDate,
    String? zone,
    String? platforms,
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'limit': _kFeedWindowLimit,
    };
    if (presetSlug.isNotEmpty) queryParams['preset_id'] = presetSlug;
    if (seedDate != null) queryParams['seed_date'] = seedDate;
    if (zone != null) queryParams['zone'] = zone;
    if (platforms != null) queryParams['platforms'] = platforms;
    debugPrint(
      '[feedProvider] GET /feed/merged '
      '${queryParams.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
    );
    try {
      final dio = _getDio();
      final response = await dio.get<dynamic>(
        '/feed/merged',
        queryParameters: queryParams,
      );

      debugPrint('[feedProvider] Response status=${response.statusCode}');

      final raw = response.data;
      if (raw == null) {
        debugPrint('[feedProvider] WARNING: response.data is null');
        return [];
      }

      final data = raw as List<dynamic>;
      debugPrint('[feedProvider] Raw item count=${data.length}');

      if (data.isEmpty) {
        debugPrint(
          '[feedProvider] WARNING: /feed/merged returned empty list — no cached feed items in DB',
        );
        return [];
      }

      final items = _parseFeedItems(data, 'feedProvider');
      debugPrint(
        '[feedProvider] Parsed ${items.length}/${data.length} items successfully',
      );
      return items;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        debugPrint(
          '[feedProvider] _fetchFeed 429 platforms=${platforms ?? "all"} — throwing _RateLimitedException',
        );
        dev.log(
          '[feedProvider] 429 platforms=${platforms ?? "all"} preset=$presetSlug',
          name: 'FeedProvider',
          level: 900,
        );
        throw const _RateLimitedException();
      }
      debugPrint(
        '[feedProvider] DioException status=${e.response?.statusCode} message=${e.message}',
      );
      debugPrint('[feedProvider] Response body=${e.response?.data}');
      rethrow;
    } catch (e) {
      debugPrint('[feedProvider] Unexpected error: $e');
      rethrow;
    }
  }

  /// Fires a background HTTP refresh for [zone] and updates cache + state on
  /// completion. Safe to call fire-and-forget. Guards against cancelled builds
  /// and preset changes before touching state.
  void _scheduleBackgroundRefresh({
    required String presetSlug,
    required String zone,
    required String platforms,
    required bool Function() isCancelledFn,
    required FeedFrontendCache cache,
  }) {
    cache.markRefreshing(presetSlug, zone);
    debugPrint(
      '[feedProvider] bg-refresh START zone=$zone platforms=$platforms preset=$presetSlug',
    );
    dev.log(
      '[feedProvider] bg-refresh start zone=$zone preset=$presetSlug',
      name: 'FeedProvider',
      level: 800,
    );
    _fetchFeed(
          page: 1,
          presetSlug: presetSlug,
          zone: 'recent',
          platforms: platforms,
        )
        .then((freshItems) {
          cache.clearRefreshing(presetSlug, zone);
          if (isCancelledFn() ||
              ref.read(activePresetSlugProvider) != presetSlug) {
            debugPrint(
              '[feedProvider] bg-refresh DISCARDED zone=$zone preset=$presetSlug (preset changed)',
            );
            return;
          }
          cache.set(presetSlug, zone, freshItems);
          if (zone == CacheZone.recentFast) _fastItems = freshItems;
          if (zone == CacheZone.recentBc) _bcItems = freshItems;
          // Merge both phases from instance state so neither is lost.
          state = AsyncData(_sortNewestFirst([..._fastItems, ..._bcItems]));
          debugPrint(
            '[feedProvider] bg-refresh DONE zone=$zone preset=$presetSlug '
            '${freshItems.length} items — state updated',
          );
          dev.log(
            '[feedProvider] bg-refresh done zone=$zone ${freshItems.length} items preset=$presetSlug',
            name: 'FeedProvider',
            level: 800,
          );
        })
        .catchError((Object e) {
          cache.clearRefreshing(presetSlug, zone);
          if (e is _RateLimitedException) {
            debugPrint(
              '[feedProvider] bg-refresh rate-limited zone=$zone preset=$presetSlug — keeping stale',
            );
            dev.log(
              '[feedProvider] bg-refresh rate-limited zone=$zone preset=$presetSlug',
              name: 'FeedProvider',
              level: 900,
            );
          } else {
            debugPrint(
              '[feedProvider] bg-refresh ERROR zone=$zone preset=$presetSlug: $e',
            );
            dev.log(
              '[feedProvider] bg-refresh error zone=$zone preset=$presetSlug: $e',
              name: 'FeedProvider',
              level: 1000,
            );
          }
        });
  }
}

/// Lazy archive feed notifier. Starts empty; data is fetched in small pages so
/// the sheet can paint quickly without hydrating the whole archive up front.
/// Rebuilds (and resets _fetched) automatically when the active preset changes.
class ArchiveFetchNotifier extends AsyncNotifier<List<FeedItem>> {
  bool _fetched = false;
  bool _isFetching = false;
  bool _hasMore = true;
  int _nextPage = 1;
  int _generation = 0;

  @override
  Future<List<FeedItem>> build() async {
    // Depend on preset and mode so that changing either resets archive state,
    // causing the archive to re-fetch on the next sheet open.
    ref.watch(activePresetSlugProvider);
    ref.watch(feedModeProvider);
    _fetched = false;
    _isFetching = false;
    _hasMore = true;
    _nextPage = 1;
    _generation++;
    return [];
  }

  Future<void> fetchOnce() async {
    if (_fetched) return;

    final cache = ref.read(feedFrontendCacheProvider);
    final presetSlug = ref.read(activePresetSlugProvider);
    final archiveResult = cache.get(presetSlug, CacheZone.archive);

    if (archiveResult.isFresh) {
      // Fresh cache hit — paint the sheet immediately, zero HTTP.
      final items = List<FeedItem>.from(archiveResult.items);
      debugPrint(
        '[archiveFetchProvider] Cache HIT: ${items.length} items preset=$presetSlug — skipping HTTP',
      );
      dev.log(
        '[archiveFetchProvider] cache hit ${items.length} items preset=$presetSlug',
        name: 'ArchiveFetchProvider',
        level: 800,
      );
      _fetched = true;
      final isFullFeed = ref.read(feedModeProvider) == FeedMode.fullFeed;
      // If in full-archive mode but the cache has fewer items than one
      // full-archive page, it was built from the daily carousel. Full-archive
      // page 1 must still run so items at positions 0–49 (which may not be
      // in the carousel window) are not silently skipped.
      final cacheCoversFullArchive =
          !isFullFeed || items.length >= _kFullArchivePageLimit;
      state = AsyncData(items);
      if (!cacheCoversFullArchive) {
        debugPrint(
          '[archiveFetchProvider] Cache HIT but mode=fullFeed with carousel-sized cache '
          '(${items.length} < $_kFullArchivePageLimit) — fetching page 1 to fill gaps',
        );
        _nextPage = 1;
        _hasMore = true;
        fetchNextPage(showInitialLoading: false);
      } else {
        _nextPage = 2;
        _hasMore =
            items.length >=
            (isFullFeed ? _kFullArchivePageLimit : _kArchivePageLimit);
      }
      return;
    }

    if (archiveResult.isStale) {
      // Stale-while-revalidate: show stale data instantly, refresh in background.
      final staleItems = List<FeedItem>.from(archiveResult.items);
      debugPrint(
        '[archiveFetchProvider] STALE-HIT: ${staleItems.length} items preset=$presetSlug '
        '— showing stale, refreshing in background',
      );
      dev.log(
        '[archiveFetchProvider] stale-hit ${staleItems.length} items preset=$presetSlug',
        name: 'ArchiveFetchProvider',
        level: 700,
      );
      _fetched = true;
      _nextPage = 1; // refresh from page 1
      _hasMore = true;
      state = AsyncData(staleItems);
      // Fire without await — user sees stale data instantly, state updates when fresh arrives.
      fetchNextPage(showInitialLoading: false);
      return;
    }

    // Cache miss — normal fetch with loading indicator.
    debugPrint(
      '[archiveFetchProvider] Cache MISS preset=$presetSlug — fetching',
    );
    await fetchNextPage(showInitialLoading: true);
  }

  Future<void> fetchNextPage({bool showInitialLoading = false}) async {
    if (_isFetching || !_hasMore) return;

    final existingItems = state.valueOrNull ?? const <FeedItem>[];
    if (_fetched && existingItems.isEmpty && !showInitialLoading) return;

    _fetched = true;
    _isFetching = true;
    final requestGeneration = _generation;
    final requestPresetSlug = ref.read(activePresetSlugProvider);
    final requestFeedMode = ref.read(feedModeProvider);
    if (showInitialLoading && existingItems.isEmpty) {
      state = const AsyncLoading();
    }

    final page = _nextPage;
    final result = await AsyncValue.guard(
      () => _fetchArchive(
        page: page,
        presetSlug: requestPresetSlug,
        feedMode: requestFeedMode,
      ),
    );
    final isStale =
        requestGeneration != _generation ||
        requestPresetSlug != ref.read(activePresetSlugProvider) ||
        requestFeedMode != ref.read(feedModeProvider);
    if (isStale) {
      debugPrint(
        '[archiveFetchProvider] STALE response discarded '
        'page=$page preset=$requestPresetSlug mode=$requestFeedMode',
      );
      _isFetching = false;
      return;
    }
    result.when(
      data: (items) {
        final rawMerged = page == 1 ? items : [...existingItems, ...items];
        final seen = <String>{};
        final merged = rawMerged
            .where((i) => seen.add('${i.platform}_${i.id}'))
            .toList();
        final pageLimit = requestFeedMode == FeedMode.fullFeed
            ? _kFullArchivePageLimit
            : _kArchivePageLimit;
        _hasMore = items.length == pageLimit;
        _nextPage = page + 1;
        state = AsyncData(merged);
        // Update frontend cache with accumulated archive items.
        // Stale-while-revalidate: next sheet open for this preset skips HTTP.
        ref
            .read(feedFrontendCacheProvider)
            .set(requestPresetSlug, CacheZone.archive, merged);
        debugPrint(
          '[archiveFetchProvider] Cache SET preset=$requestPresetSlug '
          '${merged.length} archive items (page=$page hasMore=$_hasMore)',
        );
      },
      error: (error, stackTrace) {
        debugPrint('[archiveFetchProvider] ERROR page=$page: $error');
        dev.log(
          '[archiveFetchProvider] fetch error page=$page: $error',
          name: 'ArchiveFetchProvider',
          level: 1000,
        );
        state = existingItems.isEmpty
            ? AsyncError(error, stackTrace)
            : AsyncData(existingItems);
      },
      loading: () {},
    );

    _isFetching = false;
  }

  Future<List<FeedItem>> _fetchArchive({
    required int page,
    required String presetSlug,
    required FeedMode feedMode,
  }) async {
    final isFullFeed = feedMode == FeedMode.fullFeed;
    final pageLimit = isFullFeed ? _kFullArchivePageLimit : _kArchivePageLimit;
    final queryParams = <String, dynamic>{
      'page': page,
      'limit': pageLimit,
      'zone': 'archive',
      if (isFullFeed) 'full_archive': 'true',
    };
    if (presetSlug.isNotEmpty) queryParams['preset_id'] = presetSlug;
    debugPrint(
      '[archiveFetchProvider] GET /feed/merged zone=archive '
      'page=$page limit=$pageLimit preset=$presetSlug '
      'full_archive=$isFullFeed',
    );
    try {
      final dio = ref.read(authenticatedDioProvider);
      final response = await dio.get<dynamic>(
        '/feed/merged',
        queryParameters: queryParams,
      );

      debugPrint(
        '[archiveFetchProvider] Response status=${response.statusCode}',
      );

      final raw = response.data;
      if (raw == null) {
        debugPrint('[archiveFetchProvider] WARNING: response.data is null');
        return [];
      }

      final data = raw as List<dynamic>;
      if (data.isEmpty) {
        debugPrint('[archiveFetchProvider] WARNING: empty archive response');
        return [];
      }

      final items = _parseFeedItems(data, 'archiveFetchProvider');
      debugPrint(
        '[archiveFetchProvider] Parsed ${items.length}/${data.length} archive items',
      );
      debugPrint(
        '[archiveFetchProvider] Archive artists=${items.map((i) => i.artistName).toSet().join(', ')}',
      );
      return items;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        debugPrint(
          '[archiveFetchProvider] rate-limited (429) page=$page preset=$presetSlug',
        );
        dev.log(
          '[archiveFetchProvider] 429 page=$page preset=$presetSlug',
          name: 'ArchiveFetchProvider',
          level: 900,
        );
        throw const _RateLimitedException();
      }
      debugPrint(
        '[archiveFetchProvider] DioException status=${e.response?.statusCode} message=${e.message}',
      );
      rethrow;
    } catch (e) {
      debugPrint('[archiveFetchProvider] Unexpected error: $e');
      rethrow;
    }
  }
}
