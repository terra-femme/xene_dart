import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/token_store.dart';
import 'package:xene_backend/src/utils/audit_logger.dart';

final _logger = Logger('connections.soundcloud.disconnect');

/// DELETE /connections/soundcloud/disconnect
/// Revokes the user's SC OAuth token upstream, then removes the stored token
/// row — fully disconnecting the user instead of just dropping our local copy.
/// Auth: JWT (userId injected via middleware)
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: 405);
  }

  final userId = context.read<String>();
  _logger.info('[disconnect] Disconnecting SC for userId=$userId');

  final db = context.read<DatabaseService>();
  final tokenStore = context.read<TokenStore>();
  final scService = context.read<SoundCloudService>();

  try {
    // 1. Best-effort upstream revocation BEFORE deleting the local row.
    //    If we deleted first and the revoke failed, the live SC token would be
    //    orphaned — still valid at SoundCloud with no record on our side to
    //    kill it. Read + decrypt + revoke first; any failure here is logged,
    //    never fatal, so the local delete still proceeds.
    var revoked = false;
    final connection = await db.getPlatformConnection(userId, 'soundcloud');
    if (connection != null) {
      final encryptedToken = connection['encrypted_token'] as String?;
      if (encryptedToken != null) {
        try {
          final accessToken = tokenStore.decryptToken(encryptedToken);
          revoked = await scService.revokeUserToken(accessToken);
        } catch (e) {
          _logger.warning(
            '[disconnect] Could not decrypt/revoke SC token '
            '(continuing with local delete): $e',
          );
        }
      } else {
        _logger.info(
          '[disconnect] No stored token to revoke for userId=$userId',
        );
      }
    } else {
      _logger.info('[disconnect] No SC connection row for userId=$userId');
    }

    // 2. Delete the local connection row.
    await db.client
        .from('platform_connections')
        .delete()
        .eq('user_id', userId)
        .eq('platform', 'soundcloud');

    await db.deleteSystemCache('sc_following:$userId');
    _logger.info('[disconnect] SC following cache cleared for userId=$userId');

    _logger.info(
      '[disconnect] SC connection removed for userId=$userId '
      '(upstream_revoked=$revoked)',
    );
    await logSecurityEvent(
      db.client,
      action: 'sc_token_revoke',
      userId: userId,
    );
    return Response.json(
      body: {'disconnected': true, 'upstream_revoked': revoked},
    );
  } catch (e) {
    _logger.severe('[disconnect] Error removing connection: $e');
    return Response.json(
      statusCode: 500,
      body: {'error': 'Failed to disconnect'},
    );
  }
}
