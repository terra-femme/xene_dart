import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/token_store.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('user.saved.export_sc');

/// POST /user/saved/export_sc
/// Creates a public SoundCloud playlist from all saved SC tracks.
/// Requires the user to have a connected SoundCloud account.
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

  _logger.info('[saved.export_sc] userId=$userId');

  // Verify SC connection
  final connection = await db.getPlatformConnection(userId, 'soundcloud');
  if (connection == null) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': 'SoundCloud not connected — connect your account first'},
    );
  }

  String? accessToken;
  final encryptedToken = connection['encrypted_token'] as String?;
  if (encryptedToken != null) {
    try {
      accessToken = tokenStore.decryptToken(encryptedToken);
    } catch (e) {
      _logger.severe('[saved.export_sc] Token decryption failed: $e');
    }
  }
  if (accessToken == null) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': 'No SC token stored — reconnect SoundCloud'},
    );
  }

  // Fetch all non-expired saved SC items
  final rows = await db.client
      .from('saved_items')
      .select('track_id, external_url, title')
      .eq('user_id', userId)
      .eq('platform', 'soundcloud')
      .gt('expires_at', DateTime.now().toUtc().toIso8601String())
      .order('saved_at', ascending: false);

  final scTrackIds = (rows as List)
      .cast<Map<String, dynamic>>()
      .map(
        (r) => ((r['track_id'] as String?)?.trim().isNotEmpty == true)
            ? r['track_id'] as String
            : r['external_url'] as String?,
      )
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toList();

  if (scTrackIds.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.unprocessableEntity,
      body: {'error': 'No saved SoundCloud tracks to export'},
    );
  }

  _logger.info(
    '[saved.export_sc] Adding tracks to Xene playlist tracks=${scTrackIds.length}',
  );

  Future<Response> doCreate(String token) async {
    try {
      final url = await scService.addToXenePlaylist(
        accessToken: token,
        userId: userId,
        scTrackIds: scTrackIds,
      );
      if (url == null) {
        return Response.json(
          statusCode: HttpStatus.badGateway,
          body: {'error': 'SC returned no Xene playlist URL'},
        );
      }
      _logger.info('[saved.export_sc] Xene playlist updated: $url');
      return Response.json(body: {'playlist_url': url});
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      _logger.severe('[saved.export_sc] SC API error: ${e.response?.data}');
      return Response.json(
        statusCode: HttpStatus.badGateway,
        body: {'error': 'SoundCloud API error', 'detail': _scErrorDetail(e)},
      );
    }
  }

  try {
    return await doCreate(accessToken);
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) {
      final encryptedRefresh = connection['refresh_token'] as String?;
      final refreshToken = encryptedRefresh != null
          ? tokenStore.decryptToken(encryptedRefresh)
          : null;
      if (refreshToken != null) {
        _logger.info('[saved.export_sc] Token expired — refreshing');
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
          return doCreate(newToken);
        }
      }
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'SC token expired — reconnect SoundCloud'},
      );
    }
    return Response.json(
      statusCode: HttpStatus.badGateway,
      body: {'error': 'SoundCloud API error', 'detail': _scErrorDetail(e)},
    );
  } catch (e) {
    _logger.severe('[saved.export_sc] Unexpected error: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Internal error'},
    );
  }
}

String? _scErrorDetail(DioException e) =>
    e.response?.data?.toString() ?? e.message;
