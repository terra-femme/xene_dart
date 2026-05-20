import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';
import 'preset_provider.dart';

const _kUserId = 'local_user';
// Recent feed: 30 items is enough for the initial above-fold view.
// Archive is fetched separately on sheet open (lazy hydration).
const _kFeedWindowLimit = 30;
const _kArchivePageLimit = 16;
// Full-greed mode: larger pages so the whole 31-day window lazy-loads quickly.
const _kFullArchivePageLimit = 50;

enum FeedMode { methodical, fullFeed }

/// Backend base URL, injected at build time via --dart-define=BACKEND_URL=<url>
/// Defaults to localhost:8080 for local development.
/// Production: flutter build web --dart-define=BACKEND_URL=https://xene-backend-abc123.run.app
const _kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8080',
);

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

  final presetSlug = ref.watch(activePresetSlugProvider);
  final queryParams = <String, dynamic>{
    'q': q.trim(),
    'limit': 50,
    if (presetSlug.isNotEmpty) 'preset_id': presetSlug,
  };

  debugPrint('[feedProvider] search GET /feed/merged q=$q');
  final dio = Dio(
    BaseOptions(
      baseUrl: _kBackendUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-User-Id': _kUserId,
      },
    ),
  );
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
  return ref
      .watch(feedProvider)
      .whenData(
        (items) => _sortNewestFirst(
          items
              .where((i) => !i.publishedAt.toLocal().isBefore(cutoff))
              .toList(),
        ),
      );
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

/// Transforms CORS-restricted artwork URLs to proxy through the backend.
String? _proxyArtworkUrl(String? url) {
  if (url == null || url.isEmpty) return null;

  const corsRestrictedDomains = [
    'f4.bcbits.com',
    'f3.bcbits.com',
    'f2.bcbits.com',
    'f1.bcbits.com',
    'a.bcbits.com', // Bandcamp
    'i1.sndcdn.com',
    'i2.sndcdn.com',
    'i3.sndcdn.com',
    'i4.sndcdn.com',
    'i5.sndcdn.com',
    'i6.sndcdn.com',
    'i7.sndcdn.com', // SoundCloud
    'yt3.ggpht.com',
    'yt4.ggpht.com', // YouTube
  ];

  try {
    final uri = Uri.parse(url);
    if (corsRestrictedDomains.contains(uri.host)) {
      final encoded = Uri.encodeComponent(url);
      return '$_kBackendUrl/proxy/image?url=$encoded';
    }
  } catch (e) {
    debugPrint('[feedProvider._proxyArtworkUrl] Failed to parse URL: $url');
  }

  return url;
}

/// Parses a raw JSON list into FeedItems, applying the artwork proxy transform.
List<FeedItem> _parseFeedItems(List<dynamic> data, String logTag) {
  final items = <FeedItem>[];
  for (var i = 0; i < data.length; i++) {
    try {
      final parsed = FeedItem.fromJson(data[i] as Map<String, dynamic>);
      items.add(
        parsed.copyWith(artworkUrl: _proxyArtworkUrl(parsed.artworkUrl)),
      );
    } catch (e) {
      debugPrint('[$logTag] ERROR parsing item[$i]: $e');
      debugPrint('[$logTag] Raw item[$i]: ${data[i]}');
    }
  }
  return items;
}

class FeedNotifier extends AsyncNotifier<List<FeedItem>> {
  Dio? _dio;

  @override
  Future<List<FeedItem>> build() async {
    _dio = _createDio();
    final currentPreset = ref.watch(activePresetSlugProvider);

    // Debounce rapid preset switches: each notch click invalidates feedProvider,
    // queuing multiple concurrent build() calls. Register a dispose flag so that
    // when this scope is superseded by a newer build, we bail before firing HTTP.
    var cancelled = false;
    ref.onDispose(() => cancelled = true);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (cancelled) return const <FeedItem>[];

    debugPrint(
      '[feedProvider] Initialised - baseUrl=$_kBackendUrl user=$_kUserId preset=$currentPreset',
    );

    // Both requests fire simultaneously.
    // SC+YT returns in ~300ms (cache hits); BC may take 10s on cold start.
    debugPrint(
      '[feedProvider] Phase-1 firing: platforms=soundcloud,youtube zone=recent',
    );
    debugPrint(
      '[feedProvider] Phase-2 firing: platforms=bandcamp zone=recent (concurrent)',
    );
    final bcFuture = _fetchFeed(
      page: 1,
      presetSlug: currentPreset,
      zone: 'recent',
      platforms: 'bandcamp',
    );
    final fastItems = await _fetchFeed(
      page: 1,
      presetSlug: currentPreset,
      zone: 'recent',
      platforms: 'soundcloud,youtube',
    );

    // Guard: if the preset changed while SC+YT was in flight, discard results.
    // Without this check the stale HTTP response would still update state and
    // briefly show wrong-preset cards before the correct build overwrites them.
    if (cancelled || ref.read(activePresetSlugProvider) != currentPreset) {
      return const <FeedItem>[];
    }

    debugPrint(
      '[feedProvider] Phase-1 complete: ${fastItems.length} SC+YT items — rendering feed now',
    );

    // BC appends when ready without blocking the initial render.
    bcFuture
        .then((bcItems) {
          // Discard if this build was superseded (preset changed mid-flight).
          if (cancelled) return;
          debugPrint(
            '[feedProvider] Phase-2 BC response received: ${bcItems.length} items',
          );
          if (ref.read(activePresetSlugProvider) != currentPreset) {
            debugPrint(
              '[feedProvider] Phase-2 DISCARDED — preset changed from $currentPreset '
              'to ${ref.read(activePresetSlugProvider)} while BC was loading',
            );
            return;
          }
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
            // Mark new IDs BEFORE updating state so cards read the set on first build.
            final newIds = newBcItems
                .map((i) => '${i.platform}_${i.id}')
                .toSet();
            ref.read(newFeedItemIdsProvider.notifier).state = newIds;
            state = AsyncData(_sortNewestFirst([...current, ...newBcItems]));
            debugPrint(
              '[feedProvider] Phase-2 state updated — total items now '
              '${(state.valueOrNull ?? []).length} newAnimatingIds=${newIds.length}',
            );
          }
        })
        .catchError((Object e) {
          debugPrint(
            '[feedProvider] Phase-2 ERROR (feed still showing SC+YT): $e',
          );
        });

    return fastItems;
  }

  Dio _createDio() {
    return Dio(
      BaseOptions(
        baseUrl: _kBackendUrl,
        connectTimeout: const Duration(seconds: 90),
        receiveTimeout: const Duration(seconds: 90),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-User-Id': _kUserId,
        },
      ),
    );
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
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _fetchFeed(
        page: 1,
        presetSlug: presetSlug,
        seedDate: seedDate,
        zone: seedDate == null ? 'recent' : null,
      ),
    );
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
      final dio = _dio ??= _createDio();
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
        final merged = page == 1 ? items : [...existingItems, ...items];
        final pageLimit = requestFeedMode == FeedMode.fullFeed
            ? _kFullArchivePageLimit
            : _kArchivePageLimit;
        _hasMore = items.length == pageLimit;
        _nextPage = page + 1;
        state = AsyncData(merged);
      },
      error: (error, stackTrace) {
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
      final dio = Dio(
        BaseOptions(
          baseUrl: _kBackendUrl,
          connectTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 90),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'X-User-Id': _kUserId,
          },
        ),
      );
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
