import 'package:dart_frog/dart_frog.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/token_store.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('game.export_sc');

/// POST /game/parties/:partyId/export_sc
/// Creates a public SoundCloud playlist with all tracks from this week's party.
/// Body (optional): { "week": "YYYY-MM-DD" }
/// Requires the requesting user to have a connected SoundCloud account.
Future<Response> onRequest(RequestContext context, String partyId) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final db = context.read<DatabaseService>();
  final tokenStore = context.read<TokenStore>();
  final scService = context.read<SoundCloudService>();
  final game = context.read<GameService>();

  String weekStart;
  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final w = (body['week'] as String?)?.trim() ?? '';
    weekStart = w.isNotEmpty ? w : GameService.currentWeekStart();
  } catch (_) {
    weekStart = GameService.currentWeekStart();
  }

  final connection = await db.getPlatformConnection(userId, 'soundcloud');
  if (connection == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'SoundCloud not connected — connect your account first'},
    );
  }

  String? accessToken;
  final encryptedToken = connection['encrypted_token'] as String?;
  if (encryptedToken != null) {
    try {
      accessToken = tokenStore.decryptToken(encryptedToken);
    } catch (e) {
      _logger.severe('[export_sc] Token decryption failed: $e');
    }
  }
  if (accessToken == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'No SC token stored — reconnect SoundCloud'},
    );
  }

  final memberData = await game.getWeeklyTracks(partyId, weekStart, userId);
  if (memberData.isEmpty) {
    return Response.json(
      statusCode: 403,
      body: {'error': 'Not a member of this party'},
    );
  }

  final scTrackIds = memberData
      .expand((m) => (m['tracks'] as List<dynamic>? ?? []))
      .cast<Map<String, dynamic>>()
      .map((t) => t['sc_track_id'] as String)
      .toList();

  if (scTrackIds.isEmpty) {
    return Response.json(
      statusCode: 422,
      body: {'error': 'No tracks submitted for this week yet'},
    );
  }

  _logger.info(
    '[export_sc] Adding tracks to Xene playlist partyId=$partyId week=$weekStart '
    'tracks=${scTrackIds.length}',
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
          statusCode: 502,
          body: {'error': 'SC returned no Xene playlist URL'},
        );
      }
      _logger.info('[export_sc] Xene playlist updated: $url');
      return Response.json(body: {'playlist_url': url});
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      _logger.severe('[export_sc] SC API error: ${e.response?.data}');
      return Response.json(
        statusCode: 502,
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
        _logger.info('[export_sc] Token expired — attempting refresh');
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
        statusCode: 401,
        body: {'error': 'SC token expired — reconnect SoundCloud'},
      );
    }
    return Response.json(
      statusCode: 502,
      body: {'error': 'SoundCloud API error', 'detail': _scErrorDetail(e)},
    );
  } catch (e) {
    _logger.severe('[export_sc] Unexpected error: $e');
    return Response.json(statusCode: 500, body: {'error': 'Internal error'});
  }
}

String? _scErrorDetail(DioException e) =>
    e.response?.data?.toString() ?? e.message;
