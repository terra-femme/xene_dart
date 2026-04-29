import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:xml/xml.dart';
import 'package:xene_domain/xene_domain.dart';
import 'database.dart';

final _logger = Logger('YouTubeService');

class YouTubeService {
  YouTubeService(this._db);

  final DatabaseService _db;
  final _dio = Dio(BaseOptions(
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));

  /// Resolve channel ID from a URL, handle, or ID.
  /// ELI5: Finding the secret "UC..." ID for a YouTube channel.
  Future<String?> _resolveChannelId(String ytUrl) async {
    if (ytUrl.isEmpty) return null;

    // Already an ID
    if (ytUrl.startsWith('UC') && ytUrl.length > 20) {
      return ytUrl;
    }

    // Check database first
    final cached = await _db.getYouTubeChannelId(ytUrl);
    if (cached != null) return cached;

    // Resolve via scraping
    try {
      String url = ytUrl;
      if (!url.startsWith('http')) {
        if (url.startsWith('@')) {
          url = 'https://www.youtube.com/$url';
        } else {
          url = 'https://www.youtube.com/@$url';
        }
      }

      final resp = await _dio.get<String>(url);
      final html = resp.data ?? '';

      // Patterns from youtube.py
      final patterns = [
        RegExp(r'"externalChannelId"\s*:\s*"(UC[^"]+)"'),
        RegExp(r'"channelId"\s*:\s*"(UC[^"]+)"'),
        RegExp(r'itemprop="channelId" content="(UC[^"]+)"'),
        RegExp(r'link rel="canonical" href="https://www\.youtube\.com/channel/(UC[^"]+)"'),
        RegExp(r'youtube\.com/channel/(UC[a-zA-Z0-9_-]+)'),
      ];

      for (final p in patterns) {
        final match = p.firstMatch(html);
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

  /// Fetch videos via the native YouTube RSS feed.
  /// ELI5: Reading the "Digital News Clipping" for a channel.
  Future<List<FeedItem>> getVideos(String ytUrl, String artistName) async {
    final channelId = await _resolveChannelId(ytUrl);
    if (channelId == null) return [];

    final rssUrl = 'https://www.youtube.com/feeds/videos.xml?channel_id=$channelId';
    _logger.info('[youtube] Fetching RSS feed: $rssUrl');

    try {
      final resp = await _dio.get<String>(rssUrl);
      final document = XmlDocument.parse(resp.data!);
      final entries = document.findAllElements('entry');

      final items = <FeedItem>[];
      for (final entry in entries) {
        try {
          final id = entry.findElements('yt:videoId').first.innerText;
          final title = entry.findElements('title').first.innerText;
          final link = entry.findElements('link').first.getAttribute('href')!;
          final published = entry.findElements('published').first.innerText;
          final summary = entry.findElements('media:description').first.innerText;
          final thumbnail = entry.findAllElements('media:thumbnail').first.getAttribute('url');

          items.add(FeedItem(
            id: id,
            platform: 'youtube',
            artistName: artistName,
            contentType: 'video',
            title: title,
            body: summary,
            externalUrl: link,
            artworkUrl: thumbnail,
            publishedAt: DateTime.parse(published),
          ));
        } catch (e) {
          _logger.warning('[youtube] Skipping entry for $artistName: $e');
        }
      }

      // Save to DB
      if (items.isNotEmpty) {
        final dbItems = items.map((i) => {
          'platform': 'youtube',
          'internal_id': i.id,
          'artist_name': i.artistName,
          'content_type': i.contentType,
          'title': i.title,
          'body': i.body,
          'artwork_url': i.artwork_url,
          'external_url': i.external_url,
          'published_at': i.publishedAt.toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).toList();

        await _db.saveFeedItems(dbItems);
      }

      return items;
    } catch (e) {
      _logger.severe('[youtube] RSS fetch failed for $artistName: $e');
      return [];
    }
  }
}
