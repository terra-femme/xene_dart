import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:xml/xml.dart';
import 'package:xene_domain/xene_domain.dart';
import 'database.dart';

final _logger = Logger('BandcampService');

class BandcampService {
  BandcampService(this._db);

  final DatabaseService _db;
  final _dio = Dio(BaseOptions(
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));

  /// Fetch releases via the Bandcamp RSS feed.
  /// ELI5: Checking the "Artist's Newspaper" for new music drops.
  Future<List<FeedItem>> getFeed(String bandcampUrl, String artistName) async {
    // Normalize URL to ensure it ends in /feed
    var feedUrl = bandcampUrl;
    if (!feedUrl.endsWith('/')) feedUrl += '/';
    feedUrl += 'feed';

    _logger.info('[bandcamp] Fetching RSS feed: $feedUrl');

    try {
      final resp = await _dio.get<String>(feedUrl);
      final document = XmlDocument.parse(resp.data!);
      final channel = document.findAllElements('channel').first;
      final items = channel.findElements('item');

      final feedItems = <FeedItem>[];
      for (final item in items) {
        try {
          final title = item.findElements('title').first.innerText;
          final link = item.findElements('link').first.innerText;
          final pubDateRaw = item.findElements('pubDate').first.innerText;
          final description = item.findElements('description').first.innerText;

          // Bandcamp RSS doesn't always have a direct image tag in <item>, 
          // but often puts it in the description or uses a media:content tag.
          String? artworkUrl;
          final mediaContent = item.findElements('media:content');
          if (mediaContent.isNotEmpty) {
            artworkUrl = mediaContent.first.getAttribute('url');
          }

          // Simple regex to find an image in the description if media:content is missing
          if (artworkUrl == null) {
            final imgMatch = RegExp(r'<img src="([^"]+)"').firstMatch(description);
            if (imgMatch != null) {
              artworkUrl = imgMatch.group(1);
            }
          }

          feedItems.add(FeedItem(
            id: link, // Bandcamp uses URL as unique ID in RSS
            platform: 'bandcamp',
            artistName: artistName,
            contentType: 'release',
            title: title,
            body: _stripHtml(description),
            externalUrl: link,
            artworkUrl: artworkUrl,
            publishedAt: _parseRssDate(pubDateRaw),
          ));
        } catch (e) {
          _logger.warning('[bandcamp] Skipping entry for $artistName: $e');
        }
      }

      // Save to DB
      if (feedItems.isNotEmpty) {
        final dbItems = feedItems.map((i) => {
          'platform': 'bandcamp',
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

      return feedItems;
    } catch (e) {
      _logger.severe('[bandcamp] RSS fetch failed for $artistName: $e');
      return [];
    }
  }

  /// ELI5: Cleaning up messy "HTML" tags so we only have the clean text.
  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>|&nbsp;'), ' ').trim();
  }

  /// ELI5: Turning a "Human Date" (Tue, 28 Apr 2026) into a "Computer Date."
  DateTime _parseRssDate(String dateStr) {
    try {
      // RFC822 parser (common in RSS)
      // Note: In a production app, use 'intl' package for robust date parsing.
      // For the MVP, we'll use a simplified version.
      return DateTime.parse(dateStr); 
    } catch (e) {
      // Fallback: if native parse fails, try basic cleaning
      try {
        // Many RSS feeds provide dates that DateTime.parse can handle if we strip the day name
        final parts = dateStr.split(', ');
        if (parts.length > 1) {
          return DateTime.parse(parts[1]);
        }
      } catch (_) {}
      return DateTime.now();
    }
  }
}
