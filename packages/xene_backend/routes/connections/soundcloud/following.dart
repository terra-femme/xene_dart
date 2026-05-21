import 'package:dart_frog/dart_frog.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/token_store.dart';

final _logger = Logger('connections.soundcloud.following');
const _kScApiBase = 'https://api.soundcloud.com';

/// GET /connections/soundcloud/following
/// Returns the authenticated user's SC following list as candidate artists.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final userId = context.read<String>();
  final db = context.read<DatabaseService>();
  final tokenStore = context.read<TokenStore>();
  final scService = context.read<SoundCloudService>();

  final connection = await db.getPlatformConnection(userId, 'soundcloud');
  if (connection == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'SoundCloud not connected — complete OAuth first'},
    );
  }

  String? accessToken;
  final encryptedToken = connection['encrypted_token'] as String?;
  if (encryptedToken != null) {
    try {
      accessToken = tokenStore.decryptToken(encryptedToken);
    } catch (e) {
      _logger.severe('[following] Token decryption failed: $e');
    }
  }

  if (accessToken == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'No token stored — reconnect SoundCloud'},
    );
  }

  final force = context.request.uri.queryParameters['force'] == 'true';
  final cacheKey = 'sc_following:$userId';

  if (!force) {
    final cached = await db.getSystemCache(cacheKey);
    if (cached != null) {
      _logger.info(
        '[following] Cache HIT for $userId — returning ${(cached['collection'] as List).length} entries',
      );
      return Response.json(body: cached);
    }
  }

  Future<Response> fetchFollowing(String token) async {
    _logger.info(
      '[following] Attempting request with token length: ${token.length}',
    );
    _logger.info('[following] Header: Authorization: OAuth $token');

    final dio = Dio(
      BaseOptions(
        baseUrl: _kScApiBase,
        headers: {
          'Authorization': 'OAuth $token',
          'Accept': 'application/json; charset=utf-8',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    try {
      _logger.info('[following] Calling SC /me');
      final meResp = await dio.get<Map<String, dynamic>>('/me');
      final scUserId = meResp.data!['id'];

      final allFollowing = <Map<String, dynamic>>[];
      String? nextUrl =
          '$_kScApiBase/users/$scUserId/followings?limit=50&linked_partitioning=1';

      while (nextUrl != null) {
        final pageUrl = nextUrl;
        try {
          final pageResp = await dio.getUri<Map<String, dynamic>>(
            Uri.parse(pageUrl),
          );
          final data = pageResp.data!;
          final collection = (data['collection'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          allFollowing.addAll(collection);
          nextUrl = data['next_href'] as String?;
          if (allFollowing.length >= 5000) break;
        } on DioException catch (de) {
          // If we hit a 502 in the middle of pagination, wait a bit and retry once.
          if (de.response?.statusCode == 502) {
            _logger.warning('[following] 502 on page, retrying once...');
            await Future<void>.delayed(const Duration(seconds: 2));
            final pageResp = await dio.getUri<Map<String, dynamic>>(
              Uri.parse(pageUrl),
            );
            final data = pageResp.data!;
            final collection = (data['collection'] as List? ?? [])
                .cast<Map<String, dynamic>>();
            allFollowing.addAll(collection);
            nextUrl = data['next_href'] as String?;
            continue;
          }
          rethrow;
        }
      }

      final candidates = allFollowing
          .map(
            (a) => {
              'name': (a['username'] as String?) ?? 'Unknown',
              'soundcloud_username': a['permalink'] as String?,
              'soundcloud_url': a['permalink_url'] as String?,
              'avatar_url': a['avatar_url'] as String?,
              'followers_count': a['followers_count'] as int? ?? 0,
              'description': a['description'] as String?,
            },
          )
          .where((a) => a['soundcloud_username'] != null)
          .toList();

      final payload = {
        'collection': candidates,
        'total_count': candidates.length,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      };

      await db.setSystemCache(cacheKey, payload);
      _logger.info(
        '[following] Cache SET for $userId — ${candidates.length} entries stored',
      );

      return Response.json(body: payload);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        _logger.warning('[following] SC API 401: ${e.response?.data}');
        final refreshToken = connection['refresh_token'] as String?;
        if (refreshToken != null) {
          _logger.info('[following] Token expired, attempting refresh...');
          final newData = await scService.refreshUserToken(refreshToken);
          if (newData != null) {
            final newToken = newData['access_token'] as String;
            final newRefresh = newData['refresh_token'] as String?;
            final encrypted = tokenStore.encryptToken(newToken);

            // Include `id` so this is an UPDATE on the existing row, not a new INSERT.
            // Without it, Supabase generates a new UUID and the old dead token stays in the DB.
            await db.savePlatformConnection({
              'id': connection['id'],
              'user_id': userId,
              'platform': 'soundcloud',
              'encrypted_token': encrypted,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
              if (newRefresh != null) 'refresh_token': newRefresh,
            });

            _logger.info('[following] Refresh successful, retrying request');
            return fetchFollowing(newToken);
          }
        }
      }
      rethrow;
    }
  }

  try {
    return await fetchFollowing(accessToken);
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    if (status == 401) {
      return Response.json(
        statusCode: 401,
        body: {'error': 'SoundCloud token expired — please reconnect'},
      );
    }
    return Response.json(
      statusCode: 502,
      body: {'error': 'SoundCloud API error', 'detail': e.message},
    );
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Internal error: $e'},
    );
  }
}
