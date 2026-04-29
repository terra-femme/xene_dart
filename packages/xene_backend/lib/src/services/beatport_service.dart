import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';
import '../database.dart';

final _logger = Logger('BeatportService');

class BeatportService {
  BeatportService(this._db) {
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  final DatabaseService _db;
  final _cookieJar = CookieJar();
  final _dio = Dio(BaseOptions(
    baseUrl: 'https://api.beatport.com/v4',
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));

  static const _clientId = '0GIvkCltVIuPkkwSJHp6NDb3s0potTjLBQr388Dd';
  static const _redirectUri = 'https://api.beatport.com/v4/auth/o/post-message/';

  /// ELI5: The "Sneaky Login" sequence. 
  /// 1. Tell them who we are (Login).
  /// 2. Ask for a "Secret Code" (Authorize).
  /// 3. Trade the code for a "Golden Key" (Token).
  Future<String?> _authenticateSession() async {
    final username = Platform.environment['BEATPORT_USERNAME'];
    final password = Platform.environment['BEATPORT_PASSWORD'];

    if (username == null || password == null) {
      _logger.warning('Beatport credentials missing.');
      return null;
    }

    try {
      // Step 1: Login to establish session
      final loginResp = await _dio.post(
        '/auth/login/',
        data: {'username': username, 'password': password},
      );

      if (loginResp.statusCode != 200 && loginResp.statusCode != 201) {
        _logger.severe('Beatport login failed: ${loginResp.statusCode}');
        return null;
      }

      // Step 2: Request auth code (cookies are handled by CookieManager)
      final authResp = await _dio.get(
        '/auth/o/authorize/',
        queryParameters: {
          'response_type': 'code',
          'client_id': _clientId,
          'redirect_uri': _redirectUri,
        },
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status! < 500,
        ),
      );

      final location = authResp.headers.value('location');
      if (location == null) return null;

      final uri = Uri.parse(location);
      final authCode = uri.queryParameters['code'];
      if (authCode == null) return null;

      // Step 3: Exchange code for token
      final tokenResp = await _dio.post(
        '/auth/o/token/',
        queryParameters: {
          'grant_type': 'authorization_code',
          'code': authCode,
          'redirect_uri': _redirectUri,
          'client_id': _clientId,
        },
      );

      return tokenResp.data['access_token'] as String?;
    } catch (e) {
      _logger.severe('Beatport auth flow failed: $e');
      return null;
    }
  }

  Future<String?> _getToken() async {
    const tokenKey = 'beatport_user_token';
    final cached = await _db.getSystemCache(tokenKey);
    if (cached != null && cached['access_token'] != null) {
      return cached['access_token'] as String;
    }

    final token = await _authenticateSession();
    if (token != null) {
      await _db.setSystemCache(
        tokenKey,
        {'access_token': token},
        expiresAt: DateTime.now().add(const Duration(hours: 10)),
      );
    }
    return token;
  }

  /// Fetch releases for a label.
  /// ELI5: Checking the "New Arrivals" shelf for a specific record label.
  Future<List<FeedItem>> getLabelReleases(String labelId, {String? labelName, int limit = 20}) async {
    final token = await _getToken();
    if (token == null) return [];

    try {
      final response = await _dio.get(
        '/catalog/releases/',
        queryParameters: {
          'label_id': labelId,
          'per_page': limit,
          'order_by': '-publish_date',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final results = response.data['results'] as List;
      final items = <FeedItem>[];

      for (final r in results) {
        try {
          final id = r['id'].toString();
          final title = r['name'] as String;
          final artists = (r['artists'] as List).map((a) => a['name'] as String).join(', ');
          
          final image = r['image'] as Map? ?? {};
          final imgUrl = (image['uri'] as String? ?? image['dynamic_uri'] as String? ?? '')
              .replaceFirst('{w}', '500')
              .replaceFirst('{h}', '500');

          items.add(FeedItem(
            id: 'bp_$id',
            platform: 'beatport',
            artistName: labelName ?? (r['label'] as Map)['name'] as String,
            contentType: 'release',
            title: title,
            body: artists,
            externalUrl: 'https://www.beatport.com/release/${r['slug']}/$id',
            artworkUrl: imgUrl.isEmpty ? null : imgUrl,
            publishedAt: DateTime.parse(r['publish_date'] as String),
          ));
        } catch (e) {
          _logger.warning('Error parsing Beatport release: $e');
        }
      }

      if (items.isNotEmpty) {
        final dbItems = items.map((i) => {
          'platform': 'beatport',
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
      _logger.severe('Beatport fetch failed for label $labelId: $e');
      return [];
    }
  }
}
