import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

final _logger = Logger('TwitchService');

const _kTwitchTokenUrl = 'https://id.twitch.tv/oauth2/token';
const _kTwitchStreamsUrl = 'https://api.twitch.tv/helix/streams';
const _kCacheTtlSeconds = 120; // 2-minute live status cache

class TwitchService {
  String? _appToken;
  DateTime? _tokenExpiresAt;
  final Map<String, _LiveCacheEntry> _liveCache = {};

  final Dio _dio = Dio(
    BaseOptions(listFormat: ListFormat.multi),
  );

  String get _clientId {
    final v = Platform.environment['TWITCH_CLIENT_ID'] ?? '';
    if (v.isEmpty) throw StateError('TWITCH_CLIENT_ID not set');
    return v;
  }

  String get _clientSecret {
    final v = Platform.environment['TWITCH_CLIENT_SECRET'] ?? '';
    if (v.isEmpty) throw StateError('TWITCH_CLIENT_SECRET not set');
    return v;
  }

  bool get _tokenIsValid {
    if (_appToken == null || _tokenExpiresAt == null) return false;
    return DateTime.now().toUtc().isBefore(_tokenExpiresAt!);
  }

  Future<String> _fetchAppToken() async {
    _logger.info('[twitch] Fetching new app access token');
    final resp = await _dio.post<Map<String, dynamic>>(
      _kTwitchTokenUrl,
      queryParameters: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'grant_type': 'client_credentials',
      },
    );
    _logger.info('[twitch] Token response status=${resp.statusCode}');
    final data = resp.data!;
    _appToken = data['access_token'] as String;
    // Subtract 60s buffer before actual expiry
    final expiresIn = (data['expires_in'] as int? ?? 3600) - 60;
    _tokenExpiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));
    _logger.info('[twitch] App token acquired, expires in ${expiresIn}s');
    return _appToken!;
  }

  Future<String> _getToken() async {
    if (_tokenIsValid) return _appToken!;
    return _fetchAppToken();
  }

  String _cacheKey(List<String> logins) {
    final sorted = logins.map((l) => l.toLowerCase()).toList()..sort();
    return sorted.join(',');
  }

  bool _isCacheStale(String key) {
    final entry = _liveCache[key];
    if (entry == null) return true;
    final age = DateTime.now().toUtc().difference(entry.fetchedAt).inSeconds;
    if (age <= _kCacheTtlSeconds) {
      _logger.fine('[twitch] Cache hit for $key, age=${age}s');
      return false;
    }
    return true;
  }

  /// Check which Twitch logins are currently live.
  /// Returns a list of stream info maps. Cached for 2 minutes.
  Future<List<Map<String, dynamic>>> getLiveStatus(List<String> logins) async {
    if (logins.isEmpty) {
      _logger.fine('[twitch] getLiveStatus called with empty list');
      return [];
    }

    final key = _cacheKey(logins);
    if (!_isCacheStale(key)) {
      return _liveCache[key]!.streams;
    }

    _logger.info('[twitch] Checking live status for $logins');
    final token = await _getToken();

    final resp = await _dio.get<Map<String, dynamic>>(
      _kTwitchStreamsUrl,
      queryParameters: {'user_login': logins},
      options: Options(
        headers: {
          'Client-ID': _clientId,
          'Authorization': 'Bearer $token',
        },
      ),
    );
    _logger.info('[twitch] Streams API status=${resp.statusCode}');
    _logger.fine('[twitch] Raw response: ${resp.data.toString().substring(0, 300)}');

    final rawStreams = (resp.data!['data'] as List<dynamic>? ?? []);
    _logger.info('[twitch] Got ${rawStreams.length} live stream(s)');

    final streams = rawStreams.map((s) {
      final sMap = s as Map<String, dynamic>;
      final thumb = (sMap['thumbnail_url'] as String? ?? '')
          .replaceAll('{width}', '640')
          .replaceAll('{height}', '360');
      final login = (sMap['user_login'] as String? ?? '').toLowerCase();
      return {
        'twitch_login': login,
        'stream_title': sMap['title'] ?? '',
        'game_name': sMap['game_name'] ?? '',
        'viewer_count': sMap['viewer_count'] ?? 0,
        'started_at': sMap['started_at'],
        'thumbnail_url': thumb.isNotEmpty ? thumb : null,
        'stream_url': 'https://twitch.tv/$login',
      };
    }).toList();

    _liveCache[key] = _LiveCacheEntry(streams, DateTime.now().toUtc());
    return streams;
  }
}

class _LiveCacheEntry {
  const _LiveCacheEntry(this.streams, this.fetchedAt);
  final List<Map<String, dynamic>> streams;
  final DateTime fetchedAt;
}
