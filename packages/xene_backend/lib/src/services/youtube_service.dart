import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:xml/xml.dart';
import 'package:xene_domain/xene_domain.dart';
import '../database.dart';

final _logger = Logger('YouTubeService');

class YouTubeService {
  YouTubeService(this._db);

  final DatabaseService _db;
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    ),
  );
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

      final videosResp = await _dio.get<Map<String, dynamic>>(
        '$_youtubeApiBase/playlistItems',
        queryParameters: {
          'part': 'snippet,contentDetails',
          'playlistId': uploadsPlaylist,
          'maxResults': 25,
          'key': key,
        },
      );

      final entries = videosResp.data?['items'] as List? ?? [];
      final items = <FeedItem>[];
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

        final thumbnails = snippet?['thumbnails'] as Map?;
        String? artworkUrl;
        for (final key in ['maxres', 'standard', 'high', 'medium', 'default']) {
          final thumb = thumbnails?[key] as Map?;
          artworkUrl = thumb?['url']?.toString();
          if (artworkUrl != null && artworkUrl.isNotEmpty) break;
        }

        final parsedDate = DateTime.parse(published);
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
          ),
        );
        auditSink?.add({
          'id': videoId,
          'path': 'api',
          'raw_videoPublishedAt': contentDetails?['videoPublishedAt']?.toString(),
          'raw_snippetPublishedAt': snippet?['publishedAt']?.toString(),
          'usedField': contentDetails?['videoPublishedAt'] != null
              ? 'videoPublishedAt'
              : 'snippet.publishedAt',
          'resolvedDate': parsedDate.toUtc().toIso8601String(),
        });
      }

      auditSink?.add({
        'type': 'fetch_meta',
        'path': 'api',
        'channel_id': channelId,
        'uploads_playlist_id': uploadsPlaylist,
        'items_received': items.length,
      });

      if (items.isNotEmpty) {
        _logger.info(
          '[youtube] API built ${items.length} items for $artistName',
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
          items.add(
            FeedItem(
              id: id,
              platform: 'youtube',
              artistName: artistName,
              contentType: 'video',
              title: title,
              body: body,
              externalUrl: link,
              artworkUrl: artworkUrl,
              publishedAt: parsedDate,
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
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
        )
        .toList();

    await _db.saveFeedItems(dbItems);
  }
}
