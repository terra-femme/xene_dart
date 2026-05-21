import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import 'api_analytics_service.dart';

final _logger = Logger('DiscogsService');

class DiscogsService {
  DiscogsService({ApiAnalyticsService? analytics})
    : _dio = analytics?.trackDio(_createDio(), 'discogs') ?? _createDio();

  final Dio _dio;

  static Dio _createDio() => Dio(
    BaseOptions(
      baseUrl: 'https://api.discogs.com',
      headers: {
        'User-Agent': 'xene/1.0 (github.com/terra-femme/xene)',
        'Accept': 'application/vnd.discogs.v2.discogs+json',
      },
    ),
  );

  // Regex patterns for extraction
  static final _typeIdRe = RegExp(
    r'discogs\.com/(label|artist)/(\d+)',
    caseSensitive: false,
  );
  static final _bandcampRe = RegExp(
    r'https?://[a-zA-Z0-9-]+\.bandcamp\.com(?:/[^\s"\x27<>]*)?',
  );
  static final _beatportRe = RegExp(
    r'https?://(?:www\.)?beatport\.com/(?:label|artist)/[a-zA-Z0-9_%\-]+/(\d+)',
  );

  /// Parse (entity_type, numeric_id) from a Discogs URL.
  Map<String, String?> parseDiscogsUrl(String url) {
    final match = _typeIdRe.firstMatch(url);
    if (match == null) return {'type': null, 'id': null};
    return {'type': match.group(1)?.toLowerCase(), 'id': match.group(2)};
  }

  /// Scan external URL list and profile text for known platforms.
  Map<String, String> extractPlatformLinks(
    List<String> urls,
    String? profileText,
  ) {
    final found = <String, String>{};
    final combined = '${urls.join(" ")} ${profileText ?? ""}';

    final bcMatch = _bandcampRe.firstMatch(combined);
    if (bcMatch != null)
      found['bandcamp'] = bcMatch.group(0)!.replaceAll(RegExp(r'[.,)]$'), '');

    final bpMatch = _beatportRe.firstMatch(combined);
    if (bpMatch != null) found['beatport'] = bpMatch.group(0)!;

    for (final raw in urls) {
      final u = raw.trim().replaceAll(RegExp(r'[.,)/]$'), '');
      if (u.isEmpty) continue;

      if (u.contains('bandcamp.com') && !found.containsKey('bandcamp')) {
        found['bandcamp'] = u;
      } else if (u.contains('beatport.com') && !found.containsKey('beatport')) {
        found['beatport'] = u;
      } else if (u.contains('facebook.com') && !found.containsKey('facebook')) {
        found['facebook'] = u;
      } else if ((u.contains('twitter.com') || u.contains('x.com')) &&
          !found.containsKey('twitter')) {
        final parts = u.split('/');
        final username = parts.isNotEmpty
            ? parts.last.replaceFirst('@', '')
            : '';
        if (username.isNotEmpty &&
            !['home', 'share', 'intent'].contains(username)) {
          found['twitter'] = u;
        }
      } else if (u.contains('youtube.com') && !found.containsKey('youtube')) {
        if (!u.contains('/playlist?') &&
            !u.contains('/shorts/') &&
            !u.contains('/@browse')) {
          found['youtube'] = u;
        }
      } else if (u.contains('soundcloud.com') &&
          !found.containsKey('soundcloud')) {
        final scUser = u.split('/').last;
        if (scUser.isNotEmpty &&
            !['soundcloud', 'pages', 'stream', 'discover'].contains(scUser)) {
          found['soundcloud'] = u;
        }
      } else if (u.contains('spotify.com') && !found.containsKey('spotify')) {
        found['spotify'] = u;
      } else if (u.startsWith('http') && !found.containsKey('website')) {
        final isKnown = [
          'discogs.com',
          'facebook.com',
          'twitter.com',
          'x.com',
          'youtube.com',
          'soundcloud.com',
          'bandcamp.com',
          'beatport.com',
          'spotify.com',
          'apple.com',
          'amazon.com',
        ].any((domain) => u.contains(domain));
        if (!isKnown) found['website'] = u;
      }
    }

    return found;
  }

  /// Proactive Discogs search.
  Future<Map<String, dynamic>> searchEntity(
    String name, {
    String entityType = 'label',
  }) async {
    final consumerKey = Platform.environment['DISCOGS_CONSUMER_KEY'];
    final consumerSecret = Platform.environment['DISCOGS_CONSUMER_SECRET'];

    print('[DISCOGS] searchEntity called: name="$name" entityType=$entityType');
    print(
      '[DISCOGS] key set: ${consumerKey != null && consumerKey.isNotEmpty} secret set: ${consumerSecret != null && consumerSecret.isNotEmpty}',
    );

    if (consumerKey == null || consumerSecret == null) {
      print('[DISCOGS] ✗ credentials missing — skipping proactive search');
      _logger.warning('DISCOGS credentials missing — skipping search');
      return {};
    }

    final dgType = (entityType == 'label' || entityType == 'organization')
        ? 'label'
        : 'artist';

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/database/search',
        queryParameters: {
          'q': name,
          'type': dgType,
          'per_page': 5,
          'key': consumerKey,
          'secret': consumerSecret,
        },
      );

      final results = response.data?['results'] as List? ?? [];
      print(
        '[DISCOGS] search returned ${results.length} results for "$name" (type=$dgType)',
      );
      if (results.isEmpty) return {};

      Map<String, dynamic>? best;
      double bestScore = 0.0;
      for (final r in results) {
        final title = (r['title'] as String? ?? '').toLowerCase();
        final score = _calculateSimilarity(title, name.toLowerCase());
        if (score > bestScore) {
          bestScore = score;
          best = r as Map<String, dynamic>;
        }
      }

      print(
        '[DISCOGS] best match: "${best?['title']}" score=${bestScore.toStringAsFixed(2)} (threshold=0.80)',
      );

      if (best == null || bestScore < 0.80) {
        print('[DISCOGS] ✗ no match above threshold — returning empty');
        return {};
      }

      final bestType = best['type'] ?? dgType;
      final bestId = best['id'];
      final url = 'https://www.discogs.com/$bestType/$bestId';
      print('[DISCOGS] → fetching entity links for matched URL: $url');
      return await fetchEntityLinks(url);
    } catch (e) {
      print('[DISCOGS] ✗ searchEntity threw exception: $e');
      _logger.severe('Discogs search failed for $name: $e');
      return {};
    }
  }

  /// Fetch profile and extract links.
  Future<Map<String, dynamic>> fetchEntityLinks(String discogsUrl) async {
    final consumerKey = Platform.environment['DISCOGS_CONSUMER_KEY'];
    final consumerSecret = Platform.environment['DISCOGS_CONSUMER_SECRET'];

    print('[DISCOGS] fetchEntityLinks called: $discogsUrl');
    print(
      '[DISCOGS] key set: ${consumerKey != null && consumerKey.isNotEmpty} secret set: ${consumerSecret != null && consumerSecret.isNotEmpty}',
    );

    if (consumerKey == null || consumerSecret == null) {
      print('[DISCOGS] ✗ credentials missing — aborting');
      return {};
    }

    final parsed = parseDiscogsUrl(discogsUrl);
    final type = parsed['type'];
    final id = parsed['id'];

    print('[DISCOGS] parsed type=$type id=$id');

    if (type == null || id == null) {
      // Slug-form URL (e.g. discogs.com/label/V+Recordings) — no numeric ID present.
      // Extract entity type + name from the slug and fall back to proactive search.
      final slugRe = RegExp(
        r'discogs\.com/(label|artist)/([^/?#]+)',
        caseSensitive: false,
      );
      final slugMatch = slugRe.firstMatch(discogsUrl);
      if (slugMatch != null) {
        final slugType = slugMatch.group(1)!.toLowerCase();
        final slugName = Uri.decodeComponent(
          slugMatch.group(2)!.replaceAll('+', ' '),
        ).trim();
        print(
          '[DISCOGS] slug-form URL detected — type=$slugType name="$slugName" — falling back to search',
        );
        return await searchEntity(slugName, entityType: slugType);
      }
      print('[DISCOGS] ✗ could not parse type/id from URL — aborting');
      return {};
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/${type}s/$id',
        queryParameters: {'key': consumerKey, 'secret': consumerSecret},
      );

      final data = response.data!;
      final name = data['name'] as String? ?? '';
      final profile = data['profile'] as String? ?? '';
      final urls = (data['urls'] as List? ?? []).cast<String>();

      print('[DISCOGS] API response name="$name" urls count=${urls.length}');
      print('[DISCOGS] urls from API: $urls');
      print(
        '[DISCOGS] profile preview: ${profile.substring(0, profile.length.clamp(0, 300))}',
      );

      final images = data['images'] as List? ?? [];
      String? imageUrl;
      if (images.isNotEmpty) {
        final primary = images.firstWhere(
          (img) => img['type'] == 'primary',
          orElse: () => images.first,
        );
        imageUrl =
            primary['uri'] as String? ?? primary['resource_url'] as String?;
      }

      final links = extractPlatformLinks(urls, profile);

      print('[DISCOGS] extracted links: $links');

      return {
        'name': name,
        'profile': profile,
        'discogs_id': id,
        'entity_type': type,
        'image_url': imageUrl,
        'urls': urls,
        'links': links,
      };
    } catch (e) {
      print('[DISCOGS] ✗ fetch threw exception: $e');
      _logger.severe('Discogs fetch failed for $discogsUrl: $e');
      return {};
    }
  }

  double _calculateSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.length < 2 || b.length < 2) return 0.0;

    final aBigrams = <String>{};
    for (var i = 0; i < a.length - 1; i++) {
      aBigrams.add(a.substring(i, i + 2));
    }

    var intersection = 0;
    for (var i = 0; i < b.length - 1; i++) {
      final bigram = b.substring(i, i + 2);
      if (aBigrams.contains(bigram)) intersection++;
    }

    return (2.0 * intersection) / (a.length + b.length - 2);
  }
}
