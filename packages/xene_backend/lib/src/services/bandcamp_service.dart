import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:xml/xml.dart';
import 'package:xene_domain/xene_domain.dart';
import '../database.dart';
import 'api_analytics_service.dart';

final _logger = Logger('BandcampService');

class _BcCacheEntry {
  final List<FeedItem> items;
  final DateTime fetchedAt;
  _BcCacheEntry(this.items, this.fetchedAt);
}

class BandcampTransientException implements Exception {
  BandcampTransientException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One entry from the data-client-items blob, with raw date fields exposed.
class BcBlobEntry {
  const BcBlobEntry({
    required this.position,
    this.title,
    this.pageUrl,
    this.type,
    this.featuredDate,
    this.modDate,
    this.rawFeaturedDt,
    this.rawModDt,
    required this.processZone,
  });

  final int position;
  final String? title;
  final String? pageUrl;
  final String? type;
  final DateTime? featuredDate;
  final DateTime? modDate;
  final String? rawFeaturedDt;
  final String? rawModDt;

  /// `json` = positions 0–39 (tralbum API), `overflow` = 40–79 (page fetch),
  /// `missed` = ≥ 80 (beyond processing cap).
  final String processZone;
}

/// One item from the Bandcamp RSS /feed, with the raw pubDate string preserved.
class BcRssEntry {
  const BcRssEntry({
    required this.title,
    required this.rawPubDate,
    this.pubDate,
  });

  final String title;
  final String rawPubDate;
  final DateTime? pubDate;
}

/// Diagnostic snapshot of the data-client-items blob, HTML grid, and RSS feed.
class BcDebugReport {
  const BcDebugReport({
    required this.blobEntries,
    required this.gridUrls,
    required this.rssEntries,
  });

  final List<BcBlobEntry> blobEntries;
  final List<String> gridUrls;
  final List<BcRssEntry> rssEntries;
}

class BandcampService {
  BandcampService(this._db, {ApiAnalyticsService? analytics})
    : _dio = analytics?.trackDio(_createDio(), 'bandcamp') ?? _createDio();

  final DatabaseService _db;

  // In-memory feed cache (2-hour TTL) — mirrors bandcamp.py _feed_cache.
  final _feedCache = <String, _BcCacheEntry>{};
  static const _feedCacheTtl = Duration(hours: 2);

  static const _tralbumApi =
      'https://bandcamp.com/api/mobile/25/tralbum_details';
  static const _artUrlTemplate = 'https://f4.bcbits.com/img/a{id}_16.jpg';

  // data-client-items or data-tralbums attribute in the /music page HTML
  static final _clientItemsRe = RegExp(
    r'data-(?:client-items|tralbums)="([^"]+)"',
  );

  // Grid path regexes
  static final _musicGridRe = RegExp(
    r'<ol[^>]+id="music-grid"[^>]*>([\s\S]*?)</ol>',
  );
  static final _gridItemRe = RegExp(
    r'<li[^>]+class="[^"]*music-grid-item[^"]*"[^>]*>[\s\S]*?<a[^>]+href="([^"]+)"',
  );

  // Release page extraction — application/ld+json (stable schema.org structured data)
  static final _ldJsonRe = RegExp(
    r'<script[^>]+type="application/ld\+json"[^>]*>([\s\S]*?)</script>',
  );
  // Bandcamp image URL → extract art_id: /a{id}_{size}.jpg
  static final _bcArtIdFromUrl = RegExp(r'/a(\d+)_\d+\.jpg');
  // Raw fallback regexes for pages that don't have full ld+json
  static final _pubDateRe = RegExp(r'"publish_date"\s*:\s*(\d+)');
  static final _relDateRe = RegExp(r'"release_date"\s*:\s*(\d+)');
  static final _artIdPageRe = RegExp(r'"art_id"\s*:\s*(\d+)');
  static final _embeddedPlayerSrcRe = RegExp(
    r'<iframe[^>]+src="(https://bandcamp\.com/EmbeddedPlayer/[^"]+)"',
  );
  // Genre tag extraction — matches <a class="tag">drum and bass</a>
  static final _bcTagRe = RegExp(r'<a[^>]+class="tag"[^>]*>([^<]+)<\/a>');

  final Dio _dio;

  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
      },
    ),
  );

  /// Strip any stored path from a Bandcamp URL and return the artist root.
  /// Handles any format: root, /music, /feed, /album/slug (from SC web profiles), etc.
  String _baseUrl(String url) {
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return url;
    }
  }

  String _htmlUnescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  // ── Public entry point ──────────────────────────────────────────────────────

  /// Fetch Bandcamp releases.
  /// Runs the two-path scraper (/music page) AND RSS (/feed) in parallel.
  /// Scraper uses the JSON path (data-client-items) + HTML grid path.
  /// RSS fills any recency gap. All results deduped by normalised URL.
  /// If [auditSink] is supplied, raw date fields are appended per item
  /// for the audit report.
  Future<List<FeedItem>> getFeed(
    String bandcampUrl,
    String artistName, {
    bool bypassMemoryCache = false,
    List<Map<String, dynamic>>? auditSink,
  }) async {
    final base = _baseUrl(bandcampUrl);
    _logger.info('[bandcamp] Normalized base: $bandcampUrl → $base');

    // Check in-memory cache first (2-hour TTL).
    final cached = _feedCache[base];
    if (!bypassMemoryCache &&
        cached != null &&
        DateTime.now().toUtc().difference(cached.fetchedAt) < _feedCacheTtl) {
      _logger.info(
        '[bandcamp] Cache HIT for $artistName at $base (${cached.items.length} items)',
      );
      return cached.items;
    }

    _logger.info(
      '[bandcamp] Starting feed fetch for $artistName at $base'
      '${bypassMemoryCache ? ' (manual refresh bypass)' : ''}',
    );

    // Run both sources in parallel — RSS is fast and covers the recency gap.
    List<FeedItem> scraperItems = [];
    List<FeedItem> rssItems = [];
    Object? transientFailure;
    // Collects genre tags from <a class="tag"> across all fetched release pages.
    final genreTagSink = <String>{};

    await Future.wait([
      () async {
        try {
          scraperItems = await _scrapeMusicPage(
            base,
            artistName,
            auditSink: auditSink,
            genreTagSink: genreTagSink,
          );
        } catch (e) {
          if (_isTransientBandcampError(e)) transientFailure ??= e;
          _logger.warning(
            '[bandcamp] Scraper failed for $artistName: ${_shortError(e)}',
          );
        }
      }(),
      () async {
        try {
          rssItems = await _fetchViaRss(base, artistName, auditSink: auditSink);
        } catch (e) {
          if (_isTransientBandcampError(e)) transientFailure ??= e;
          _logger.warning(
            '[bandcamp] RSS fetch failed for $artistName: ${_shortError(e)}',
          );
        }
      }(),
    ]);

    // Merge: scraper items first (richer metadata); RSS fills anything not
    // yet in data-client-items. Dedup by normalised external URL.
    final byUrl = <String, FeedItem>{};
    for (final item in [...scraperItems, ...rssItems]) {
      final key = _normaliseUrl(item.externalUrl);
      byUrl.putIfAbsent(key.isNotEmpty ? key : item.id, () => item);
    }
    final items = byUrl.values.toList();

    _logger.info(
      '[bandcamp] Merged: ${scraperItems.length} scraper + ${rssItems.length} RSS '
      '= ${items.length} unique for $artistName',
    );

    if (items.isNotEmpty) {
      final dbItems = items
          .map(
            (i) => {
              'platform': 'bandcamp',
              'internal_id': i.id,
              'artist_name': artistName,
              'content_type': i.contentType,
              'title': i.title,
              'body': i.body,
              'media_url': i.mediaUrl,
              'artwork_url': i.artworkUrl,
              'external_url': i.externalUrl,
              'published_at': i.publishedAt.toIso8601String(),
              'track_count': i.trackCount,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
          )
          .toList();
      await _db.saveFeedItems(dbItems);

      // Persist genre tags collected from release page HTML (non-fatal).
      if (genreTagSink.isNotEmpty) {
        _logger.info('[bandcamp] Genre tags for $artistName: $genreTagSink');
        await _db
            .updateArtistGenreTags(genreTagSink.toList(), bandcampUrl: base)
            .catchError((Object e) {
              _logger.warning(
                '[bandcamp] Genre tags update skipped for $artistName: $e',
              );
            });
      }

      _feedCache[base] = _BcCacheEntry(items, DateTime.now().toUtc());
      _logger.info(
        '[bandcamp] Saved ${items.length} items for $artistName + wrote cache',
      );
    } else {
      if (transientFailure != null) {
        throw BandcampTransientException(
          'Transient Bandcamp failure for $artistName at $base: '
          '${_shortError(transientFailure!)}',
        );
      }
      _logger.warning('[bandcamp] No items found for $artistName at $base');
    }

    return items;
  }

  // ── Two-path scraper ────────────────────────────────────────────────────────

  /// Fetches /music page and runs the JSON path, HTML grid path, and JSON
  /// blob overflow path (positions 40–79 in the blob via page fetch).
  Future<List<FeedItem>> _scrapeMusicPage(
    String base,
    String artistName, {
    List<Map<String, dynamic>>? auditSink,
    Set<String>? genreTagSink,
  }) async {
    final musicUrl = '$base/music';
    _logger.info('[bandcamp] Scraping music page: $musicUrl');

    final resp = await _dio.get<String>(
      musicUrl,
      options: Options(validateStatus: _acceptClientErrors),
    );
    if (resp.statusCode == 429) {
      throw BandcampTransientException(
        'Bandcamp rate limited music page for $artistName at $musicUrl',
      );
    }
    if (resp.statusCode != 200) {
      _logger.warning(
        '[bandcamp] Music page ${resp.statusCode} for $artistName',
      );
      return [];
    }
    final html = resp.data!;

    // Path 1: JSON (data-client-items) — firstMatch + 40-item cap, mirrors Python .search()
    final jsonItems = await _parseDataClientItems(
      html,
      base,
      artistName,
      auditSink: auditSink,
    );

    // Path 2: HTML grid — fetches individual release pages; catches Featured items
    // that aren't yet surfaced in data-client-items (CDN lag / brand-new releases).
    List<FeedItem> gridItems = [];
    try {
      gridItems = await _scrapeGridHtml(
        html,
        base,
        artistName,
        auditSink: auditSink,
        genreTagSink: genreTagSink,
      );
    } catch (e) {
      if (jsonItems.isEmpty || !_isTransientBandcampError(e)) rethrow;
      _logger.warning(
        '[bandcamp] Grid path failed for $artistName; using JSON path only: '
        '${_shortError(e)}',
      );
    }

    // Path 3: JSON blob overflow — page_urls at positions 40–79 skipped by
    // the tralbum-API cap. Large labels (Overview, etc.) can have 100+ releases
    // in the blob; new items land after position 40 before CDN lag catches up.
    List<FeedItem> overflowItems = [];
    try {
      overflowItems = await _scrapeJsonBlobOverflow(
        html,
        base,
        artistName,
        alreadyProcessed: jsonItems,
        auditSink: auditSink,
        genreTagSink: genreTagSink,
      );
    } catch (e) {
      _logger.warning(
        '[bandcamp] JSON blob overflow path failed for $artistName: '
        '${_shortError(e)}',
      );
    }

    // Merge: grid first (newest/featured), then overflow, then JSON path.
    // Dedup by normalised URL so no release is counted twice.
    final byUrl = <String, FeedItem>{};
    for (final item in [...gridItems, ...overflowItems, ...jsonItems]) {
      final key = _normaliseUrl(item.externalUrl);
      byUrl.putIfAbsent(key.isNotEmpty ? key : item.id, () => item);
    }

    final merged = byUrl.values.toList();
    _logger.info(
      '[bandcamp] Merged: ${gridItems.length} grid + ${overflowItems.length} overflow '
      '+ ${jsonItems.length} json = ${merged.length} unique for $artistName',
    );
    return merged;
  }

  /// JSON blob overflow path — processes page_urls from the blob at positions
  /// [skipCount, skipCount + maxOverflow) that were skipped by the 40-item
  /// tralbum-API cap. Uses _fetchReleasePageDetail (ld+json) for date accuracy.
  Future<List<FeedItem>> _scrapeJsonBlobOverflow(
    String html,
    String base,
    String artistName, {
    required List<FeedItem> alreadyProcessed,
    int skipCount = 40,
    int maxOverflow = 40,
    List<Map<String, dynamic>>? auditSink,
    Set<String>? genreTagSink,
  }) async {
    final match = _clientItemsRe.firstMatch(html);
    if (match == null) return [];

    List<dynamic> releases;
    try {
      releases = jsonDecode(_htmlUnescape(match.group(1)!)) as List<dynamic>;
    } catch (e) {
      return [];
    }

    final overflow = releases
        .cast<Map<String, dynamic>>()
        .skip(skipCount)
        .take(maxOverflow)
        .toList();

    if (overflow.isEmpty) {
      _logger.info(
        '[bandcamp] JSON blob overflow: no items beyond position $skipCount '
        'for $artistName (blob has ${releases.length} total)',
      );
      return [];
    }

    _logger.info(
      '[bandcamp] JSON blob overflow: ${overflow.length} items at positions '
      '$skipCount–${skipCount + overflow.length - 1} '
      '(blob total=${releases.length}) for $artistName',
    );

    // Skip URLs already covered by the tralbum-API path.
    final alreadyUrls = alreadyProcessed
        .map((i) => _normaliseUrl(i.externalUrl))
        .toSet();

    final hrefs = <String>[];
    for (final r in overflow) {
      final pageUrl = r['page_url'] as String?;
      if (pageUrl == null || pageUrl.isEmpty) continue;
      final url = pageUrl.startsWith('/') ? '$base$pageUrl' : pageUrl;
      if (!alreadyUrls.contains(_normaliseUrl(url))) hrefs.add(url);
    }

    if (hrefs.isEmpty) return [];
    _logger.info(
      '[bandcamp] JSON blob overflow: ${hrefs.length} new hrefs to fetch '
      'for $artistName',
    );

    final items = <FeedItem>[];
    for (var i = 0; i < hrefs.length; i += 2) {
      final batch = hrefs.sublist(i, (i + 2).clamp(0, hrefs.length));
      final results = await Future.wait(
        batch.map(
          (url) => _fetchReleasePageDetail(
            url,
            artistName,
            path: 'overflow',
            auditSink: auditSink,
            genreTagSink: genreTagSink,
          ),
        ),
        eagerError: false,
      );
      for (final item in results) {
        if (item != null) items.add(item);
      }
      if (i + 2 < hrefs.length) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }

    _logger.info(
      '[bandcamp] JSON blob overflow built ${items.length} items for $artistName',
    );
    return items;
  }

  /// JSON path — mirrors Python _parse_data_client_items.
  /// Uses firstMatch (.search()) and caps at 40 items.
  Future<List<FeedItem>> _parseDataClientItems(
    String html,
    String base,
    String artistName, {
    List<Map<String, dynamic>>? auditSink,
  }) async {
    final match = _clientItemsRe.firstMatch(html);
    if (match == null) {
      _logger.warning('[bandcamp] No data-client-items found for $artistName');
      return [];
    }

    List<dynamic> releases;
    try {
      releases = jsonDecode(_htmlUnescape(match.group(1)!)) as List<dynamic>;
    } catch (e) {
      _logger.warning(
        '[bandcamp] Failed to parse data-client-items JSON for $artistName: $e',
      );
      return [];
    }

    int? bandId;
    for (final raw in releases.cast<Map<String, dynamic>>()) {
      bandId = _toIntOrNull(raw['band_id']);
      if (bandId != null) break;
    }

    if (bandId == null) {
      _logger.warning(
        '[bandcamp] No band_id in data-client-items for $artistName',
      );
      return [];
    }

    // Newest-first; cap at 40 (mirrors Python LIMIT=40).
    final toProcess = releases.cast<Map<String, dynamic>>().take(40).toList();
    _logger.info(
      '[bandcamp] JSON path: ${toProcess.length} releases to fetch for $artistName',
    );

    final capturedBandId = bandId;
    final items = <FeedItem>[];
    for (var i = 0; i < toProcess.length; i += 5) {
      final batch = toProcess.sublist(i, (i + 5).clamp(0, toProcess.length));
      final details = await Future.wait(
        batch.map(
          (r) => _fetchReleaseDetail(
            tralbumId: _toInt(r['id']),
            bandId: capturedBandId,
            tralbumType: (r['type'] as String? ?? 'album')[0],
          ),
        ),
        eagerError: false,
      );
      for (var j = 0; j < batch.length; j++) {
        final item = _buildFeedItem(
          batch[j],
          details[j],
          base,
          artistName,
          auditSink: auditSink,
        );
        if (item != null) items.add(item);
      }
    }

    _logger.info(
      '[bandcamp] JSON path built ${items.length} items for $artistName',
    );
    return items;
  }

  /// HTML grid path — mirrors Python _scrape_grid_html.
  /// Parses <ol id="music-grid"> and fetches up to 20 individual release pages.
  Future<List<FeedItem>> _scrapeGridHtml(
    String html,
    String base,
    String artistName, {
    List<Map<String, dynamic>>? auditSink,
    Set<String>? genreTagSink,
  }) async {
    final gridMatch = _musicGridRe.firstMatch(html);
    if (gridMatch == null) {
      _logger.info('[bandcamp] No music-grid in HTML for $artistName');
      return [];
    }
    final gridHtml = gridMatch.group(1)!;

    final hrefs = _gridItemRe
        .allMatches(gridHtml)
        .map((m) => m.group(1)!)
        .take(20)
        .toList();

    _logger.info(
      '[bandcamp] Grid path: ${hrefs.length} items found for $artistName',
    );
    if (hrefs.isEmpty) return [];

    final items = <FeedItem>[];
    for (var i = 0; i < hrefs.length; i += 2) {
      final batch = hrefs.sublist(i, (i + 2).clamp(0, hrefs.length));
      final results = await Future.wait(
        batch.map((href) {
          final url = href.startsWith('http') ? href : '$base$href';
          return _fetchReleasePageDetail(
            url,
            artistName,
            path: 'grid',
            auditSink: auditSink,
            genreTagSink: genreTagSink,
          );
        }),
        eagerError: false,
      );
      for (final item in results) {
        if (item != null) items.add(item);
      }
      // Polite delay between batches to avoid Bandcamp 429 rate limiting.
      if (i + 2 < hrefs.length) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }

    _logger.info(
      '[bandcamp] Grid path built ${items.length} items for $artistName',
    );
    return items;
  }

  /// Fetches an individual release page and extracts metadata via application/ld+json.
  Future<FeedItem?> _fetchReleasePageDetail(
    String url,
    String artistName, {
    String path = 'grid',
    List<Map<String, dynamic>>? auditSink,
    Set<String>? genreTagSink,
  }) async {
    try {
      _logger.info('[bandcamp] Grid: fetching release page $url');
      final resp = await _dio.get<String>(
        url,
        options: Options(validateStatus: _acceptClientErrors),
      );
      if (resp.statusCode == 429) {
        throw BandcampTransientException(
          'Bandcamp rate limited release page for $artistName at $url',
        );
      }
      if (resp.statusCode != 200) {
        _logger.warning(
          '[bandcamp] Grid release page ${resp.statusCode} for $url',
        );
        return null;
      }
      final html = resp.data!;

      // Extract <a class="tag"> elements for genre signal collection (Milestone 1).
      if (genreTagSink != null) {
        for (final m in _bcTagRe.allMatches(html)) {
          final tag = m.group(1)?.trim().toLowerCase();
          if (tag != null && tag.isNotEmpty) genreTagSink.add(tag);
        }
      }

      String? title;
      String? displayArtist;
      DateTime? publishedAt;
      String? artworkUrl;
      String? about;
      final embedUrl = _extractEmbeddedPlayerUrl(html);
      int trackCount = 0;
      bool foundMusicSchema = false;

      // Audit tracking variables — filled as date sources are discovered.
      String? rawDatePublished;
      String? rawReleaseTsStr;
      String? rawPublishTsStr;
      String? detailUsedField;

      // Primary: application/ld+json
      for (final m in _ldJsonRe.allMatches(html)) {
        Map<String, dynamic> data;
        try {
          data = jsonDecode(m.group(1)!) as Map<String, dynamic>;
        } catch (e) {
          _logger.fine('[bandcamp] Grid ld+json parse error at $url: $e');
          continue;
        }

        // @type can be a String OR a List — both are valid schema.org.
        final typeRaw = data['@type'];
        final type = typeRaw is List
            ? typeRaw.whereType<String>().join(',')
            : (typeRaw is String ? typeRaw : '');

        if (!type.contains('Music')) {
          _logger.fine(
            '[bandcamp] Grid ld+json skipping @type="$type" at $url',
          );
          continue;
        }

        foundMusicSchema = true;
        _logger.info('[bandcamp] Grid ld+json @type="$type" at $url');

        title ??= data['name'] as String?;

        final datePub = data['datePublished'] as String?;
        if (datePub != null && publishedAt == null) {
          rawDatePublished = datePub;
          publishedAt = _parseBandcampDate(datePub);
          if (publishedAt != null) detailUsedField = 'ld+json.datePublished';
          _logger.info(
            '[bandcamp] Grid datePublished="$datePub" → $publishedAt for $url',
          );
        }

        about ??= data['description'] as String?;

        // byArtist holds the actual performer(s), not the label.
        // Can be a Map or a List of Maps.
        if (displayArtist == null) {
          final byArtistRaw = data['byArtist'];
          if (byArtistRaw is Map<String, dynamic>) {
            displayArtist = byArtistRaw['name'] as String?;
          } else if (byArtistRaw is List) {
            final names = byArtistRaw
                .whereType<Map<String, dynamic>>()
                .map((a) => a['name'] as String?)
                .whereType<String>()
                .toList();
            if (names.isNotEmpty) displayArtist = names.join(', ');
          }
        }

        // image can be a String or a List in some schema.org variants.
        final imgRaw = data['image'];
        final imgUrl = imgRaw is String
            ? imgRaw
            : (imgRaw is List ? imgRaw.whereType<String>().firstOrNull : null);
        if (imgUrl != null && artworkUrl == null) {
          final artMatch = _bcArtIdFromUrl.firstMatch(imgUrl);
          artworkUrl = artMatch != null
              ? _artUrlTemplate.replaceFirst('{id}', artMatch.group(1)!)
              : imgUrl;
        }

        final numTracks = data['numTracks'];
        if (numTracks != null) trackCount = _toIntOrNull(numTracks) ?? 0;

        if (title != null && publishedAt != null) break;
      }

      if (!foundMusicSchema) {
        _logger.warning('[bandcamp] Grid: no Music ld+json at $url');
        _logger.warning(
          '[bandcamp] Grid HTML preview (first 800 chars): ${html.length > 800 ? html.substring(0, 800) : html}',
        );
      }

      // Fallback: raw Unix timestamp regexes.
      if (publishedAt == null) {
        rawReleaseTsStr = _relDateRe.firstMatch(html)?.group(1);
        rawPublishTsStr = _pubDateRe.firstMatch(html)?.group(1);
        final releaseTs = _toIntOrNull(rawReleaseTsStr);
        final publishTs = _toIntOrNull(rawPublishTsStr);
        final ts = releaseTs ?? publishTs;
        if (ts != null) {
          publishedAt = DateTime.fromMillisecondsSinceEpoch(
            ts * 1000,
            isUtc: true,
          );
          detailUsedField = releaseTs != null
              ? 'release_date_ts'
              : 'publish_date_ts';
          _logger.info(
            '[bandcamp] Grid fallback timestamp → $publishedAt for $url',
          );
        }
      }

      if (artworkUrl == null) {
        final artId = _toIntOrNull(_artIdPageRe.firstMatch(html)?.group(1));
        if (artId != null && artId != 0) {
          artworkUrl = _artUrlTemplate.replaceFirst('{id}', artId.toString());
        }
      }

      if (publishedAt == null || title == null || title.isEmpty) {
        _logger.warning(
          '[bandcamp] Grid: title=$title publishedAt=$publishedAt — skipping $url',
        );
        return null;
      }

      final contentType = trackCount <= 1
          ? 'track'
          : trackCount <= 6
          ? 'ep'
          : 'album';

      _logger.info(
        '[bandcamp] Grid item: "$title" '
        'publishedAt=${publishedAt.toIso8601String()} '
        'contentType=$contentType trackCount=$trackCount',
      );

      // Use the actual performer name if available; fall back to the label name.
      final effectiveArtist =
          (displayArtist != null && displayArtist.trim().isNotEmpty)
          ? _htmlUnescape(displayArtist.trim())
          : artistName;

      // Mandatory Title Augmentation (mirrors SoundCloudService)
      var finalTitle = _htmlUnescape(title);
      if (!finalTitle.toLowerCase().contains(effectiveArtist.toLowerCase())) {
        finalTitle = '$effectiveArtist - $finalTitle';
      }

      _logger.info(
        '[bandcamp] Grid item: "$finalTitle" '
        'publishedAt=${publishedAt.toIso8601String()} '
        'contentType=$contentType trackCount=$trackCount',
      );

      final item = FeedItem(
        id: 'bc_grid_${url.hashCode.abs()}',
        platform: 'bandcamp',
        artistName: artistName,
        contentType: contentType,
        title: finalTitle,
        body: about != null && about.trim().isNotEmpty ? about.trim() : null,
        mediaUrl: embedUrl,
        artworkUrl: artworkUrl,
        externalUrl: url,
        publishedAt: publishedAt,
        trackCount: trackCount,
      );

      auditSink?.add({
        'id': item.id,
        'path': path,
        'raw_datePublished': rawDatePublished,
        'raw_release_date_ts': rawReleaseTsStr,
        'raw_publish_date_ts': rawPublishTsStr,
        'usedField': detailUsedField ?? '-',
        'resolvedDate': publishedAt.toUtc().toIso8601String(),
      });

      return item;
    } catch (e, st) {
      if (_isTransientBandcampError(e)) rethrow;
      _logger.warning('[bandcamp] Grid page detail THREW for $url: $e\n$st');
      return null;
    }
  }

  /// Parses Bandcamp date strings — ISO 8601, "23 Apr 2026", "April 23, 2026".
  DateTime? _parseBandcampDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    try {
      return DateTime.parse(t).toUtc();
    } catch (_) {}
    final dmy = RegExp(r'^(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})').firstMatch(t);
    if (dmy != null) {
      final mo = _monthNum(dmy.group(2)!);
      final d = int.tryParse(dmy.group(1)!);
      final y = int.tryParse(dmy.group(3)!);
      if (mo != null && d != null && y != null)
        return DateTime.utc(y, mo, d, 12);
    }
    final mdy = RegExp(r'^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})').firstMatch(t);
    if (mdy != null) {
      final mo = _monthNum(mdy.group(1)!);
      final d = int.tryParse(mdy.group(2)!);
      final y = int.tryParse(mdy.group(3)!);
      if (mo != null && d != null && y != null)
        return DateTime.utc(y, mo, d, 12);
    }
    return null;
  }

  int? _monthNum(String name) {
    const m = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    return name.length >= 3 ? m[name.toLowerCase().substring(0, 3)] : null;
  }

  // ── Tralbum API (JSON path detail fetch) ───────────────────────────────────

  Future<Map<String, dynamic>?> _fetchReleaseDetail({
    required int tralbumId,
    required int bandId,
    required String tralbumType,
  }) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        _tralbumApi,
        queryParameters: {
          'tralbum_type': tralbumType,
          'tralbum_id': tralbumId,
          'band_id': bandId,
        },
        options: Options(validateStatus: _acceptClientErrors),
      );
      if (resp.statusCode == 200) return resp.data;
      if (resp.statusCode == 429) {
        throw BandcampTransientException(
          'Bandcamp rate limited tralbum detail id=$tralbumId',
        );
      }
      _logger.warning(
        '[bandcamp] tralbum detail id=$tralbumId status=${resp.statusCode}',
      );
    } catch (e) {
      if (_isTransientBandcampError(e)) rethrow;
      _logger.warning('[bandcamp] tralbum detail FAILED id=$tralbumId: $e');
    }
    return null;
  }

  FeedItem? _buildFeedItem(
    Map<String, dynamic> release,
    Map<String, dynamic>? detail,
    String base,
    String artistName, {
    List<Map<String, dynamic>>? auditSink,
  }) {
    try {
      final rawArtId = release['art_id'] ?? detail?['art_id'];
      final artIdInt = rawArtId != null ? _toInt(rawArtId) : 0;
      final artworkUrl = artIdInt != 0
          ? _artUrlTemplate.replaceFirst('{id}', artIdInt.toString())
          : null;

      final title = _htmlUnescape((release['title'] as String?) ?? '');
      final pageUrl = (release['page_url'] as String?) ?? '';
      final externalUrl = pageUrl.startsWith('/')
          ? '$base$pageUrl'
          : pageUrl.isNotEmpty
          ? pageUrl
          : base;

      String? body;
      DateTime? publishedAt;
      String? usedField;

      if (detail != null) {
        final rawAbout = detail['about'] as String?;
        if (rawAbout != null && rawAbout.trim().isNotEmpty) {
          body = rawAbout.trim();
        }

        if (body == null) {
          final credits = detail['credits'] as String?;
          if (credits != null && credits.trim().length > 10) {
            body = credits.trim();
          }
        }

        if (body == null) {
          final tracks = (detail['tracks'] as List?) ?? [];
          if (tracks.isNotEmpty) {
            final titles = tracks
                .take(4)
                .map(
                  (t) =>
                      ((t as Map<String, dynamic>?)?['title'] as String?) ?? '',
                )
                .where((t) => t.isNotEmpty)
                .toList();
            if (titles.isNotEmpty) {
              body = titles.join(' · ');
              if (tracks.length > 4) body = '$body…';
            }
          }
        }

        // Prefer release_date (public-facing on Bandcamp); fall back to publish_date.
        for (final key in ['release_date', 'publish_date', 'modified_date']) {
          final ts = detail[key];
          if (ts != null) {
            try {
              publishedAt = DateTime.fromMillisecondsSinceEpoch(
                _toInt(ts) * 1000,
                isUtc: true,
              );
              usedField = 'detail.$key';
              break;
            } catch (_) {}
          }
        }
      }

      if (publishedAt == null) {
        for (final key in ['featured_date', 'mod_date', 'last_mod_date']) {
          final ts = release[key];
          if (ts != null) {
            try {
              publishedAt = DateTime.fromMillisecondsSinceEpoch(
                _toInt(ts) * 1000,
                isUtc: true,
              );
              usedField = 'release.$key';
              break;
            } catch (_) {}
          }
        }
      }

      if (publishedAt == null) {
        _logger.fine('[bandcamp] Skipping "$title" — no parseable date');
        return null;
      }

      final trackList = (detail?['tracks'] as List?) ?? [];
      final trackCount = trackList.length;
      final contentType = trackCount <= 1
          ? 'track'
          : trackCount <= 6
          ? 'ep'
          : 'album';
      final tralbumType = (release['type'] as String? ?? 'album').toLowerCase();
      final embedUrl = _buildBandcampEmbedUrl(
        tralbumId: _toInt(release['id']),
        tralbumType: tralbumType,
      );

      final releaseArtist = release['artist'] as String?;
      final effectiveArtist =
          (releaseArtist != null && releaseArtist.trim().isNotEmpty)
          ? _htmlUnescape(releaseArtist.trim())
          : artistName;

      // Mandatory Title Augmentation (mirrors SoundCloudService)
      var finalTitle = title;
      if (!finalTitle.toLowerCase().contains(effectiveArtist.toLowerCase())) {
        finalTitle = '$effectiveArtist - $finalTitle';
      }

      final item = FeedItem(
        id: 'bc_${release['id']}',
        platform: 'bandcamp',
        artistName: artistName,
        contentType: contentType,
        title: finalTitle,
        body: body,
        mediaUrl: embedUrl,
        artworkUrl: artworkUrl,
        externalUrl: externalUrl,
        publishedAt: publishedAt,
        trackCount: trackCount,
      );

      auditSink?.add({
        'id': item.id,
        'path': 'json',
        'raw_release_date': detail?['release_date']?.toString(),
        'raw_publish_date': detail?['publish_date']?.toString(),
        'raw_modified_date': detail?['modified_date']?.toString(),
        'raw_featured_date': release['featured_date']?.toString(),
        'raw_mod_date': release['mod_date']?.toString(),
        'raw_last_mod_date': release['last_mod_date']?.toString(),
        'usedField': usedField ?? '-',
        'resolvedDate': publishedAt.toUtc().toIso8601String(),
      });

      return item;
    } catch (e) {
      _logger.warning('[bandcamp] Error building FeedItem for $artistName: $e');
      return null;
    }
  }

  // ── RSS fallback ────────────────────────────────────────────────────────────

  Future<List<FeedItem>> _fetchViaRss(
    String base,
    String artistName, {
    List<Map<String, dynamic>>? auditSink,
  }) async {
    final rssUrl = '$base/feed';
    _logger.info('[bandcamp] Fetching RSS: $rssUrl');

    final resp = await _dio.get<String>(
      rssUrl,
      options: Options(validateStatus: _acceptClientErrors),
    );
    if (resp.statusCode == 429) {
      throw BandcampTransientException(
        'Bandcamp rate limited RSS for $artistName at $rssUrl',
      );
    }
    if (resp.statusCode == 404) {
      _logger.info('[bandcamp] RSS not available for $artistName at $rssUrl');
      return [];
    }
    if (resp.statusCode != 200) {
      _logger.warning(
        '[bandcamp] RSS ${resp.statusCode} for $artistName at $rssUrl',
      );
      return [];
    }

    final document = XmlDocument.parse(resp.data!);
    final channel = document.findAllElements('channel').firstOrNull;
    if (channel == null) {
      _logger.warning('[bandcamp] RSS has no <channel> for $artistName');
      return [];
    }

    final items = <FeedItem>[];
    for (final item in channel.findElements('item')) {
      try {
        final title = item.findElements('title').firstOrNull?.innerText ?? '';
        final link = item.findElements('link').firstOrNull?.innerText ?? '';
        final pubDateRaw = item.findElements('pubDate').firstOrNull?.innerText;
        final description = item
            .findElements('description')
            .firstOrNull
            ?.innerText;

        String? artworkUrl;
        final mediaNodes = item.findElements('media:content');
        if (mediaNodes.isNotEmpty) {
          artworkUrl = mediaNodes.first.getAttribute('url');
        }
        if (artworkUrl == null && description != null) {
          final m = RegExp(
            "<img[^>]+src=[\"']([^\"']+)[\"']",
          ).firstMatch(description);
          if (m != null) artworkUrl = m.group(1);
        }

        final publishedAt = pubDateRaw != null
            ? _parseRssDate(pubDateRaw)
            : DateTime.now().toUtc();
        final slug = link.split('/').last.split('?').first;
        final itemId = slug.isNotEmpty
            ? 'bc_$slug'
            : 'bc_${link.hashCode.abs()}';

        // Mandatory Title Augmentation (mirrors SoundCloudService)
        var finalTitle = title;
        if (!finalTitle.toLowerCase().contains(artistName.toLowerCase())) {
          finalTitle = '$artistName - $finalTitle';
        }

        items.add(
          FeedItem(
            id: itemId,
            platform: 'bandcamp',
            artistName: artistName,
            contentType: 'release',
            title: finalTitle,
            body: description != null ? _stripHtml(description) : null,
            artworkUrl: artworkUrl,
            externalUrl: link,
            publishedAt: publishedAt,
          ),
        );

        auditSink?.add({
          'id': itemId,
          'path': 'rss',
          'raw_pubDate': pubDateRaw ?? '-',
          'usedField': pubDateRaw != null ? 'pubDate' : 'now()',
          'resolvedDate': publishedAt.toUtc().toIso8601String(),
        });
      } catch (e) {
        _logger.warning('[bandcamp] RSS entry parse error for $artistName: $e');
      }
    }

    _logger.info('[bandcamp] RSS built ${items.length} items for $artistName');
    return items;
  }

  // ── Audit / debug ──────────────────────────────────────────────────────────

  /// Fetches the /music page and /feed RSS and returns a raw date diagnostic
  /// report without normalising anything into FeedItems.  Only used by the
  /// feed_audit CLI tool.
  Future<BcDebugReport> getDebugReport(
    String bandcampUrl,
    String artistName,
  ) async {
    final base = _baseUrl(bandcampUrl);
    _logger.info('[bandcamp] getDebugReport for $artistName at $base');

    // Blob + grid ─────────────────────────────────────────────────────────────
    final blobEntries = <BcBlobEntry>[];
    final gridUrls = <String>[];

    try {
      final resp = await _dio.get<String>(
        '$base/music',
        options: Options(validateStatus: _acceptClientErrors),
      );
      if (resp.statusCode == 200) {
        final html = resp.data!;

        final match = _clientItemsRe.firstMatch(html);
        if (match != null) {
          try {
            final releases =
                jsonDecode(_htmlUnescape(match.group(1)!)) as List<dynamic>;
            for (var i = 0; i < releases.length; i++) {
              final r = releases[i] as Map<String, dynamic>;
              final rawFeatured = r['featured_date'];
              final rawMod = r['mod_date'];
              final featuredTs = _toIntOrNull(rawFeatured);
              final modTs = _toIntOrNull(rawMod);
              final processZone = i < 40
                  ? 'json'
                  : i < 80
                  ? 'overflow'
                  : 'missed';

              blobEntries.add(
                BcBlobEntry(
                  position: i,
                  title: r['title'] as String?,
                  pageUrl: r['page_url'] as String?,
                  type: r['type'] as String?,
                  rawFeaturedDt: rawFeatured?.toString(),
                  rawModDt: rawMod?.toString(),
                  featuredDate: featuredTs != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                          featuredTs * 1000,
                          isUtc: true,
                        )
                      : null,
                  modDate: modTs != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                          modTs * 1000,
                          isUtc: true,
                        )
                      : null,
                  processZone: processZone,
                ),
              );
            }
            _logger.info(
              '[bandcamp] Debug blob: ${blobEntries.length} entries '
              '(${blobEntries.where((e) => e.processZone == 'missed').length} missed) '
              'for $artistName',
            );
          } catch (e) {
            _logger.warning(
              '[bandcamp] Debug blob parse error for $artistName: $e',
            );
          }
        } else {
          _logger.warning(
            '[bandcamp] Debug: no data-client-items on /music page for $artistName',
          );
        }

        final gridMatch = _musicGridRe.firstMatch(html);
        if (gridMatch != null) {
          gridUrls.addAll(
            _gridItemRe
                .allMatches(gridMatch.group(1)!)
                .map((m) => m.group(1)!)
                .take(20),
          );
        }
      } else {
        _logger.warning(
          '[bandcamp] Debug music page ${resp.statusCode} for $artistName',
        );
      }
    } catch (e) {
      _logger.warning(
        '[bandcamp] Debug music page fetch failed for $artistName: ${_shortError(e)}',
      );
    }

    // RSS ─────────────────────────────────────────────────────────────────────
    final rssEntries = <BcRssEntry>[];

    try {
      final resp = await _dio.get<String>(
        '$base/feed',
        options: Options(validateStatus: _acceptClientErrors),
      );
      if (resp.statusCode == 200) {
        final document = XmlDocument.parse(resp.data!);
        final channel = document.findAllElements('channel').firstOrNull;
        if (channel != null) {
          for (final item in channel.findElements('item')) {
            final title =
                item.findElements('title').firstOrNull?.innerText ?? '';
            final rawPubDate =
                item.findElements('pubDate').firstOrNull?.innerText ?? '';
            final pubDate = rawPubDate.isNotEmpty
                ? _parseRssDate(rawPubDate)
                : null;
            rssEntries.add(
              BcRssEntry(
                title: title,
                rawPubDate: rawPubDate,
                pubDate: pubDate,
              ),
            );
          }
          _logger.info(
            '[bandcamp] Debug RSS: ${rssEntries.length} entries for $artistName',
          );
        }
      } else if (resp.statusCode != 404) {
        _logger.warning(
          '[bandcamp] Debug RSS ${resp.statusCode} for $artistName',
        );
      }
    } catch (e) {
      _logger.warning(
        '[bandcamp] Debug RSS fetch failed for $artistName: ${_shortError(e)}',
      );
    }

    return BcDebugReport(
      blobEntries: blobEntries,
      gridUrls: gridUrls,
      rssEntries: rssEntries,
    );
  }

  // ── Utilities ───────────────────────────────────────────────────────────────

  String _normaliseUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final s = '${uri.scheme}://${uri.host}${uri.path}'.toLowerCase();
      return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
    } catch (_) {
      final s = url.toLowerCase();
      return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
    }
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.parse(v.toString());
  }

  int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    try {
      return _toInt(v);
    } catch (_) {
      return null;
    }
  }

  String? _extractEmbeddedPlayerUrl(String html) {
    final match = _embeddedPlayerSrcRe.firstMatch(html);
    final raw = match?.group(1);
    if (raw == null || raw.isEmpty) return null;
    return _htmlUnescape(raw);
  }

  String _buildBandcampEmbedUrl({
    required int tralbumId,
    required String tralbumType,
  }) {
    final type = tralbumType == 'track' || tralbumType == 't'
        ? 'track'
        : 'album';
    return 'https://bandcamp.com/EmbeddedPlayer/'
        '$type=$tralbumId/'
        'size=large/'
        'bgcol=ffffff/'
        'linkcol=0687f5/'
        'tracklist=true/'
        'transparent=true/';
  }

  String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>|&nbsp;'), ' ').trim();

  DateTime _parseRssDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      try {
        final parts = dateStr.split(', ');
        if (parts.length > 1) return DateTime.parse(parts[1]);
      } catch (_) {}
      return DateTime.now().toUtc();
    }
  }

  bool _isTransientBandcampError(Object e) {
    if (e is BandcampTransientException) return true;
    if (e is DioException) {
      final status = e.response?.statusCode;
      return status == 429 ||
          status == 408 ||
          status == 502 ||
          status == 503 ||
          status == 504;
    }
    return false;
  }

  String _shortError(Object e) {
    if (e is BandcampTransientException) return e.message;
    if (e is DioException) {
      final status = e.response?.statusCode;
      final uri = e.requestOptions.uri;
      return status == null
          ? e.message ?? e.type.name
          : 'HTTP $status for $uri';
    }
    return e.toString();
  }

  bool _acceptClientErrors(int? status) => status != null && status < 500;
}
