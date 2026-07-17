import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:xml/xml.dart';
import 'package:xene_domain/xene_domain.dart';
import '../database.dart';
import '../utils/http_client.dart';
import 'api_analytics_service.dart';

final _logger = Logger('YouTubeService');

class YouTubeService {
  YouTubeService(this._db, {ApiAnalyticsService? analytics})
    : _dio = analytics?.trackDio(_createDio(), 'youtube') ?? _createDio();

  final DatabaseService _db;
  final Dio _dio;
  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    ),
  )..httpClientAdapter = pooledKeepAliveAdapter();
  static const _youtubeApiBase = 'https://www.googleapis.com/youtube/v3';
  static const _uploadsPlaylistCacheTtl = Duration(days: 30);

  String? get _apiKey {
    final key = Platform.environment['YOUTUBE_API_KEY'];
    if (key == null || key.isEmpty || key == 'your_api_key_here') return null;
    return key;
  }

  /// Resolve channel ID from a URL, handle, or ID.
  /// Ported from youtube.py :: _resolve_channel_id
  Future<String?> _resolveChannelId(String ytUrl) async {
    if (ytUrl.isEmpty) return null;

    // Already an ID
    if (ytUrl.length > 20 && ytUrl.startsWith('UC')) return ytUrl;

    // Check database first
    final cached = await _db.getYouTubeChannelId(ytUrl);
    if (cached != null) return cached;

    final apiResolved = await _resolveChannelIdViaApi(ytUrl);
    if (apiResolved != null) {
      await _db.saveYouTubeChannelId(ytUrl, apiResolved);
      return apiResolved;
    }

    // Try to resolve via page scrape
    var url = ytUrl;
    if (!url.startsWith('http')) {
      if (url.startsWith('@')) {
        url = 'https://www.youtube.com/$url';
      } else {
        url = 'https://www.youtube.com/@$url';
      }
    }

    try {
      final response = await _dio.get<String>(url);
      final body = response.data ?? '';

      final patterns = [
        RegExp(r'"externalChannelId"\s*:\s*"(UC[^"]+)"'),
        RegExp(r'"channelId"\s*:\s*"(UC[^"]+)"'),
        RegExp(r'itemprop="channelId" content="(UC[^"]+)"'),
        RegExp(
          r'link rel="canonical" href="https://www\.youtube\.com/channel/(UC[^"]+)"',
        ),
        RegExp(r'youtube\.com/channel/(UC[a-zA-Z0-9_-]+)'),
      ];

      for (final p in patterns) {
        final match = p.firstMatch(body);
        if (match != null) {
          final channelId = match.group(1)!;
          _logger.info('[youtube] Resolved $ytUrl -> $channelId');
          await _db.saveYouTubeChannelId(ytUrl, channelId);
          return channelId;
        }
      }
    } catch (e) {
      _logger.warning('[youtube] Failed to resolve channel ID for $ytUrl: $e');
    }

    return null;
  }

  String? _extractChannelId(String value) {
    if (value.startsWith('UC') && value.length > 20) return value;
    final match = RegExp(
      r'youtube\.com/channel/(UC[a-zA-Z0-9_-]+)',
    ).firstMatch(value);
    return match?.group(1);
  }

  String? _extractHandle(String value) {
    final handleMatch = RegExp(
      r'(?:youtube\.com/)?@([a-zA-Z0-9._-]+)',
    ).firstMatch(value);
    if (handleMatch != null) return handleMatch.group(1);

    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('http') ||
        trimmed.startsWith('UC')) {
      return null;
    }
    return trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
  }

  Future<String?> _resolveChannelIdViaApi(String ytUrl) async {
    final key = _apiKey;
    if (key == null) return null;

    final channelId = _extractChannelId(ytUrl);
    if (channelId != null) return channelId;

    final handle = _extractHandle(ytUrl);
    if (handle == null) return null;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_youtubeApiBase/channels',
        queryParameters: {'part': 'id', 'forHandle': handle, 'key': key},
      );
      final items = response.data?['items'] as List? ?? [];
      if (items.isNotEmpty) {
        final first = items.first;
        if (first is Map && first['id'] is String) {
          final id = first['id'] as String;
          _logger.info('[youtube] API resolved @$handle -> $id');
          return id;
        }
      }
    } catch (e) {
      _logger.warning('[youtube] API handle resolve failed for $ytUrl: $e');
    }

    return null;
  }

  /// Fetch videos via YouTube Data API first, falling back to native RSS.
  /// If [auditSink] is supplied, raw date fields are appended per item
  /// (keyed by video id) for the audit report.
  Future<List<FeedItem>> getVideos(
    String ytUrl,
    String artistName, {
    List<Map<String, dynamic>>? auditSink,
  }) async {
    final channelId = await _resolveChannelId(ytUrl);
    if (channelId == null) return [];

    final apiItems = await _getVideosViaApi(
      channelId,
      artistName,
      auditSink: auditSink,
    );
    if (apiItems.isNotEmpty) return apiItems;

    return _getVideosViaRss(channelId, artistName, auditSink: auditSink);
  }

  Future<List<FeedItem>> _getVideosViaApi(
    String channelId,
    String artistName, {
    List<Map<String, dynamic>>? auditSink,
  }) async {
    final key = _apiKey;
    if (key == null) {
      _logger.info('[youtube] YOUTUBE_API_KEY not set - using RSS fallback');
      return [];
    }

    try {
      final uploadsPlaylist = await _getUploadsPlaylistId(channelId, key);
      if (uploadsPlaylist == null || uploadsPlaylist.isEmpty) return [];

      // Paginate newest-first until every item in a page pre-dates the 31d window.
      // Early-exit means a slow channel costs 1 API call; a daily-upload channel
      // like COLORS costs 2-3. Safety cap: 5 pages × 50 = 250 items max.
      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 31));
      final items = <FeedItem>[];
      String? pageToken;
      var pagesFetched = 0;
      const maxPages = 5;

      do {
        final videosResp = await _dio.get<Map<String, dynamic>>(
          '$_youtubeApiBase/playlistItems',
          queryParameters: {
            'part': 'snippet,contentDetails',
            'playlistId': uploadsPlaylist,
            'maxResults': 50,
            'key': key,
            if (pageToken != null) 'pageToken': pageToken,
          },
        );

        final entries = videosResp.data?['items'] as List? ?? [];
        pageToken = videosResp.data?['nextPageToken'] as String?;
        pagesFetched++;
        final scheduleByVideoId = await _getScheduledStarts(
          entries
              .whereType<Map>()
              .map((entry) {
                final snippet = entry['snippet'] as Map?;
                final contentDetails = entry['contentDetails'] as Map?;
                final resourceId = snippet?['resourceId'] as Map?;
                return contentDetails?['videoId']?.toString() ??
                    resourceId?['videoId']?.toString();
              })
              .whereType<String>()
              .toList(),
          key,
        );

        var hitCutoff = false;
        for (final raw in entries) {
          if (raw is! Map) continue;
          final snippet = raw['snippet'] as Map?;
          final contentDetails = raw['contentDetails'] as Map?;
          final resourceId = snippet?['resourceId'] as Map?;
          final videoId =
              contentDetails?['videoId']?.toString() ??
              resourceId?['videoId']?.toString();
          final title = snippet?['title']?.toString();
          final published =
              contentDetails?['videoPublishedAt']?.toString() ??
              snippet?['publishedAt']?.toString();
          if (videoId == null || title == null || published == null) continue;

          final parsedDate = DateTime.parse(published);
          final scheduledStart = scheduleByVideoId[videoId];
          final isUpcoming =
              scheduledStart != null &&
              scheduledStart.toUtc().isAfter(DateTime.now().toUtc());
          // Items come back newest-first; once one is too old, all remaining are too.
          if (!isUpcoming && parsedDate.toUtc().isBefore(cutoff)) {
            hitCutoff = true;
            break;
          }

          final thumbnails = snippet?['thumbnails'] as Map?;
          String? artworkUrl;
          for (final k in ['maxres', 'standard', 'high', 'medium', 'default']) {
            final thumb = thumbnails?[k] as Map?;
            artworkUrl = thumb?['url']?.toString();
            if (artworkUrl != null && artworkUrl.isNotEmpty) break;
          }

          items.add(
            FeedItem(
              id: videoId,
              platform: 'youtube',
              artistName: artistName,
              contentType: 'video',
              title: title,
              body: snippet?['description']?.toString(),
              externalUrl: 'https://www.youtube.com/watch?v=$videoId',
              artworkUrl: artworkUrl,
              publishedAt: parsedDate,
              releaseAt: scheduledStart,
              dateSource: scheduledStart != null
                  ? 'youtube.liveStreamingDetails.scheduledStartTime'
                  : null,
              dateConfidence: scheduledStart != null ? 'scheduled' : null,
              isUpcoming: isUpcoming,
            ),
          );
          auditSink?.add({
            'id': videoId,
            'path': 'api',
            'raw_videoPublishedAt': contentDetails?['videoPublishedAt']
                ?.toString(),
            'raw_snippetPublishedAt': snippet?['publishedAt']?.toString(),
            'usedField': contentDetails?['videoPublishedAt'] != null
                ? 'videoPublishedAt'
                : 'snippet.publishedAt',
            'resolvedDate': parsedDate.toUtc().toIso8601String(),
            'scheduledStartTime': scheduledStart?.toUtc().toIso8601String(),
            'isUpcoming': isUpcoming,
          });
        }

        if (hitCutoff) break;
      } while (pageToken != null && pagesFetched < maxPages);

      auditSink?.add({
        'type': 'fetch_meta',
        'path': 'api',
        'channel_id': channelId,
        'uploads_playlist_id': uploadsPlaylist,
        'items_received': items.length,
        'pages_fetched': pagesFetched,
      });

      if (items.isNotEmpty) {
        _logger.info(
          '[youtube] API built ${items.length} items for $artistName '
          '(pages=$pagesFetched)',
        );
        await _saveItems(items);
      }

      return items;
    } catch (e) {
      _logger.warning(
        '[youtube] API fetch failed for $artistName - using RSS fallback: $e',
      );
      auditSink?.add({
        'type': 'fetch_meta',
        'path': 'api',
        'channel_id': channelId,
        'items_received': 0,
        'error': e.toString(),
      });
      return [];
    }
  }

  Future<String?> _getUploadsPlaylistId(String channelId, String key) async {
    final cacheKey = 'youtube_uploads_playlist:$channelId';
    final cached = await _db.getSystemCache(cacheKey);
    final cachedId = cached?['uploads_playlist_id'] as String?;
    if (cachedId != null && cachedId.isNotEmpty) {
      _logger.info('[youtube] Uploads playlist cache HIT for $channelId');
      return cachedId;
    }

    final channelResp = await _dio.get<Map<String, dynamic>>(
      '$_youtubeApiBase/channels',
      queryParameters: {'part': 'contentDetails', 'id': channelId, 'key': key},
    );
    final channelItems = channelResp.data?['items'] as List? ?? [];
    if (channelItems.isEmpty) return null;

    final firstChannel = channelItems.first;
    final contentDetails = firstChannel is Map
        ? firstChannel['contentDetails'] as Map?
        : null;
    final relatedPlaylists = contentDetails?['relatedPlaylists'] as Map?;
    final uploadsPlaylist = relatedPlaylists?['uploads']?.toString();
    if (uploadsPlaylist == null || uploadsPlaylist.isEmpty) return null;

    await _db.setSystemCache(cacheKey, {
      'uploads_playlist_id': uploadsPlaylist,
      'channel_id': channelId,
    }, expiresAt: DateTime.now().toUtc().add(_uploadsPlaylistCacheTtl));
    _logger.info('[youtube] Cached uploads playlist for $channelId');
    return uploadsPlaylist;
  }

  Future<Map<String, DateTime>> _getScheduledStarts(
    List<String> videoIds,
    String key,
  ) async {
    if (videoIds.isEmpty) return const {};
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_youtubeApiBase/videos',
        queryParameters: {
          'part': 'liveStreamingDetails',
          'id': videoIds.join(','),
          'key': key,
        },
      );
      final scheduled = <String, DateTime>{};
      final items = response.data?['items'] as List? ?? [];
      for (final item in items) {
        if (item is! Map) continue;
        final id = item['id']?.toString();
        final details = item['liveStreamingDetails'] as Map?;
        final scheduledStart = details?['scheduledStartTime']?.toString();
        if (id == null || scheduledStart == null) continue;
        scheduled[id] = DateTime.parse(scheduledStart);
      }
      return scheduled;
    } catch (e) {
      _logger.warning('[youtube] scheduled start lookup failed: $e');
      return const {};
    }
  }

  /// Fetch videos via the native YouTube RSS feed.
  /// Ported from youtube.py :: get_videos
  Future<List<FeedItem>> _getVideosViaRss(
    String channelId,
    String artistName, {
    List<Map<String, dynamic>>? auditSink,
  }) async {
    final rssUrl =
        'https://www.youtube.com/feeds/videos.xml?channel_id=$channelId';
    _logger.info('[youtube] Fetching RSS feed for $artistName: $rssUrl');

    try {
      final response = await _dio.get<String>(rssUrl);
      final document = XmlDocument.parse(response.data!);
      final entries = document.findAllElements('entry');

      final items = <FeedItem>[];
      for (final entry in entries) {
        try {
          final id = entry.findElements('yt:videoId').first.innerText;
          final title = entry.findElements('title').first.innerText;
          final link = entry.findElements('link').first.getAttribute('href')!;
          final published = entry.findElements('published').first.innerText;

          String? body;
          try {
            body = entry.findAllElements('media:description').first.innerText;
          } catch (_) {}

          String? artworkUrl;
          try {
            artworkUrl = entry
                .findAllElements('media:thumbnail')
                .first
                .getAttribute('url');
          } catch (_) {}

          final parsedDate = DateTime.parse(published);
          // Premieres are only announced on recently-published entries. Gate
          // the watch-page scrape so a refresh doesn't download the full HTML
          // for every historical RSS entry (15/artist) on each cache miss.
          final entryAge = DateTime.now().toUtc().difference(
            parsedDate.toUtc(),
          );
          final premiere = entryAge <= const Duration(days: 30)
              ? await _getPremiereDetailsFromWatchPage(id, link)
              : null;
          if (entryAge > const Duration(days: 30)) {
            _logger.fine(
              '[youtube] Skipping premiere lookup for $id: '
              'entry is ${entryAge.inDays}d old',
            );
          }
          final releaseAt = premiere?.scheduledStart;
          final isUpcoming =
              releaseAt != null &&
              releaseAt.toUtc().isAfter(DateTime.now().toUtc());
          final bodyWithPremiere =
              premiere?.text != null && body?.contains(premiere!.text!) != true
              ? [
                  if (body != null && body.trim().isNotEmpty) body.trim(),
                  premiere!.text!,
                ].join('\n\n')
              : body;

          items.add(
            FeedItem(
              id: id,
              platform: 'youtube',
              artistName: artistName,
              contentType: 'video',
              title: title,
              body: bodyWithPremiere,
              externalUrl: link,
              artworkUrl: artworkUrl,
              publishedAt: parsedDate,
              releaseAt: releaseAt,
              dateSource: premiere?.dateSource,
              dateConfidence: releaseAt != null ? 'scheduled' : null,
              isUpcoming: isUpcoming,
            ),
          );
          auditSink?.add({
            'id': id,
            'path': 'rss',
            'raw_videoPublishedAt': null,
            'raw_snippetPublishedAt': null,
            'raw_rssPublished': published,
            'usedField': 'rss.published',
            'resolvedDate': parsedDate.toUtc().toIso8601String(),
            'scheduledStartTime': releaseAt?.toUtc().toIso8601String(),
            'premiereText': premiere?.text,
            'isUpcoming': isUpcoming,
          });
        } catch (e) {
          _logger.warning('[youtube] Skipping entry for $artistName: $e');
        }
      }

      auditSink?.add({
        'type': 'fetch_meta',
        'path': 'rss',
        'channel_id': channelId,
        'rss_url': rssUrl,
        'items_received': items.length,
      });

      if (items.isNotEmpty) {
        _logger.info('[youtube] Built ${items.length} items for $artistName');
        await _saveItems(items);
      }

      return items;
    } catch (e) {
      _logger.severe('[youtube] RSS fetch failed for $artistName: $e');
      auditSink?.add({
        'type': 'fetch_meta',
        'path': 'rss',
        'channel_id': channelId,
        'rss_url': rssUrl,
        'items_received': 0,
        'error': e.toString(),
      });
      return [];
    }
  }

  Future<_YouTubePremiereDetails?> _getPremiereDetailsFromWatchPage(
    String videoId,
    String link,
  ) async {
    try {
      final uri = Uri.parse(link);
      final watchUri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'v': uri.queryParameters['v'] ?? videoId,
          'hl': 'en',
          'gl': 'US',
        },
      );
      final response = await _dio.get<String>(watchUri.toString());
      final html = response.data ?? '';
      final scheduledStart =
          _scheduledStartFromWatchHtml(html) ?? _premiereDateFromText(html);
      final text = _premiereTextFromWatchHtml(html);
      if (scheduledStart == null && text == null) return null;
      return _YouTubePremiereDetails(
        scheduledStart: scheduledStart,
        text: text,
        dateSource: scheduledStart != null
            ? 'youtube.watch.scheduledStartTime'
            : 'youtube.watch.premiereText',
      );
    } catch (e) {
      _logger.warning(
        '[youtube] watch premiere lookup failed for $videoId: $e',
      );
      return null;
    }
  }

  DateTime? _scheduledStartFromWatchHtml(String html) {
    final patterns = [
      RegExp(r'"startTimestamp"\s*:\s*"([^"]+)"'),
      RegExp(r'"scheduledStartTime"\s*:\s*"([^"]+)"'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match == null) continue;
      final raw = match.group(1);
      if (raw == null || raw.isEmpty) continue;
      final epochSeconds = int.tryParse(raw);
      if (epochSeconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          epochSeconds * 1000,
          isUtc: true,
        );
      }
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toUtc();
    }
    return null;
  }

  String? _premiereTextFromWatchHtml(String html) {
    final textMatch = RegExp(
      r'Premieres?\s+\d{1,2}[\/.-]\d{1,2}[\/.-]\d{2,4}(?:,?\s+\d{1,2}(?::\d{2})?\s*(?:AM|PM|a\.m\.|p\.m\.))?',
      caseSensitive: false,
    ).firstMatch(html);
    return textMatch?.group(0)?.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  DateTime? _premiereDateFromText(String text) {
    final match = RegExp(
      r'premieres?\s+(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{2,4})(?:,?\s+(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?))?',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;

    final month = int.tryParse(match.group(1)!);
    final day = int.tryParse(match.group(2)!);
    var year = int.tryParse(match.group(3)!);
    if (month == null || day == null || year == null) return null;
    if (year < 100) year += 2000;

    var hour = int.tryParse(match.group(4) ?? '0') ?? 0;
    final minute = int.tryParse(match.group(5) ?? '0') ?? 0;
    final period = match.group(6)?.toLowerCase().replaceAll('.', '');
    if (period == 'pm' && hour < 12) hour += 12;
    if (period == 'am' && hour == 12) hour = 0;

    final parsed = DateTime(year, month, day, hour, minute);
    return parsed.isAfter(DateTime.now()) ? parsed.toUtc() : null;
  }

  Future<void> _saveItems(List<FeedItem> items) async {
    final dbItems = items
        .map(
          (i) => {
            'platform': 'youtube',
            'internal_id': i.id,
            'artist_name': i.artistName,
            'content_type': i.contentType,
            'title': i.title,
            'body': i.body,
            'artwork_url': i.artworkUrl,
            'external_url': i.externalUrl,
            'published_at': i.publishedAt.toIso8601String(),
            'source_release_at': i.releaseAt?.toIso8601String(),
            'date_source': i.dateSource,
            'date_confidence': i.dateConfidence,
            'is_upcoming': i.isUpcoming,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
        )
        .toList();

    await _db.saveFeedItems(dbItems);
  }
}

class _YouTubePremiereDetails {
  const _YouTubePremiereDetails({
    required this.scheduledStart,
    required this.text,
    required this.dateSource,
  });

  final DateTime? scheduledStart;
  final String? text;
  final String? dateSource;
}
