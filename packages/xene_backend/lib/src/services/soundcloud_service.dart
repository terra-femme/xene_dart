import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';
import '../database.dart';

final _logger = Logger('SoundCloudService');

class SoundCloudService {
  SoundCloudService(this._db);

  final DatabaseService _db;
  final _dio = Dio(BaseOptions(
    baseUrl: 'https://api.soundcloud.com',
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));

  /// Fetch or Refresh OAuth token.
  /// ELI5: Getting a "Hall Pass" to talk to SoundCloud.
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
      final response = await _dio.post<Map<String, dynamic>>(
        '/oauth2/token',
        data: {
          'grant_type': 'client_credentials',
          'client_id': clientId,
          'client_secret': clientSecret,
        },
      );

      final data = response.data!;
      final token = data['access_token'] as String;
      final expiresIn = data['expires_in'] as int;

      // Cache it
      await _db.setSystemCache(
        tokenKey,
        {'access_token': token},
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn - 60)),
      );

      return token;
    } catch (e) {
      _logger.severe('Failed to get SoundCloud token: $e');
      return null;
    }
  }

  /// Resolve a username to a User ID.
  /// ELI5: Turning a "Screen Name" into a "Social Security Number."
  Future<Map<String, dynamic>?> _resolveUserInfo(String username) async {
    final token = await _getToken();
    if (token == null) return null;

    try {
      final profileUrl = 'https://soundcloud.com/$username';
      final response = await _dio.get<Map<String, dynamic>>(
        '/resolve',
        queryParameters: {'url': profileUrl},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.data;
    } catch (e) {
      _logger.warning('Failed to resolve SoundCloud user $username: $e');
      return null;
    }
  }

  /// Fetch tracks for an artist.
  /// ELI5: Asking SoundCloud for a list of all songs by an artist.
  Future<List<FeedItem>> getTracks(String username, String? displayName) async {
    final token = await _getToken();
    if (token == null) return [];

    final userData = await _resolveUserInfo(username);
    if (userData == null) return [];

    final userId = userData['id'].toString();
    final avatarUrl = (userData['avatar_url'] as String?).toString().replaceFirst('-large.', '-t500x500.');

    try {
      final response = await _dio.get<List<dynamic>>(
        '/users/$userId/tracks',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final items = <FeedItem>[];
      for (final track in response.data!) {
        try {
          // SoundCloud date format: "2026/04/17 08:24:29 +0000"
          // Dart needs a bit of help with the "/" and spaces
          final rawDate = track['created_at'] as String;
          final normalizedDate = rawDate.replaceAll('/', '-');
          
          items.add(FeedItem(
            id: track['id'].toString(),
            platform: 'soundcloud',
            artistName: displayName ?? track['user']['username'] as String,
            contentType: 'track',
            title: track['title'] as String,
            body: track['description'] as String?,
            artworkUrl: track['artwork_url'] as String? ?? avatarUrl,
            externalUrl: track['permalink_url'] as String,
            publishedAt: DateTime.parse(normalizedDate),
            durationSeconds: (track['duration'] as int) ~/ 1000,
            playCount: track['playback_count'] as int?,
            like_count: track['likes_count'] as int?, // Note: match model fields
          ));
        } catch (e) {
          _logger.warning('Error parsing track: $e');
        }
      }

      // Save to DB
      final dbItems = items.map((i) => {
        'platform': i.platform,
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
      
      return items;
    } catch (e) {
      _logger.severe('Failed to fetch SoundCloud tracks: $e');
      return [];
    }
  }
}
