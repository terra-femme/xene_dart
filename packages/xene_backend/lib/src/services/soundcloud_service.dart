import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';
import '../database.dart';
import '../utils/http_client.dart';
import 'api_analytics_service.dart';
import 'soundcloud_date_resolver.dart';

final _logger = Logger('SoundCloudService');

class _ScTrackCacheEntry {
  final List<FeedItem> items;
  final DateTime fetchedAt;
  _ScTrackCacheEntry(this.items, this.fetchedAt);
}

class _ScUserCacheEntry {
  final Map<String, dynamic> data;
  final DateTime fetchedAt;
  _ScUserCacheEntry(this.data, this.fetchedAt);
}

class _ScRepostMeta {
  const _ScRepostMeta({
    required this.repostedByName,
    required this.repostedAt,
    required this.feedSourcePath,
  });

  final String repostedByName;
  final DateTime? repostedAt;
  final String feedSourcePath;
}

class SoundCloudService {
  SoundCloudService(
    this._db, {
    ApiAnalyticsService? analytics,
    Dio? dio,
    DateTime Function()? now,
    bool? dateResolverV2,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _dateResolverV2Override = dateResolverV2,
       _dio =
           dio ??
           (analytics?.trackDio(_createDio(), 'soundcloud') ?? _createDio());

  final DatabaseService _db;
  static const _xenePlaylistTitle = 'XENE Tunes';

  // In-memory caches — mirrors soundcloud.py _cache (1h) and _user_id_cache (7d).
  final _trackCache = <String, _ScTrackCacheEntry>{};
  final _userCache = <String, _ScUserCacheEntry>{};
  static const _trackCacheTtl = Duration(hours: 1);
  static const _userCacheTtl = Duration(days: 7);

  final Dio _dio;
  final DateTime Function() _now;
  final bool? _dateResolverV2Override;
  static const _dateResolver = SoundCloudDateResolver();

  bool get _v2DatesEnabled =>
      _dateResolverV2Override ??
      Platform.environment['SC_DATE_RESOLVER_V2']?.toLowerCase() == 'true';

  static Dio _createDio() => Dio(
    BaseOptions(
      baseUrl: 'https://api.soundcloud.com',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ),
  )..httpClientAdapter = pooledKeepAliveAdapter();

  // Regex patterns for bio link extraction (mirrors soundcloud.py)
  static final _bioUrlPatterns = {
    'spotify': RegExp(r'open\.spotify\.com/(?:artist|user)/[a-zA-Z0-9]+'),
    'bandcamp': RegExp(r'[a-zA-Z0-9.-]+\.bandcamp\.com'),
    'patreon': RegExp(r'patreon\.com/[a-zA-Z0-9_-]+'),
    'gumroad': RegExp(r'gumroad\.com/[a-zA-Z0-9_-]+'),
    'youtube': RegExp(r'youtube\.com/(?:@|channel/|c/)[a-zA-Z0-9_-]+'),
    'twitter': RegExp(r'(?:twitter\.com|x\.com)/[a-zA-Z0-9_-]+'),
    'beatport': RegExp(r'beatport\.com/(?:artist|label)/[a-zA-Z0-9_-]+/\d+'),
    'discogs': RegExp(r'discogs\.com/(?:label|artist|release)/[0-9a-zA-Z._-]+'),
  };

  /// Fetch or Refresh OAuth token (Client Credentials).
  Future<String?> _getToken() async {
    const tokenKey = 'soundcloud_client_credentials';

    // 1. Check DB Cache
    final cached = await _db.getSystemCache(tokenKey);
    if (cached != null && cached['access_token'] != null) {
      return cached['access_token'] as String;
    }

    // 2. Fetch New Token
    final clientId = Platform.environment['SC_CLIENT_ID'];
    final clientSecret = Platform.environment['SC_CLIENT_SECRET'];

    if (clientId == null || clientSecret == null) {
      _logger.warning('SoundCloud credentials missing.');
      return null;
    }

    try {
      final authString = base64Encode(utf8.encode('$clientId:$clientSecret'));
      final response = await _dio.post<Map<String, dynamic>>(
        'https://secure.soundcloud.com/oauth/token',
        data: {'grant_type': 'client_credentials'},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Authorization': 'Basic $authString'},
        ),
      );

      final data = response.data!;
      final token = data['access_token'] as String;
      final expiresIn = data['expires_in'] as int;

      // Cache it
      await _db.setSystemCache(tokenKey, {
        'access_token': token,
      }, expiresAt: DateTime.now().add(Duration(seconds: expiresIn - 60)));

      return token;
    } catch (e) {
      _logger.severe('Failed to get SoundCloud client token: $e');
      return null;
    }
  }

  /// Refresh a user's OAuth token using their refresh_token.
  /// Per SoundCloud docs: client_id, client_secret, and refresh_token as form body params.
  /// Note: Basic Auth is only required for the client_credentials grant, not refresh_token.
  Future<Map<String, dynamic>?> refreshUserToken(String refreshToken) async {
    final clientId = Platform.environment['SC_CLIENT_ID'];
    final clientSecret = Platform.environment['SC_CLIENT_SECRET'];

    if (clientId == null || clientSecret == null) {
      _logger.warning('SoundCloud credentials missing for refresh.');
      return null;
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'https://secure.soundcloud.com/oauth/token',
        data: {
          'grant_type': 'refresh_token',
          'client_id': clientId,
          'client_secret': clientSecret,
          'refresh_token': refreshToken,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      return response.data;
    } catch (e) {
      _logger.severe('Failed to refresh SoundCloud user token: $e');
      return null;
    }
  }

  /// Revoke a user's OAuth access token upstream at SoundCloud.
  ///
  /// Calls the documented sign-out endpoint:
  ///   POST https://secure.soundcloud.com/sign-out  body: {"access_token": ...}
  /// which terminates the SC session and invalidates the token for further API
  /// use (https://developers.soundcloud.com/docs).
  ///
  /// Best-effort: returns true if the token is no longer usable upstream, false
  /// on any failure. NEVER throws — the disconnect route must still delete the
  /// local row even if SoundCloud is unreachable or the token was already dead.
  Future<bool> revokeUserToken(String accessToken) async {
    _logger.info(
      '[sc] revokeUserToken: revoking access token upstream '
      '(len=${accessToken.length})',
    );
    try {
      final response = await _dio.post<dynamic>(
        'https://secure.soundcloud.com/sign-out',
        data: jsonEncode({'access_token': accessToken}),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          // SC returns 401 when the token is already invalid. Treat <500 as
          // "handled" so an already-dead token is not surfaced as a Dio error.
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 200) {
        _logger.info('[sc] revokeUserToken: SC token revoked (status=200)');
        return true;
      }
      if (status == 401) {
        // 401 = "this token is associated with a session that is already
        // invalid" — from our perspective the token is dead, so count it as
        // revoked rather than a failure.
        _logger.info(
          '[sc] revokeUserToken: token already invalid upstream (status=401) '
          '— treating as revoked',
        );
        return true;
      }
      _logger.warning(
        '[sc] revokeUserToken: unexpected status=$status body=${response.data}',
      );
      return false;
    } catch (e) {
      _logger.warning('[sc] revokeUserToken: revoke request failed: $e');
      return false;
    }
  }

  /// Resolve a username to a User ID.
  /// Accepts either a plain username (e.g., "ghostemane") or a full SoundCloud
  /// profile URL (e.g., "https://soundcloud.com/ghostemane"). Validates URLs
  /// are legitimate SoundCloud domains to prevent SSRF attacks.
  Future<Map<String, dynamic>?> _resolveUserInfo(String username) async {
    final token = await _getToken();
    if (token == null) return null;

    // Normalize username
    var cleanUsername = username;
    if (username.contains('soundcloud.com/')) {
      // If a full URL was provided, validate it's a legitimate SoundCloud URL
      if (!isSoundCloudProfileUrl(username)) {
        _logger.warning(
          '[sc] _resolveUserInfo: rejected non-SoundCloud URL: $username',
        );
        return null;
      }
      try {
        final uri = Uri.parse(username);
        cleanUsername = uri.path.split('/').where((p) => p.isNotEmpty).first;
      } catch (_) {
        return null;
      }
    } else if (username.contains('/')) {
      // Reject URLs with paths that don't look like SoundCloud usernames
      cleanUsername = username.split('/').where((p) => p.isNotEmpty).first;
    }

    // Check in-memory user cache (7-day TTL — mirrors soundcloud.py _user_id_cache).
    final userCached = _userCache[cleanUsername];
    if (userCached != null &&
        DateTime.now().toUtc().difference(userCached.fetchedAt) <
            _userCacheTtl) {
      _logger.info('[sc] User cache HIT for $cleanUsername');
      return userCached.data;
    }

    try {
      final profileUrl = 'https://soundcloud.com/$cleanUsername';
      final response = await _dio.get<Map<String, dynamic>>(
        '/resolve',
        queryParameters: {'url': profileUrl},
        options: Options(headers: {'Authorization': 'OAuth $token'}),
      );

      if (response.data != null) {
        _userCache[cleanUsername] = _ScUserCacheEntry(
          response.data!,
          DateTime.now().toUtc(),
        );
      }
      return response.data;
    } catch (e) {
      _logger.warning('Failed to resolve SoundCloud user $cleanUsername: $e');
      return null;
    }
  }

  /// Official SoundCloud web-profiles fetch.
  Future<Map<String, dynamic>> fetchWebProfiles(String scProfileUrl) async {
    final token = await _getToken();
    if (token == null) return {};

    try {
      final resolved = await resolveProfileUrl(scProfileUrl);
      if (resolved == null) return {};

      final userId = resolved['id'];
      final response = await _dio.get<List<dynamic>>(
        '/users/$userId/web-profiles',
        options: Options(headers: {'Authorization': 'OAuth $token'}),
      );

      final out = <String, dynamic>{};
      // Expanded domain→network map — covers all common artist platforms
      final domainToNetwork = {
        'bandcamp.com': 'bandcamp',
        'spotify.com': 'spotify',
        'youtube.com': 'youtube',
        'twitter.com': 'twitter',
        'x.com': 'twitter',
        'facebook.com': 'facebook',
        'discogs.com': 'discogs',
        'instagram.com': 'instagram',
        'twitch.tv': 'twitch',
        'tiktok.com': 'tiktok',
        'patreon.com': 'patreon',
        'gumroad.com': 'gumroad',
        'beatport.com': 'beatport',
        'tumblr.com': 'tumblr',
        'pinterest.com': 'pinterest',
        'linktr.ee': 'linktree',
        'soundcloud.com': 'soundcloud',
      };

      for (final p in (response.data ?? [])) {
        final profile = p as Map<String, dynamic>;
        var network = (profile['network'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final purl = (profile['url'] ?? '').toString().trim();

        if (purl.isEmpty) continue;

        // Always try domain inference — SC's network field can be unreliable
        try {
          final host = Uri.parse(purl).host.toLowerCase();
          for (final entry in domainToNetwork.entries) {
            if (host == entry.key || host.endsWith('.${entry.key}')) {
              network = entry.value;
              break;
            }
          }
        } catch (_) {}

        // Fallback: use title if network still unknown
        if (network.isEmpty) {
          network = (profile['title'] ?? '').toString().trim().toLowerCase();
        }

        if (network.isEmpty || network == 'soundcloud') continue;

        final slug = purl.replaceAll(RegExp(r'/$'), '').split('/').last;
        out[network] = {'id': slug, 'url': purl, 'title': profile['title']};
      }
      return out;
    } catch (e) {
      _logger.warning('Failed to fetch SoundCloud web-profiles: $e');
      return {};
    }
  }

  /// Parse raw bio text for explicit intent links.
  Map<String, String> extractLinksFromBio(String? bioText) {
    final found = <String, String>{};
    if (bioText == null || bioText.isEmpty) return found;

    for (final entry in _bioUrlPatterns.entries) {
      final match = entry.value.firstMatch(bioText);
      if (match != null) {
        var url = match.group(0)!;
        if (!url.startsWith('http')) url = 'https://$url';
        found[entry.key] = url;
      }
    }
    return found;
  }

  /// Resolve a full SC profile URL and return the user object.
  /// Resolve a SoundCloud profile URL to user metadata.
  /// Validates the URL is a legitimate SoundCloud domain before making any
  /// HTTP request to prevent SSRF attacks.
  Future<Map<String, dynamic>?> resolveProfileUrl(String scUrl) async {
    if (!isSoundCloudProfileUrl(scUrl)) {
      _logger.warning(
        '[sc] resolveProfileUrl: rejected non-SoundCloud URL: $scUrl',
      );
      throw ArgumentError('URL must be a valid soundcloud.com profile URL');
    }

    final token = await _getToken();
    if (token == null) return null;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/resolve',
        queryParameters: {'url': scUrl},
        options: Options(headers: {'Authorization': 'OAuth $token'}),
      );
      return response.data;
    } catch (e) {
      _logger.warning('Failed to resolve SoundCloud profile URL $scUrl: $e');
      return null;
    }
  }

  /// Fetch tracks + own playlists (EPs) + reposts for an artist.
  /// If [auditSink] is supplied, raw date fields are appended per item
  /// (keyed by the FeedItem id) for the audit report.
  Future<List<FeedItem>> getTracks(
    String username,
    String? displayName, {
    bool bypassMemoryCache = false,
    List<Map<String, dynamic>>? auditSink,
  }) async {
    print('[SC] getTracks called: username=$username displayName=$displayName');

    // Check in-memory track cache (1-hour TTL).
    final trackCached = _trackCache[username];
    if (!bypassMemoryCache &&
        trackCached != null &&
        _now().toUtc().difference(trackCached.fetchedAt) < _trackCacheTtl) {
      _logger.info(
        '[sc] Track cache HIT for $username (${trackCached.items.length} items)',
      );
      return trackCached.items;
    }

    final token = await _getToken();
    if (token == null) return [];

    final userData = await _resolveUserInfo(username);
    if (userData == null) return [];

    final userId = userData['id'].toString();
    final artistDisplayName = displayName ?? userData['username'];
    final avatarUrl = (userData['avatar_url'] as String?)
        .toString()
        .replaceFirst('-large.', '-t500x500.');

    final items = <FeedItem>[];
    final repostMetaById = <String, _ScRepostMeta>{};
    final cutoff = _now().toUtc().subtract(const Duration(days: 31));

    // 1. Fetch own tracks
    final tracks = await _getCollection(
      '/users/$userId/tracks',
      token,
      cutoffDate: cutoff,
      auditSink: auditSink,
    );
    await _verifyAnomalousPublicDates(tracks, token);
    _parseScTracks(
      tracks,
      items,
      artistDisplayName,
      avatarUrl,
      auditSink: auditSink,
      repostMetaById: repostMetaById,
    );

    // 2. Fetch own playlists (EPs/Albums) - CRUCIAL for Nixxy Rain
    final ownPlaylists = await _getCollection(
      '/users/$userId/playlists',
      token,
      cutoffDate: cutoff,
      auditSink: auditSink,
    );
    await _verifyAnomalousPublicDates(ownPlaylists, token);
    _parseScPlaylists(
      ownPlaylists,
      items,
      artistDisplayName,
      avatarUrl,
      auditSink: auditSink,
      repostMetaById: repostMetaById,
    );

    // 3. Fetch track reposts
    final trackReposts = await _getCollection(
      '/users/$userId/reposts/tracks',
      token,
      cutoffDate: cutoff,
      auditSink: auditSink,
    );
    await _verifyAnomalousPublicDates(trackReposts, token);
    _parseScTracks(
      trackReposts,
      items,
      artistDisplayName,
      avatarUrl,
      auditSink: auditSink,
      repostMetaById: repostMetaById,
    );

    // 4. Fetch playlist reposts
    final playlistReposts = await _getCollection(
      '/users/$userId/reposts/playlists',
      token,
      cutoffDate: cutoff,
      auditSink: auditSink,
    );
    await _verifyAnomalousPublicDates(playlistReposts, token);
    _parseScPlaylists(
      playlistReposts,
      items,
      artistDisplayName,
      avatarUrl,
      auditSink: auditSink,
      repostMetaById: repostMetaById,
    );

    // Sort, trim to window, save.
    // Pre-orders (future publishedAt) are kept; only past-31d items are dropped.
    items.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final windowItems = items
        .where((i) => i.publishedAt.isAfter(cutoff) || i.isUpcoming)
        .toList();

    // V2 must also persist corrected items that fall outside the display
    // window. Otherwise an old cache row with bad future metadata survives
    // forever because the corrected public date is no longer recent.
    final persistenceItems = _v2DatesEnabled ? items : windowItems;
    final dbItems = persistenceItems.map((i) {
      final repostMeta = repostMetaById[i.id];
      return {
        'platform': i.platform,
        'internal_id': i.id,
        'artist_name': artistDisplayName,
        'content_type': i.contentType,
        'title': i.title,
        'body': i.body,
        'artwork_url': i.artworkUrl,
        'external_url': i.externalUrl,
        'published_at': i.publishedAt.toIso8601String(),
        'source_created_at': i.sourceCreatedAt?.toIso8601String(),
        'source_display_at': i.displayAt?.toIso8601String(),
        'source_release_at': i.releaseAt?.toIso8601String(),
        'source_last_modified_at': i.sourceLastModifiedAt?.toIso8601String(),
        'date_source': i.dateSource,
        'date_confidence': i.dateConfidence,
        'date_conflict_reason': i.dateConflictReason,
        'is_upcoming': i.isUpcoming,
        'duration_seconds': i.durationSeconds,
        'play_count': i.playCount,
        'like_count': i.likeCount,
        'track_count': i.trackCount,
        'is_repost': repostMeta != null,
        'reposted_by_name': repostMeta?.repostedByName,
        'reposted_at': repostMeta?.repostedAt?.toUtc().toIso8601String(),
        'feed_source_path': repostMeta?.feedSourcePath,
        'updated_at': _now().toUtc().toIso8601String(),
      };
    }).toList();

    await _db.saveFeedItems(dbItems);

    // Extract genre signals from SC user profile for the discovery system.
    // Uses the canonical SC username from the API (userData['username']) which
    // matches the soundcloud_username key stored in the artists table.
    // Non-fatal — genre update failure must never abort the feed fetch.
    final scApiUsername = (userData['username'] as String?)
        ?.toLowerCase()
        .trim();
    if (scApiUsername != null) {
      final scGenre = userData['genre'] as String?;
      final scTagList = userData['tag_list'] as String?;
      final genreTags = _parseScGenreTags(scGenre, scTagList);
      if (genreTags.isNotEmpty) {
        _logger.info('[sc] Genre tags for $scApiUsername: $genreTags');
        await _db
            .updateArtistGenreTags(genreTags, soundcloudUsername: scApiUsername)
            .catchError((Object e) {
              _logger.warning(
                '[sc] Genre tags update skipped for $scApiUsername: $e',
              );
            });
      }
    }

    // Write to in-memory track cache.
    _trackCache[username] = _ScTrackCacheEntry(windowItems, _now().toUtc());
    _logger.info(
      '[sc] Track cache WRITE for $username (${windowItems.length} items)',
    );

    return windowItems;
  }

  /// Helper to handle SoundCloud's paginated collection responses.
  /// Stops paginating once all items on a page are older than [cutoffDate].
  /// If [auditSink] is supplied, appends a `type: 'fetch_collection'` entry
  /// after the fetch completes with page count and raw item count.
  Future<List<dynamic>> _getCollection(
    String path,
    String token, {
    DateTime? cutoffDate,
    List<Map<String, dynamic>>? auditSink,
  }) async {
    const pageLimit = 50;
    const maxPages = 10;
    final items = <dynamic>[];
    var pagesActual = 0;
    var earlyExit = false;

    try {
      String? nextPath = path;
      Map<String, dynamic>? queryParameters = {
        'linked_partitioning': true,
        'limit': pageLimit,
      };

      for (var page = 0; page < maxPages && nextPath != null; page++) {
        pagesActual = page + 1;
        final response = await _dio.get<dynamic>(
          nextPath,
          queryParameters: queryParameters,
          options: Options(headers: {'Authorization': 'OAuth $token'}),
        );

        final data = response.data;
        if (data is Map && data.containsKey('collection')) {
          final collection = data['collection'] as List<dynamic>? ?? [];
          items.addAll(collection);

          // Stop paginating if every item on this page is older than cutoff.
          // Use the public-facing date (display_date → release_date → created_at)
          // so privately-uploaded-then-recently-released tracks are not missed.
          if (cutoffDate != null && collection.isNotEmpty) {
            final allOld = collection.every((item) {
              if (item is! Map) return false;
              final raw =
                  (item['display_date'] ??
                          item['release_date'] ??
                          item['created_at'] ??
                          item['last_modified'])
                      as String?;
              if (raw == null) return false;
              final dt = DateTime.tryParse(raw)?.toUtc();
              return dt != null && dt.isBefore(cutoffDate);
            });
            if (allOld) {
              _logger.info(
                '[sc] Collection $path early-exit at page $page — all items older than cutoff',
              );
              earlyExit = true;
              break;
            }
          }

          final nextHref = data['next_href'] as String?;
          if (nextHref == null || nextHref.isEmpty) break;

          final nextUri = Uri.parse(nextHref);
          nextPath = nextUri.path;
          queryParameters = nextUri.queryParameters;
        } else if (data is List) {
          items.addAll(data);
          pagesActual = 1;
          break;
        } else {
          break;
        }
      }

      _logger.info('[sc] Collection $path fetched ${items.length} items');
      auditSink?.add({
        'type': 'fetch_collection',
        'endpoint': path,
        'pages_fetched': pagesActual,
        'items_received': items.length,
        'early_exit': earlyExit,
      });
      return items;
    } catch (e) {
      _logger.warning('[sc] Failed to fetch collection at $path: $e');
      auditSink?.add({
        'type': 'fetch_collection',
        'endpoint': path,
        'pages_fetched': pagesActual,
        'items_received': items.length,
        'early_exit': earlyExit,
        'error': e.toString(),
      });
      return [];
    }
  }

  Future<void> _verifyAnomalousPublicDates(
    List<dynamic> rows,
    String token,
  ) async {
    var verified = 0;
    for (final raw in rows) {
      if (verified >= 8 || raw is! Map) break;
      final wrapper = Map<String, dynamic>.from(raw);
      final nested = wrapper['track'] ?? wrapper['playlist'];
      final item = nested is Map ? Map<String, dynamic>.from(nested) : wrapper;
      final preview = _dateResolver.resolve(item, now: _now());
      if (preview.releaseAt == null ||
          !preview.releaseAt!.isAfter(_now().toUtc())) {
        continue;
      }
      final url = item['permalink_url'];
      if (url is! String || url.isEmpty) continue;
      try {
        final response = await _dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        final pageItem = _hydratedResource(response.data ?? '', item['id']);
        final displayAt = _dateResolver.parseDate(pageItem?['display_date']);
        if (displayAt == null) continue;
        item['_xene_verified_display_date'] = displayAt.toIso8601String();
        final conflictReason = await _duplicatePlaylistConflict(item, token);
        if (conflictReason != null) {
          item['_xene_verified_conflict_reason'] = conflictReason;
        }
        if (nested is Map) {
          nested['_xene_verified_display_date'] = displayAt.toIso8601String();
          if (conflictReason != null) {
            nested['_xene_verified_conflict_reason'] = conflictReason;
          }
        } else {
          raw['_xene_verified_display_date'] = displayAt.toIso8601String();
          if (conflictReason != null) {
            raw['_xene_verified_conflict_reason'] = conflictReason;
          }
        }
        verified++;
      } catch (e) {
        _logger.warning(
          '[sc-date] public verification failed id=${item['id']}: $e',
        );
      }
    }
  }

  Future<String?> _duplicatePlaylistConflict(
    Map<String, dynamic> item,
    String token,
  ) async {
    if (item['kind'] != 'playlist') return null;
    final sourceIds = _trackIds(item);
    if (sourceIds.isEmpty) return null;
    final title = item['title']?.toString() ?? '';
    final query = title
        .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), ' ')
        .trim();
    if (query.isEmpty) return null;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/playlists',
        queryParameters: {'q': query, 'limit': 20, 'linked_partitioning': true},
        options: Options(headers: {'Authorization': 'OAuth $token'}),
      );
      final candidates = response.data?['collection'];
      if (candidates is! List) return null;
      for (final raw in candidates) {
        if (raw is! Map) continue;
        final candidate = Map<String, dynamic>.from(raw);
        if (candidate['id']?.toString() == item['id']?.toString()) continue;
        final candidateIds = _trackIds(candidate);
        if (candidateIds.length != sourceIds.length ||
            !candidateIds.containsAll(sourceIds)) {
          continue;
        }
        final candidateDate =
            _dateResolver.parseDate(candidate['display_date']) ??
            _dateResolver.parseDate(candidate['created_at']);
        if (candidateDate != null && !candidateDate.isAfter(_now().toUtc())) {
          return 'duplicate_playlist_same_tracks_with_past_date';
        }
      }
    } catch (e) {
      _logger.warning(
        '[sc-date] duplicate playlist check failed id=${item['id']}: $e',
      );
    }
    return null;
  }

  Set<String> _trackIds(Map<String, dynamic> playlist) {
    final tracks = playlist['tracks'];
    if (tracks is! List) return const {};
    return tracks
        .whereType<Map>()
        .map((track) => track['id']?.toString())
        .whereType<String>()
        .toSet();
  }

  Map<String, dynamic>? _hydratedResource(String html, Object? expectedId) {
    final match = RegExp(
      r'window\.__sc_hydration\s*=\s*(\[.*?\]);\s*</script>',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) return null;
    try {
      final entries = jsonDecode(match.group(1)!) as List<dynamic>;
      for (final raw in entries) {
        if (raw is! Map) continue;
        final data = raw['data'];
        if (data is! Map) continue;
        if (data['id']?.toString() == expectedId?.toString()) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (_) {}
    return null;
  }

  SoundCloudDateResolution _resolveDate(
    Map<String, dynamic> item, {
    DateTime? repostedAt,
  }) {
    return _dateResolver.resolve(
      item,
      repostedAt: repostedAt,
      verifiedDisplayAt: _dateResolver.parseDate(
        item['_xene_verified_display_date'],
      ),
      verifiedConflictReason: item['_xene_verified_conflict_reason']
          ?.toString(),
      now: _now(),
    );
  }

  void _logShadowDateDifference(
    Map<String, dynamic> item,
    SoundCloudDateResolution resolution,
  ) {
    if (_v2DatesEnabled ||
        resolution.legacyPublishedAt == resolution.publishedAt) {
      return;
    }
    _logger.warning(
      '[sc-date-shadow] ${jsonEncode({'id': item['id'], 'title': item['title'], 'legacy_published_at': resolution.legacyPublishedAt.toIso8601String(), 'v2_published_at': resolution.publishedAt.toIso8601String(), 'release_at': resolution.releaseAt?.toIso8601String(), 'is_upcoming': resolution.isUpcoming, 'confidence': resolution.confidence, 'conflict_reason': resolution.conflictReason})}',
    );
  }

  /// Search SoundCloud users by name — used as the source-of-truth lookup.
  Future<List<Map<String, dynamic>>> searchUsers(
    String query, {
    int limit = 10,
  }) async {
    final token = await _getToken();
    if (token == null) return [];

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/users',
        queryParameters: {
          'q': query,
          'limit': limit,
          'linked_partitioning': true,
        },
        options: Options(headers: {'Authorization': 'OAuth $token'}),
      );
      final collection = (response.data?['collection'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      _logger.info('[sc] searchUsers "$query": ${collection.length} results');
      return collection;
    } catch (e) {
      _logger.warning('[sc] searchUsers failed for "$query": $e');
      return [];
    }
  }

  /// Search SoundCloud tracks by query string.
  /// Returns up to [limit] track objects with the fields needed for party submission.
  Future<List<Map<String, dynamic>>> searchTracks(
    String query, {
    int limit = 10,
  }) async {
    final token = await _getToken();
    if (token == null) return [];

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/tracks',
        queryParameters: {
          'q': query,
          'limit': limit,
          'linked_partitioning': true,
        },
        options: Options(headers: {'Authorization': 'OAuth $token'}),
      );
      final collection = (response.data?['collection'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      _logger.info('[sc] searchTracks "$query": ${collection.length} results');

      return collection.map((t) {
        final artworkRaw = t['artwork_url'] as String?;
        final artwork = artworkRaw?.replaceFirst('-large', '-t500x500');
        final durationMs = t['duration'] as int? ?? 0;
        return {
          'id': t['id']?.toString() ?? '',
          'title': t['title'] as String? ?? 'Unknown',
          'artwork_url': artwork,
          'duration_seconds': (durationMs / 1000).round(),
          'permalink_url': t['permalink_url'] as String? ?? '',
          'username': (t['user'] as Map?)?['username'] as String? ?? 'Unknown',
        };
      }).toList();
    } catch (e) {
      _logger.warning('[sc] searchTracks failed for "$query": $e');
      return [];
    }
  }

  /// Resolve a track's directly-playable stream URL using the official token.
  ///
  /// SoundCloud's `/tracks/{id}/stream` (singular) 302-redirects to a signed
  /// CloudFront URL (`cf-media.sndcdn.com` / `cf-preview-media…`) whose auth is
  /// baked into the query string (Policy/Signature/Key-Pair-Id) — so it's
  /// fetchable by a native player with **no** Authorization header.
  ///
  /// We deliberately do NOT return the `/streams` JSON fields (`http_mp3_128_url`
  /// etc.): those stay on `api.soundcloud.com` and still require the OAuth
  /// header, which a client (ExoPlayer/just_audio) can't send → 401. Verified
  /// live 2026-07-06 against track 932965966.
  ///
  /// NOTE: with app client-credentials this resolves to a ~30s PREVIEW
  /// (`cf-preview-media`) for most tracks; full-length streams require
  /// user-level rights the app token doesn't carry.
  Future<String?> getStreamUrl(String trackId) async {
    final token = await _getToken();
    if (token == null) return null;

    try {
      final response = await _dio.get<dynamic>(
        '/tracks/$trackId/stream',
        options: Options(
          headers: {'Authorization': 'OAuth $token'},
          followRedirects: false, // capture the 302 Location ourselves
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      final location = response.headers.value('location');
      if (location == null || location.isEmpty) {
        _logger.warning(
          '[sc] getStreamUrl: no Location on /stream redirect for $trackId '
          '(status=${response.statusCode})',
        );
        return null;
      }
      _logger.info(
        '[sc] getStreamUrl resolved $trackId → signed CDN url '
        '(len=${location.length})',
      );
      return location;
    } catch (e) {
      _logger.warning('Failed to resolve SoundCloud stream for $trackId: $e');
      return null;
    }
  }

  /// Creates a public SoundCloud playlist on behalf of a user.
  /// [accessToken] is the user's OAuth token (not the app client token).
  /// Returns the playlist permalink URL, or null if SC returns no URL.
  Future<String?> createScPlaylist({
    required String accessToken,
    required String title,
    required List<String> scTrackIds,
  }) async {
    if (scTrackIds.isEmpty) return null;

    final trackIds = await _expandScTrackIds(accessToken, scTrackIds);
    final tracks = trackIds.map((id) => {'id': id}).toList();

    if (tracks.isEmpty) return null;

    _logger.info(
      '[sc] createScPlaylist title="$title" tracks=${tracks.length}',
    );

    // Explicitly encode to JSON string so Dio sends the body as-is.
    // Passing a Map with a custom contentType can cause Dio to form-encode
    // instead of JSON-encode, which SC rejects with 422.
    final body = jsonEncode({
      'playlist': {'title': title, 'sharing': 'public', 'tracks': tracks},
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/playlists',
      data: body,
      options: Options(
        headers: {
          'Authorization': 'OAuth $accessToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    final url = response.data?['permalink_url'] as String?;
    _logger.info('[sc] createScPlaylist success: url=$url');
    return url;
  }

  /// Adds tracks to a user's persisted private Xene playlist.
  ///
  /// SoundCloud playlist updates require sending the complete track list, so we
  /// fetch the current playlist, merge in new track IDs, then PUT the full list.
  Future<String?> addToXenePlaylist({
    required String accessToken,
    required String userId,
    required List<String> scTrackIds,
  }) async {
    final newTrackIds = await _expandScTrackIds(accessToken, scTrackIds);
    if (newTrackIds.isEmpty) return null;

    final playlist = await _getOrCreateXenePlaylist(
      accessToken,
      userId,
      initialTrackIds: newTrackIds,
    );
    if (playlist == null) return null;

    final playlistId = _resourceIdText(playlist['id']);
    if (playlistId == null) return null;

    final existingTrackIds = _extractPlaylistTrackIds(playlist).toList();
    final mergedTrackIds = LinkedHashSet<String>.from(existingTrackIds)
      ..addAll(newTrackIds);
    final tracks = mergedTrackIds.map((id) => {'id': id}).toList();

    _logger.info(
      '[sc] addToXenePlaylist playlist=$playlistId '
      'existing=${existingTrackIds.length} incoming=${newTrackIds.length} '
      'merged=${tracks.length}',
    );

    final body = jsonEncode({
      'playlist': {
        'title': _xenePlaylistTitle,
        'sharing': 'private',
        'tracks': tracks,
      },
    });

    final response = await _dio.put<Map<String, dynamic>>(
      '/playlists/$playlistId',
      data: body,
      options: Options(
        headers: {
          'Authorization': 'OAuth $accessToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    final updated = response.data;
    await _cacheXenePlaylist(userId, updated);
    return _playlistUrl(updated);
  }

  /// Replaces the user's private queue playback playlist with this exact track
  /// order and returns a secret-token URL that the widget can embed.
  Future<String?> replaceQueuePlaybackPlaylist({
    required String accessToken,
    required String userId,
    required List<String> scTrackIds,
  }) async {
    final trackIds = await _expandScTrackIds(accessToken, scTrackIds);
    if (trackIds.isEmpty) return null;

    final playlist = await _getOrCreateCachedPlaylist(
      accessToken: accessToken,
      userId: userId,
      cachePrefix: 'soundcloud:queue_playlist',
      title: 'Xene Queue',
      initialTrackIds: trackIds,
    );
    if (playlist == null) return null;

    final playlistId = _resourceIdText(playlist['id']);
    if (playlistId == null) return null;

    final body = jsonEncode({
      'playlist': {
        'title': 'Xene Queue',
        'sharing': 'private',
        'tracks': trackIds.map((id) => {'id': id}).toList(),
      },
    });

    final response = await _dio.put<Map<String, dynamic>>(
      '/playlists/$playlistId',
      data: body,
      options: Options(
        headers: {
          'Authorization': 'OAuth $accessToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    final updated = response.data;
    await _cachePlaylist(
      cachePrefix: 'soundcloud:queue_playlist',
      userId: userId,
      playlist: updated,
      fallbackTitle: 'Xene Queue',
    );
    return _playlistUrl(updated);
  }

  Future<Map<String, dynamic>?> _getOrCreateXenePlaylist(
    String accessToken,
    String userId, {
    required List<String> initialTrackIds,
  }) async {
    return _getOrCreateCachedPlaylist(
      accessToken: accessToken,
      userId: userId,
      cachePrefix: 'soundcloud:xene_playlist',
      title: _xenePlaylistTitle,
      initialTrackIds: initialTrackIds,
    );
  }

  Future<Map<String, dynamic>?> _getOrCreateCachedPlaylist({
    required String accessToken,
    required String userId,
    required String cachePrefix,
    required String title,
    required List<String> initialTrackIds,
  }) async {
    final cached = await _getCachedPlaylist(
      accessToken: accessToken,
      userId: userId,
      cachePrefix: cachePrefix,
    );
    if (cached != null) return cached;

    final initialTracks = initialTrackIds.map((id) => {'id': id}).toList();
    final body = jsonEncode({
      'playlist': {
        'title': title,
        'sharing': 'private',
        'tracks': initialTracks,
      },
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/playlists',
      data: body,
      options: Options(
        headers: {
          'Authorization': 'OAuth $accessToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    final playlist = response.data;
    await _cachePlaylist(
      cachePrefix: cachePrefix,
      userId: userId,
      playlist: playlist,
      fallbackTitle: title,
    );
    _logger.info('[sc] Created private playlist "$title" for user=$userId');
    return playlist;
  }

  Future<Map<String, dynamic>?> _getCachedPlaylist({
    required String accessToken,
    required String userId,
    required String cachePrefix,
  }) async {
    final cached = await _db.getSystemCache(
      _playlistCacheKey(cachePrefix, userId),
    );
    final playlistId = _resourceIdText(cached?['playlist_id']);
    if (playlistId == null) return null;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/playlists/$playlistId',
        queryParameters: {'show_tracks': true},
        options: Options(headers: {'Authorization': 'OAuth $accessToken'}),
      );
      final playlist = response.data;
      if (playlist != null) {
        await _cachePlaylist(
          cachePrefix: cachePrefix,
          userId: userId,
          playlist: playlist,
          fallbackTitle: cached?['title'] as String? ?? 'Xene Playlist',
        );
      }
      return playlist;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _logger.warning(
          '[sc] Cached Xene playlist $playlistId not found; recreating',
        );
        return null;
      }
      rethrow;
    }
  }

  Future<void> _cacheXenePlaylist(
    String userId,
    Map<String, dynamic>? playlist,
  ) => _cachePlaylist(
    cachePrefix: 'soundcloud:xene_playlist',
    userId: userId,
    playlist: playlist,
    fallbackTitle: _xenePlaylistTitle,
  );

  Future<void> _cachePlaylist({
    required String cachePrefix,
    required String userId,
    required Map<String, dynamic>? playlist,
    required String fallbackTitle,
  }) async {
    final playlistId = _resourceIdText(playlist?['id']);
    if (playlistId == null) return;
    await _db.setSystemCache(_playlistCacheKey(cachePrefix, userId), {
      'playlist_id': playlistId,
      'playlist_url': _playlistUrl(playlist),
      'title': playlist?['title'] ?? fallbackTitle,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  String _playlistCacheKey(String cachePrefix, String userId) =>
      '$cachePrefix:$userId';

  String? _playlistUrl(Map<String, dynamic>? playlist) {
    final permalinkUrl = playlist?['permalink_url'] as String?;
    if (permalinkUrl == null || permalinkUrl.isEmpty) return null;

    final secretToken = playlist?['secret_token'] as String?;
    if (secretToken == null || secretToken.isEmpty) return permalinkUrl;

    final uri = Uri.parse(permalinkUrl);
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'secret_token': secretToken,
          },
        )
        .toString();
  }

  Future<List<String>> _expandScTrackIds(
    String accessToken,
    List<String> rawIds,
  ) async {
    final ids = LinkedHashSet<String>();

    for (final raw in rawIds) {
      final value = raw.trim();
      if (value.isEmpty) continue;

      final directId = int.tryParse(value);
      if (directId != null) {
        ids.add(directId.toString());
        continue;
      }

      final playlistMatch = RegExp(r'^playlist-(\d+)$').firstMatch(value);
      if (playlistMatch != null) {
        final playlistId = playlistMatch.group(1)!;
        ids.addAll(await _getPlaylistTrackIds(accessToken, playlistId));
        continue;
      }

      if (value.startsWith('http://') || value.startsWith('https://')) {
        ids.addAll(await _resolveTrackIdsFromUrl(accessToken, value));
      }
    }

    return ids.toList();
  }

  Future<List<String>> _resolveTrackIdsFromUrl(
    String accessToken,
    String url,
  ) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/resolve',
        queryParameters: {'url': url},
        options: Options(headers: {'Authorization': 'OAuth $accessToken'}),
      );
      final data = response.data;
      if (data == null) return const [];

      final kind = data['kind'] as String?;
      final id = data['id'];
      final idText = _resourceIdText(id);
      if (kind == 'track' && idText != null) return [idText];
      if (kind == 'playlist' && idText != null) {
        final embeddedTracks = _extractPlaylistTrackIds(data).toList();
        if (embeddedTracks.isNotEmpty) return embeddedTracks;
        // await, so a failure in the playlist lookup is caught below and logged
        // against this URL rather than escaping as an unhandled async error.
        return await _getPlaylistTrackIds(accessToken, idText);
      }
    } catch (e) {
      _logger.warning('[sc] Failed to resolve export URL $url: $e');
    }
    return const [];
  }

  Future<List<String>> _getPlaylistTrackIds(
    String accessToken,
    String playlistId,
  ) async {
    try {
      final tracksResponse = await _dio.get<dynamic>(
        '/playlists/$playlistId/tracks',
        options: Options(headers: {'Authorization': 'OAuth $accessToken'}),
      );
      final tracks = _extractTrackIds(tracksResponse.data).toList();
      if (tracks.isNotEmpty) return tracks;

      final playlistResponse = await _dio.get<Map<String, dynamic>>(
        '/playlists/$playlistId',
        queryParameters: {'show_tracks': true},
        options: Options(headers: {'Authorization': 'OAuth $accessToken'}),
      );
      return _extractPlaylistTrackIds(playlistResponse.data).toList();
    } catch (e) {
      _logger.warning(
        '[sc] Failed to expand playlist $playlistId for export: $e',
      );
      return const [];
    }
  }

  Iterable<String> _extractPlaylistTrackIds(
    Map<String, dynamic>? playlist,
  ) sync* {
    final tracks = playlist?['tracks'];
    yield* _extractTrackIds(tracks);
  }

  Iterable<String> _extractTrackIds(Object? tracks) sync* {
    if (tracks is! List) return;
    for (final item in tracks) {
      if (item is Map<String, dynamic>) {
        final id = _resourceIdText(item['id']);
        if (id != null) yield id;
      }
    }
  }

  String? _resourceIdText(Object? id) {
    if (id is int) return id.toString();
    if (id is String && id.trim().isNotEmpty) return id.trim();
    return null;
  }

  void _parseScTracks(
    List<dynamic> data,
    List<FeedItem> items,
    String artistName,
    String avatarUrl, {
    List<Map<String, dynamic>>? auditSink,
    Map<String, _ScRepostMeta>? repostMetaById,
  }) {
    for (var trackData in data) {
      try {
        // 1. Unwrap Repost Wrapper if present
        final isRepost =
            trackData['type'] == 'track-repost' || trackData['track'] != null;
        final Map<String, dynamic> track = isRepost
            ? trackData['track'] as Map<String, dynamic>
            : trackData as Map<String, dynamic>;

        // Guard: SC duration is in ms — 0 means unprocessed, removed, or ghost.
        final rawDuration = track['duration'] as int? ?? 0;
        if (rawDuration < 1000) {
          _logger.warning(
            '[sc] Dropping ghost track "${track['title']}" (duration=${rawDuration}ms) id=${track['id']}',
          );
          auditSink?.add({
            'type': 'fetch_drop',
            'reason': 'zero_duration',
            'id': track['id']?.toString() ?? 'unknown',
            'title': track['title']?.toString() ?? '',
            'is_repost': isRepost,
            'duration_ms': rawDuration,
          });
          continue;
        }

        final String? repostCreatedAt = isRepost
            ? trackData['created_at'] as String?
            : null;
        final repostedAt = _parseSoundCloudDate(repostCreatedAt);
        final resolution = _resolveDate(track, repostedAt: repostedAt);
        final publishedAt = _v2DatesEnabled
            ? resolution.publishedAt
            : resolution.legacyPublishedAt;
        _logShadowDateDifference(track, resolution);

        // 2. Extract Producer Name (metadata_artist > user['username'])
        final producerName = _getProducerName(track, artistName);

        // 3. Mandatory Title Augmentation: "Producer - Title"
        var title = track['title'] as String? ?? '';
        if (title.trim().isEmpty) {
          _logger.warning(
            '[sc] Dropping track with blank title id=${track['id']}',
          );
          continue;
        }
        if (!title.toLowerCase().contains(producerName.toLowerCase())) {
          title = '$producerName - $title';
        }

        final trackId = track['id'].toString();
        if (isRepost) {
          repostMetaById?[trackId] = _ScRepostMeta(
            repostedByName: artistName,
            repostedAt: repostedAt,
            feedSourcePath: 'track-repost',
          );
        }
        final feedItem = FeedItem(
          id: trackId,
          platform: 'soundcloud',
          artistName: artistName,
          contentType: 'track',
          title: title,
          body: _cardBody(
            description: track['description'] as String?,
            repostedBy: isRepost ? artistName : null,
          ),
          artworkUrl:
              ((track['artwork_url'] as String?)?.replaceFirst(
                '-large.',
                '-t500x500.',
              )) ??
              avatarUrl,
          externalUrl: _validateTrackUrl(track['permalink_url']),
          publishedAt: publishedAt,
          sourceCreatedAt: resolution.sourceCreatedAt,
          displayAt: resolution.displayAt,
          releaseAt: resolution.releaseAt,
          sourceLastModifiedAt: resolution.sourceLastModifiedAt,
          dateSource: _v2DatesEnabled ? resolution.dateSource : 'legacy_max',
          dateConfidence: resolution.confidence,
          dateConflictReason: resolution.conflictReason,
          isUpcoming: _v2DatesEnabled && resolution.isUpcoming,
          durationSeconds: (track['duration'] as int) ~/ 1000,
          playCount: track['playback_count'] as int?,
          likeCount: track['likes_count'] as int?,
        );
        items.add(feedItem);

        auditSink?.add(
          _scAuditEntry(
            id: trackId,
            track: track,
            isRepost: isRepost,
            repostCreatedAt: repostCreatedAt,
            publishedAt: publishedAt,
            path: isRepost ? 'track-repost' : 'own-track',
          ),
        );
      } catch (e) {
        _logger.warning('Error parsing SoundCloud track: $e');
      }
    }
  }

  void _parseScPlaylists(
    List<dynamic> data,
    List<FeedItem> items,
    String artistName,
    String avatarUrl, {
    List<Map<String, dynamic>>? auditSink,
    Map<String, _ScRepostMeta>? repostMetaById,
  }) {
    final artistLower = artistName.toLowerCase();
    for (var plData in data) {
      try {
        // 1. Unwrap Repost Wrapper if present
        final isRepost =
            plData['type'] == 'playlist-repost' || plData['playlist'] != null;
        final Map<String, dynamic> pl = isRepost
            ? plData['playlist'] as Map<String, dynamic>
            : plData as Map<String, dynamic>;

        final uploader = pl['user']['username'].toString().toLowerCase();
        var title = pl['title'] as String? ?? '';

        // Guard: skip blank-title playlists.
        if (title.trim().isEmpty) {
          _logger.warning(
            '[sc] Dropping playlist with blank title id=${pl['id']}',
          );
          continue;
        }

        // Filter: if not uploader, artist name must be in title
        if (uploader != artistLower &&
            !title.toLowerCase().contains(artistLower)) {
          auditSink?.add({
            'type': 'fetch_drop',
            'reason': 'playlist_title_filter',
            'id': 'playlist-${pl['id']}',
            'title': title,
            'uploader': uploader,
            'is_repost': isRepost,
            'raw_created_at': pl['created_at']?.toString(),
          });
          continue;
        }

        // Guard: skip empty playlists — track_count=0 means nothing to play.
        final trackCount = pl['track_count'] as int? ?? 0;
        if (trackCount == 0) {
          _logger.warning(
            '[sc] Dropping empty playlist "$title" (track_count=0) id=${pl['id']}',
          );
          auditSink?.add({
            'type': 'fetch_drop',
            'reason': 'empty_playlist',
            'id': 'playlist-${pl['id']}',
            'title': title,
            'is_repost': isRepost,
            'track_count': trackCount,
          });
          continue;
        }

        final String? repostCreatedAt = isRepost
            ? plData['created_at'] as String?
            : null;
        final repostedAt = _parseSoundCloudDate(repostCreatedAt);
        final resolution = _resolveDate(pl, repostedAt: repostedAt);
        final publishedAt = _v2DatesEnabled
            ? resolution.publishedAt
            : resolution.legacyPublishedAt;
        _logShadowDateDifference(pl, resolution);

        // 2. Extract Producer Name
        final producerName = _getProducerName(pl, artistName);

        // 3. Mandatory Title Augmentation
        if (!title.toLowerCase().contains(producerName.toLowerCase())) {
          title = '$producerName - $title';
        }

        final plId = 'playlist-${pl['id']}';
        if (isRepost) {
          repostMetaById?[plId] = _ScRepostMeta(
            repostedByName: artistName,
            repostedAt: repostedAt,
            feedSourcePath: 'playlist-repost',
          );
        }
        items.add(
          FeedItem(
            id: plId,
            platform: 'soundcloud',
            artistName: artistName,
            contentType: 'release',
            title: title,
            body: _cardBody(
              description: pl['description'] as String?,
              repostedBy: isRepost ? artistName : null,
            ),
            artworkUrl:
                ((pl['artwork_url'] as String?)?.replaceFirst(
                  '-large.',
                  '-t500x500.',
                )) ??
                avatarUrl,
            externalUrl: _validateTrackUrl(pl['permalink_url']),
            publishedAt: publishedAt,
            sourceCreatedAt: resolution.sourceCreatedAt,
            displayAt: resolution.displayAt,
            releaseAt: resolution.releaseAt,
            sourceLastModifiedAt: resolution.sourceLastModifiedAt,
            dateSource: _v2DatesEnabled ? resolution.dateSource : 'legacy_max',
            dateConfidence: resolution.confidence,
            dateConflictReason: resolution.conflictReason,
            isUpcoming: _v2DatesEnabled && resolution.isUpcoming,
            trackCount: pl['track_count'] as int?,
            durationSeconds:
                pl['duration'] is int && (pl['duration'] as int) > 0
                ? (pl['duration'] as int) ~/ 1000
                : null,
          ),
        );

        auditSink?.add(
          _scAuditEntry(
            id: plId,
            track: pl,
            isRepost: isRepost,
            repostCreatedAt: repostCreatedAt,
            publishedAt: publishedAt,
            path: isRepost ? 'playlist-repost' : 'own-playlist',
          ),
        );
      } catch (e) {
        _logger.warning('Error parsing SoundCloud playlist: $e');
      }
    }
  }

  /// Validate that the provided URL is a legitimate SoundCloud profile URL.
  /// Returns true if the URL is HTTPS and points to soundcloud.com or
  /// www.soundcloud.com; false otherwise. Prevents SSRF attacks by rejecting
  /// arbitrary URLs before making upstream HTTP requests.
  /// Static so it can be tested independently.
  static bool isSoundCloudProfileUrl(String url) {
    // Reject URLs with control characters (newlines, tabs, null bytes, etc.)
    // which could indicate header injection or similar attacks
    if (url.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return false;
    }

    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https') return false;
      final host = uri.host.toLowerCase();
      return host == 'soundcloud.com' || host == 'www.soundcloud.com';
    } catch (_) {
      return false;
    }
  }

  /// Validate track permalink URL from SoundCloud API before storing.
  /// Ensures the URL is a valid SoundCloud track URL (HTTPS + soundcloud.com domain).
  /// Logs warnings if URL is malformed, then returns it anyway to avoid breaking
  /// the feed if the API returns unexpected data.
  String _validateTrackUrl(dynamic urlValue) {
    final url = urlValue as String? ?? '';
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' ||
          (uri.host.toLowerCase() != 'soundcloud.com' &&
              uri.host.toLowerCase() != 'www.soundcloud.com')) {
        _logger.warning(
          '[sc] Track URL from API does not match expected SoundCloud domain: $url',
        );
      }
    } catch (e) {
      _logger.warning('[sc] Failed to validate track URL: $url, error: $e');
    }
    return url;
  }

  String? _cardBody({
    required String? description,
    required String? repostedBy,
  }) {
    final cleanDescription = description?.trim();
    if (repostedBy == null || repostedBy.trim().isEmpty) {
      return cleanDescription?.isEmpty == true ? null : cleanDescription;
    }

    final attribution = '\u21bb by ${repostedBy.trim()}';
    if (cleanDescription == null || cleanDescription.isEmpty) {
      return attribution;
    }
    if (cleanDescription.startsWith(attribution)) return cleanDescription;
    return '$attribution\n$cleanDescription';
  }

  /// Builds an audit entry capturing every raw date field seen for an item.
  Map<String, dynamic> _scAuditEntry({
    required String id,
    required Map<String, dynamic> track,
    required bool isRepost,
    required String? repostCreatedAt,
    required DateTime publishedAt,
    required String path,
  }) {
    final ry = track['release_year'];
    final rm = track['release_month'];
    final rd = track['release_day'];
    String? releaseYmd;
    if (ry is int && rm is int && rd is int) {
      releaseYmd =
          '$ry-${rm.toString().padLeft(2, '0')}-${rd.toString().padLeft(2, '0')}';
    }

    // Reconstruct which candidate won the max-date selection.
    final candidates = <String, DateTime>{};
    if (releaseYmd != null) {
      final parsed = _parseSoundCloudDate(
        '${ry!}-${(rm as int).toString().padLeft(2, '0')}-${(rd as int).toString().padLeft(2, '0')}',
      );
      if (parsed != null) candidates['release_ymd'] = parsed;
    }
    for (final f in ['release_date', 'display_date', 'created_at']) {
      final val = track[f];
      if (val is String && val.isNotEmpty) {
        final parsed = _parseSoundCloudDate(val);
        if (parsed != null) candidates[f] = parsed;
      }
    }
    if (isRepost && repostCreatedAt != null) {
      final parsed = _parseSoundCloudDate(repostCreatedAt);
      if (parsed != null) candidates['repost_created_at'] = parsed;
    }

    String usedField = '-';
    if (isRepost && repostCreatedAt != null) {
      final rdt = _parseSoundCloudDate(repostCreatedAt);
      if (rdt != null && rdt == publishedAt) {
        usedField = 'repost_created_at';
      }
    }
    if (usedField == '-') {
      for (final entry in candidates.entries) {
        if (entry.key != 'repost_created_at' && entry.value == publishedAt) {
          usedField = entry.key;
          break;
        }
      }
    }
    if (usedField == '-' && candidates.isNotEmpty) {
      // Fallback: label whichever candidate matches publishedAt closest.
      usedField = candidates.entries
          .reduce(
            (a, b) =>
                (a.value.difference(publishedAt).abs() <
                    b.value.difference(publishedAt).abs())
                ? a
                : b,
          )
          .key;
    }

    return {
      'id': id,
      'path': path,
      'isRepost': isRepost,
      'raw_repost_created_at': repostCreatedAt,
      'raw_release_ymd': releaseYmd,
      'raw_release_date': track['release_date']?.toString(),
      'raw_display_date': track['display_date']?.toString(),
      'raw_created_at': track['created_at']?.toString(),
      'usedField': usedField,
      'resolvedDate': publishedAt.toUtc().toIso8601String(),
    };
  }

  /// Extracts the best possible producer name from a track/playlist map.
  String _getProducerName(Map<String, dynamic> item, String fallback) {
    // 1. Check metadata_artist (Highest Priority)
    final metaArtist = item['metadata_artist'];
    if (metaArtist is String && metaArtist.trim().isNotEmpty) {
      // Some uploaders put themselves in metadata_artist, we should check it
      if (metaArtist.toLowerCase() != 'dtdnb' &&
          metaArtist.toLowerCase() != 'dnb spread' &&
          metaArtist.toLowerCase() != 'skankandbass') {
        return metaArtist.trim();
      }
    }

    // 2. Check user['username']
    final user = item['user'];
    if (user is Map) {
      final username = user['username'];
      if (username is String && username.trim().isNotEmpty) {
        return username.trim();
      }
    }

    return fallback;
  }

  DateTime? _parseSoundCloudDate(Object? value) =>
      _dateResolver.parseDate(value);

  /// Parse SC profile genre + tag_list fields into a sorted, deduplicated list.
  /// SC tag_list format: "drum and bass" "liquid" dnb neurofunk
  /// (multi-word tags are double-quoted; single-word tags are unquoted)
  static List<String> _parseScGenreTags(String? genre, String? tagList) {
    final tags = <String>{};
    if (genre != null && genre.trim().isNotEmpty) {
      tags.add(genre.trim().toLowerCase());
    }
    if (tagList != null && tagList.trim().isNotEmpty) {
      final quotedRe = RegExp(r'"([^"]+)"');
      // Collect quoted multi-word tags first.
      for (final m in quotedRe.allMatches(tagList)) {
        final t = m.group(1)!.trim();
        if (t.isNotEmpty) tags.add(t.toLowerCase());
      }
      // Collect remaining unquoted single-word tokens.
      final remaining = tagList.replaceAll(quotedRe, '').trim();
      for (final t in remaining.split(RegExp(r'\s+'))) {
        if (t.isNotEmpty) tags.add(t.toLowerCase());
      }
    }
    return tags.toList()..sort();
  }
}
