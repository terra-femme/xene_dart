import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/token_store.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('user.queue.sc_playlist');

/// POST /user/queue/sc_playlist
/// Creates or replaces a private SoundCloud playlist for the user's queued
/// SoundCloud tracks, returning a secret-token URL suitable for widget embed.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final db = context.read<DatabaseService>();
  final tokenStore = context.read<TokenStore>();
  final scService = context.read<SoundCloudService>();

  final startIndex = await _readStartIndex(context);
  _logger.info('[queue.sc_playlist] userId=$userId startIndex=$startIndex');

  final connection = await db.getPlatformConnection(userId, 'soundcloud');
  if (connection == null) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': 'SoundCloud not connected - connect your account first'},
    );
  }

  String? accessToken;
  final encryptedToken = connection['encrypted_token'] as String?;
  if (encryptedToken != null) {
    try {
      accessToken = tokenStore.decryptToken(encryptedToken);
    } catch (e) {
      _logger.severe('[queue.sc_playlist] Token decryption failed: $e');
    }
  }
  if (accessToken == null) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': 'No SC token stored - reconnect SoundCloud'},
    );
  }

  final scTrackIds = await _loadQueuedScTrackIds(db, userId, startIndex);
  if (scTrackIds.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.unprocessableEntity,
      body: {'error': 'No queued SoundCloud tracks to play'},
    );
  }

  Future<Response> createWithToken(String token) async {
    try {
      final playlistUrl = await scService.replaceQueuePlaybackPlaylist(
        accessToken: token,
        userId: userId,
        scTrackIds: scTrackIds,
      );
      if (playlistUrl == null) {
        return Response.json(
          statusCode: HttpStatus.badGateway,
          body: {'error': 'SC returned no queue playlist URL'},
        );
      }
      return Response.json(
        body: {'playlist_url': playlistUrl, 'track_count': scTrackIds.length},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      _logger.severe('[queue.sc_playlist] SC API error: ${e.response?.data}');
      return Response.json(
        statusCode: HttpStatus.badGateway,
        body: {'error': 'SoundCloud API error', 'detail': _scErrorDetail(e)},
      );
    }
  }

  try {
    return await createWithToken(accessToken);
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) {
      final encryptedRefresh = connection['refresh_token'] as String?;
      final refreshToken = encryptedRefresh != null
          ? tokenStore.decryptToken(encryptedRefresh)
          : null;
      if (refreshToken != null) {
        _logger.info('[queue.sc_playlist] Token expired - refreshing');
        final newData = await scService.refreshUserToken(refreshToken);
        if (newData != null) {
          final newToken = newData['access_token'] as String;
          final newRefresh = newData['refresh_token'] as String?;
          await db.savePlatformConnection({
            'id': connection['id'],
            'user_id': userId,
            'platform': 'soundcloud',
            'encrypted_token': tokenStore.encryptToken(newToken),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            if (newRefresh != null)
              'refresh_token': tokenStore.encryptToken(newRefresh),
          });
          return createWithToken(newToken);
        }
      }
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'SC token expired - reconnect SoundCloud'},
      );
    }
    return Response.json(
      statusCode: HttpStatus.badGateway,
      body: {'error': 'SoundCloud API error', 'detail': _scErrorDetail(e)},
    );
  } catch (e) {
    _logger.severe('[queue.sc_playlist] Unexpected error: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Internal error'},
    );
  }
}

Future<int?> _readStartIndex(RequestContext context) async {
  try {
    final body = await context.request.json() as Map<String, dynamic>;
    return body['start_index'] as int?;
  } catch (_) {
    return null;
  }
}

Future<List<String>> _loadQueuedScTrackIds(
  DatabaseService db,
  String userId,
  int? startIndex,
) async {
  final rows = await db.client
      .from('user_queue')
      .select('position, platform, track_id, external_url')
      .eq('user_id', userId)
      .order('position', ascending: true);

  final queueRows = (rows as List).cast<Map<String, dynamic>>();
  final scRows = queueRows
      .where((row) => row['platform'] == 'soundcloud')
      .toList();
  if (scRows.isEmpty) return const [];

  if (startIndex != null && startIndex >= 0 && startIndex < queueRows.length) {
    final startRow = queueRows[startIndex];
    if (startRow['platform'] == 'soundcloud') {
      final startPosition = startRow['position'];
      final startRowIndex = scRows.indexWhere(
        (row) => row['position'] == startPosition,
      );
      if (startRowIndex > 0) {
        return _trackRefs([
          ...scRows.skip(startRowIndex),
          ...scRows.take(startRowIndex),
        ]);
      }
    }
  }

  return _trackRefs(scRows);
}

List<String> _trackRefs(Iterable<Map<String, dynamic>> rows) => rows
    .map(
      (row) => ((row['track_id'] as String?)?.trim().isNotEmpty == true)
          ? row['track_id'] as String
          : row['external_url'] as String?,
    )
    .whereType<String>()
    .where((id) => id.isNotEmpty)
    .toList();

String? _scErrorDetail(DioException e) =>
    e.response?.data?.toString() ?? e.message;
