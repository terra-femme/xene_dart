import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../repositories/publication_repository.dart';

final _logger = Logger('PublicationPollerService');

const _pollTtl = Duration(hours: 2);

/// Fetches RSS feeds for every enabled press_publication and persists the
/// parsed articles to publication_articles.
///
/// Supports RSS 2.0 (<item>) and Atom 1.0 (<entry>). Handles CDATA sections,
/// media namespace extensions for images, and RFC 822 / ISO 8601 date formats.
///
/// Each publication is polled sequentially — parallel fetching would saturate
/// the server's outbound connections and trigger rate limits on publication
/// domains. The 4-hour cron window is large enough for serial execution.
class PublicationPollerService {
  PublicationPollerService(this._repo, this._dio);

  final PublicationRepository _repo;
  final Dio _dio;

  /// Polls all enabled publications in tier + name order.
  ///
  /// When [force] is false (default), publications polled within the last
  /// [_pollTtl] are skipped — applies to both scheduled and manual runs.
  /// Pass [force]=true from the admin endpoint to override.
  ///
  /// Errors on individual publications are swallowed — one bad feed must not
  /// abort the rest of the run.
  Future<Map<String, dynamic>> pollAll({bool force = false}) async {
    final publications = await _repo.getEnabledPublications();
    _logger.info(
      '[PublicationPoller] pollAll start: ${publications.length} publications'
      '${force ? " (force=true, TTL skip disabled)" : ""}',
    );

    var succeeded = 0;
    var failed = 0;
    var skipped = 0;
    var articlesTotal = 0;

    for (final pub in publications) {
      if (!force) {
        final lastPolledStr = pub['last_polled'] as String?;
        if (lastPolledStr != null) {
          final lastPolled = DateTime.tryParse(lastPolledStr)?.toUtc();
          if (lastPolled != null) {
            final age = DateTime.now().toUtc().difference(lastPolled);
            if (age < _pollTtl) {
              final name = pub['name'] as String? ?? 'Unknown';
              _logger.fine(
                '[PublicationPoller] $name: skipped '
                '(polled ${age.inMinutes}m ago, TTL=${_pollTtl.inHours}h)',
              );
              skipped++;
              continue;
            }
          }
        }
      }

      final result = await _pollOne(pub);
      if (result >= 0) {
        succeeded++;
        articlesTotal += result;
      } else {
        failed++;
      }
    }

    _logger.info(
      '[PublicationPoller] pollAll complete: '
      'succeeded=$succeeded failed=$failed skipped=$skipped articles=$articlesTotal',
    );

    return {
      'publications_polled': succeeded + failed,
      'skipped': skipped,
      'succeeded': succeeded,
      'failed': failed,
      'articles_saved': articlesTotal,
    };
  }

  /// Polls a single publication. Returns the number of articles saved on
  /// success, or -1 on failure.
  Future<int> _pollOne(Map<String, dynamic> pub) async {
    final pubId = pub['id'] as String;
    final name = pub['name'] as String? ?? 'Unknown';
    final rssUrl = pub['rss_url'] as String?;
    final urlFilter = pub['article_url_filter'] as String?;

    if (rssUrl == null || rssUrl.isEmpty) {
      _logger.warning('[PublicationPoller] $name: no rss_url, skipping');
      return -1;
    }

    _logger.info('[PublicationPoller] Polling $name → $rssUrl');

    try {
      final response = await _dio.get<String>(
        rssUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 10),
          headers: {'User-Agent': 'Xene/1.0 (+https://xene.app; RSS reader)'},
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        _logger.warning('[PublicationPoller] $name: HTTP $statusCode');
        await _repo.stampPollFailure(
          pubId,
          'HTTP $statusCode',
          statusCode: statusCode,
        );
        return -1;
      }

      final body = response.data ?? '';
      if (body.isEmpty) {
        _logger.warning('[PublicationPoller] $name: empty response body');
        await _repo.stampPollFailure(pubId, 'Empty response body');
        return -1;
      }

      _logger.fine('[PublicationPoller] $name: ${body.length} bytes received');

      var articles = _parseRss(body, pubId);
      if (urlFilter != null && urlFilter.isNotEmpty) {
        final before = articles.length;
        articles = articles
            .where((a) => (a['url'] as String? ?? '').contains(urlFilter))
            .toList();
        _logger.fine(
          '[PublicationPoller] $name: url_filter="$urlFilter" kept ${articles.length}/$before articles',
        );
      }
      _logger.info(
        '[PublicationPoller] $name: parsed ${articles.length} articles',
      );

      if (articles.isNotEmpty) {
        await _repo.saveArticles(articles);
      }
      await _repo.stampPollSuccess(pubId);
      return articles.length;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      final msg = 'DioException ${e.type.name}: ${e.message}';
      _logger.warning('[PublicationPoller] $name failed: $msg');
      await _repo.stampPollFailure(pubId, msg, statusCode: statusCode);
      return -1;
    } catch (e, st) {
      _logger.warning('[PublicationPoller] $name unexpected error: $e\n$st');
      await _repo.stampPollFailure(pubId, e.toString());
      return -1;
    }
  }

  /// Parses an RSS 2.0 or Atom 1.0 feed body into article row maps.
  List<Map<String, dynamic>> _parseRss(String body, String publicationId) {
    final articles = <Map<String, dynamic>>[];
    try {
      final doc = XmlDocument.parse(body);

      // RSS 2.0 uses <item>; Atom 1.0 uses <entry>
      final items = [
        ...doc.findAllElements('item'),
        ...doc.findAllElements('entry'),
      ];

      _logger.fine('[PublicationPoller] feed has ${items.length} items');

      for (final item in items) {
        final title = _text(item, ['title'])?.trim();
        if (title == null || title.isEmpty) continue;

        final url = _extractUrl(item);
        if (url == null || url.isEmpty) continue;

        final snippet = _extractSnippet(item);
        final author = _text(item, ['author', 'creator']);
        final imageUrl = _extractImageUrl(item);
        final publishedAt = _extractDate(item);

        articles.add({
          'publication_id': publicationId,
          'title': title,
          'url': url,
          if (snippet != null && snippet.isNotEmpty) 'snippet': snippet,
          if (author != null && author.isNotEmpty) 'author': author,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          if (publishedAt != null) 'published_at': publishedAt,
          // expires_at defaults to now() + 7 days in the schema
        });
      }
    } on XmlException catch (e) {
      _logger.warning('[PublicationPoller] XML parse error: $e');
    } catch (e) {
      _logger.warning('[PublicationPoller] _parseRss unexpected error: $e');
    }
    return articles;
  }

  /// Finds the first non-empty text value from the listed element names.
  /// Tries exact qualified name first, then matches by local name to handle
  /// namespace prefix variation (e.g. dc:creator vs creator).
  String? _text(XmlElement item, List<String> candidates) {
    for (final tag in candidates) {
      final localName = tag.contains(':') ? tag.split(':').last : tag;

      final el =
          item.findElements(tag).firstOrNull ??
          item.children
              .whereType<XmlElement>()
              .where((e) => e.name.local == localName)
              .firstOrNull;

      final text = el?.innerText.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  String? _extractUrl(XmlElement item) {
    // Atom: <link href="url"/> — element may be empty with href attribute
    for (final el in item.findElements('link')) {
      final href = el.getAttribute('href');
      if (href != null && href.trim().isNotEmpty) return href.trim();
      // RSS 2.0: <link>url</link>
      final text = el.innerText.trim();
      if (text.isNotEmpty) return text;
    }
    // Atom fallback: <id>url</id> — Atom uses IRI in <id>
    final id = item.findElements('id').firstOrNull;
    final idText = id?.innerText.trim() ?? '';
    if (idText.startsWith('http')) return idText;
    return null;
  }

  String? _extractSnippet(XmlElement item) {
    for (final tag in ['description', 'summary', 'content']) {
      final el = item.findElements(tag).firstOrNull;
      if (el == null) continue;
      final raw = el.innerText.trim();
      if (raw.isEmpty) continue;
      // Strip HTML tags that appear inside CDATA description blocks
      final clean = raw
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (clean.isEmpty) continue;
      return clean.length > 300 ? '${clean.substring(0, 297)}...' : clean;
    }
    return null;
  }

  String? _extractImageUrl(XmlElement item) {
    // <media:thumbnail url="..."/> — most common in electronic music publications
    for (final el in item.children.whereType<XmlElement>()) {
      if (el.name.local == 'thumbnail') {
        final url = el.getAttribute('url');
        if (url != null && url.isNotEmpty) return url.trim();
      }
      if (el.name.local == 'content') {
        final url = el.getAttribute('url');
        final medium = el.getAttribute('medium') ?? '';
        if (url != null && url.isNotEmpty && medium == 'image')
          return url.trim();
      }
    }
    // <enclosure url="..." type="image/..."/>
    for (final el in item.findElements('enclosure')) {
      final type = el.getAttribute('type') ?? '';
      if (!type.startsWith('image/')) continue;
      final url = el.getAttribute('url');
      if (url != null && url.isNotEmpty) return url.trim();
    }
    return null;
  }

  String? _extractDate(XmlElement item) {
    final raw =
        _text(item, ['pubDate', 'published', 'updated', 'date']) ??
        _text(item, ['dc:date']);
    if (raw == null) return null;
    try {
      return DateTime.parse(raw).toUtc().toIso8601String();
    } catch (_) {
      return _parseRfc822(raw)?.toUtc().toIso8601String();
    }
  }

  static const _months = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  /// Parses RFC 822 dates used by RSS 2.0.
  /// Example: "Mon, 01 Jan 2024 12:00:00 +0000"
  DateTime? _parseRfc822(String raw) {
    try {
      // Strip optional leading weekday
      final clean = raw.trim().replaceFirst(RegExp(r'^[A-Za-z]+,\s*'), '');
      final parts = clean.split(RegExp(r'\s+'));
      if (parts.length < 4) return null;
      final day = int.parse(parts[0]);
      final month = _months[parts[1]] ?? 1;
      final year = int.parse(parts[2]);
      final timeParts = parts[3].split(':');
      if (timeParts.length < 2) return null;
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;
      return DateTime.utc(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}
