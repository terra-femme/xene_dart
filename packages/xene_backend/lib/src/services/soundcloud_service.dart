import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';
import '../database.dart';

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

class SoundCloudService {
  SoundCloudService(this._db);

  final DatabaseService _db;

  // In-memory caches — mirrors soundcloud.py _cache (1h) and _user_id_cache (7d).
  final _trackCache = <String, _ScTrackCacheEntry>{};
  final _userCache = <String, _ScUserCacheEntry>{};
  static const _trackCacheTtl = Duration(hours: 1);
  static const _userCacheTtl = Duration(days: 7);

  final _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.soundcloud.com',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ),
  );

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

  /// Resolve a username to a User ID.
  Future<Map<String, dynamic>?> _resolveUserInfo(String username) async {
    final token = await _getToken();
    if (token == null) return null;

    // Normalize username
    var cleanUsername = username;
    if (username.contains('soundcloud.com/')) {
      try {
        final uri = Uri.parse(username);
        cleanUsername = uri.path.split('/').where((p) => p.isNotEmpty).first;
      } catch (_) {}
    } else if (username.contains('/')) {
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
  Future<Map<String, dynamic>?> resolveProfileUrl(String scUrl) async {
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
        DateTime.now().toUtc().difference(trackCached.fetchedAt) <
            _trackCacheTtl) {
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
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 31));

    // 1. Fetch own tracks
    final tracks = await _getCollection(
      '/users/$userId/tracks',
      token,
      cutoffDate: cutoff,
      auditSink: auditSink,
    );
    _parseScTracks(tracks, items, artistDisplayName, avatarUrl, auditSink: auditSink);

    // 2. Fetch own playlists (EPs/Albums) - CRUCIAL for Nixxy Rain
    final ownPlaylists = await _getCollection(
      '/users/$userId/playlists',
      token,
      cutoffDate: cutoff,
      auditSink: auditSink,
    );
    _parseScPlaylists(ownPlaylists, items, artistDisplayName, avatarUrl, auditSink: auditSink);

    // 3. Fetch track reposts
    final trackReposts = await _getCollection(
      '/users/$userId/reposts/tracks',
      token,
      cutoffDate: cutoff,
      auditSink: auditSink,
    );
    _parseScTracks(trackReposts, items, artistDisplayName, avatarUrl, auditSink: auditSink);

    // 4. Fetch playlist reposts
    final playlistReposts = await _getCollection(
      '/users/$userId/reposts/playlists',
      token,
      cutoffDate: cutoff,
      auditSink: auditSink,
    );
    _parseScPlaylists(playlistReposts, items, artistDisplayName, avatarUrl, auditSink: auditSink);

    // Sort, trim to window, save.
    // Pre-orders (future publishedAt) are kept; only past-31d items are dropped.
    items.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final windowItems = items.where((i) => i.publishedAt.isAfter(cutoff)).toList();

    final dbItems = windowItems
        .map(
          (i) => {
            'platform': i.platform,
            'internal_id': i.id,
            'artist_name': artistDisplayName,
            'content_type': i.contentType,
            'title': i.title,
            'body': i.body,
            'artwork_url': i.artworkUrl,
            'external_url': i.externalUrl,
            'published_at': i.publishedAt.toIso8601String(),
            'duration_seconds': i.durationSeconds,
            'play_count': i.playCount,
            'like_count': i.likeCount,
            'track_count': i.trackCount,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
        )
        .toList();

    await _db.saveFeedItems(dbItems);

    // Write to in-memory track cache.
    _trackCache[username] = _ScTrackCacheEntry(windowItems, DateTime.now().toUtc());
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
              final raw = (item['display_date'] ??
                      item['release_date'] ??
                      item['created_at'] ??
                      item['last_modified']) as String?;
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

  /// Resolve a track's stream URL using the official token.
  Future<String?> getStreamUrl(String trackId) async {
    final token = await _getToken();
    if (token == null) return null;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/tracks/$trackId/streams',
        options: Options(
          headers: {'Authorization': 'OAuth $token'},
          followRedirects: false, // We want the redirect URL
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      // The streams endpoint returns a list of formats.
      // Usually 'http_mp3_128_url' or similar.
      final data = response.data!;
      return data['http_mp3_128_url'] as String?;
    } catch (e) {
      _logger.warning('Failed to resolve SoundCloud stream for $trackId: $e');
      return null;
    }
  }

  void _parseScTracks(
    List<dynamic> data,
    List<FeedItem> items,
    String artistName,
    String avatarUrl, {
    List<Map<String, dynamic>>? auditSink,
  }) {
    for (var trackData in data) {
      try {
        // 1. Unwrap Repost Wrapper if present
        final isRepost =
            trackData['type'] == 'track-repost' || trackData['track'] != null;
        final Map<String, dynamic> track = isRepost
            ? trackData['track'] as Map<String, dynamic>
            : trackData as Map<String, dynamic>;

        final String? repostCreatedAt =
            isRepost ? trackData['created_at'] as String? : null;
        final publishedAt = isRepost
            ? _parseSoundCloudDate(repostCreatedAt) ??
                  _parsePublicTrackDate(track)
            : _parsePublicTrackDate(track);

        // 2. Extract Producer Name (metadata_artist > user['username'])
        final producerName = _getProducerName(track, artistName);

        // 3. Mandatory Title Augmentation: "Producer - Title"
        var title = track['title'] as String;
        if (!title.toLowerCase().contains(producerName.toLowerCase())) {
          title = '$producerName - $title';
        }

        final trackId = track['id'].toString();
        final feedItem = FeedItem(
          id: trackId,
          platform: 'soundcloud',
          artistName: artistName,
          contentType: 'track',
          title: title,
          body: track['description'] as String?,
          artworkUrl:
              ((track['artwork_url'] as String?)?.replaceFirst(
                '-large.',
                '-t500x500.',
              )) ??
              avatarUrl,
          externalUrl: track['permalink_url'] as String,
          publishedAt: publishedAt,
          durationSeconds: (track['duration'] as int) ~/ 1000,
          playCount: track['playback_count'] as int?,
          likeCount: track['likes_count'] as int?,
        );
        items.add(feedItem);

        auditSink?.add(_scAuditEntry(
          id: trackId,
          track: track,
          isRepost: isRepost,
          repostCreatedAt: repostCreatedAt,
          publishedAt: publishedAt,
          path: isRepost ? 'track-repost' : 'own-track',
        ));
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
        var title = pl['title'] as String;

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

        final String? repostCreatedAt =
            isRepost ? plData['created_at'] as String? : null;
        final publishedAt = isRepost
            ? _parseSoundCloudDate(repostCreatedAt) ??
                  _parsePublicTrackDate(pl)
            : _parsePublicTrackDate(pl);

        // 2. Extract Producer Name
        final producerName = _getProducerName(pl, artistName);

        // 3. Mandatory Title Augmentation
        if (!title.toLowerCase().contains(producerName.toLowerCase())) {
          title = '$producerName - $title';
        }

        final plId = 'playlist-${pl['id']}';
        items.add(
          FeedItem(
            id: plId,
            platform: 'soundcloud',
            artistName: artistName,
            contentType: 'release',
            title: title,
            body: pl['description'] as String?,
            artworkUrl:
                ((pl['artwork_url'] as String?)?.replaceFirst(
                  '-large.',
                  '-t500x500.',
                )) ??
                avatarUrl,
            externalUrl: pl['permalink_url'] as String,
            publishedAt: publishedAt,
            trackCount: pl['track_count'] as int?,
          ),
        );

        auditSink?.add(_scAuditEntry(
          id: plId,
          track: pl,
          isRepost: isRepost,
          repostCreatedAt: repostCreatedAt,
          publishedAt: publishedAt,
          path: isRepost ? 'playlist-repost' : 'own-playlist',
        ));
      } catch (e) {
        _logger.warning('Error parsing SoundCloud playlist: $e');
      }
    }
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
      releaseYmd = '$ry-${rm.toString().padLeft(2, '0')}-${rd.toString().padLeft(2, '0')}';
    }

    // Reconstruct which candidate won the max-date selection.
    final candidates = <String, DateTime>{};
    if (releaseYmd != null) {
      final parsed = _parseSoundCloudDate('${ry!}-${(rm as int).toString().padLeft(2, '0')}-${(rd as int).toString().padLeft(2, '0')}');
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
            (a, b) => (a.value.difference(publishedAt).abs() <
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

  /// Match the public SoundCloud Tracks tab date. Uploaded tracks can show
  /// release metadata ("7 days ago") even when the API resource was created
  /// earlier, so release/display dates win over created_at for own items.
  DateTime _parsePublicTrackDate(Map<String, dynamic> item) {
    final candidates = <DateTime>[];

    final ry = item['release_year'];
    final rm = item['release_month'];
    final rd = item['release_day'];
    if (ry is int && rm is int && rd is int) {
      try {
        candidates.add(_dateOnlyUtc(ry, rm, rd));
      } catch (_) {}
    }

    final fields = ['release_date', 'display_date', 'created_at'];
    for (final f in fields) {
      final val = item[f];
      if (val is String && val.isNotEmpty) {
        final parsed = _parseSoundCloudDate(val);
        if (parsed != null) candidates.add(parsed);
      }
    }

    if (candidates.isEmpty) return DateTime.now().toUtc();

    return candidates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  DateTime? _parseSoundCloudDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final trimmed = value.trim();
    final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(trimmed);
    if (dateOnly != null) {
      return _dateOnlyUtc(
        int.parse(dateOnly.group(1)!),
        int.parse(dateOnly.group(2)!),
        int.parse(dateOnly.group(3)!),
      );
    }

    try {
      return DateTime.parse(trimmed.replaceAll('/', '-')).toUtc();
    } catch (_) {
      final match = RegExp(
        r'^(\d{4})/(\d{2})/(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s+([+-])(\d{2})(\d{2})$',
      ).firstMatch(trimmed);
      if (match == null) return null;

      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final hour = int.parse(match.group(4)!);
      final minute = int.parse(match.group(5)!);
      final second = int.parse(match.group(6)!);
      final sign = match.group(7) == '-' ? -1 : 1;
      final offsetHours = int.parse(match.group(8)!);
      final offsetMinutes = int.parse(match.group(9)!);
      final offset = Duration(
        hours: sign * offsetHours,
        minutes: sign * offsetMinutes,
      );

      return DateTime.utc(
        year,
        month,
        day,
        hour,
        minute,
        second,
      ).subtract(offset);
    }
  }

  DateTime _dateOnlyUtc(int year, int month, int day) {
    // SoundCloud public dates are calendar dates, not instants. Store them at
    // midday UTC so US time zones do not shift them into the previous day when
    // recent/archive buckets compare local calendar days.
    return DateTime.utc(year, month, day, 12);
  }
}
