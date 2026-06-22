import 'dart:async';
import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/publication_poller_service.dart';
import 'package:xene_backend/src/utils/audit_logger.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';

final _logger = Logger('press_scout/poll_publications');

/// POST /press-scout/poll-publications
/// Manually triggers a full RSS publication poll run.
/// Useful when combined with press-scout/run for a HITL workflow.
/// Admin-only to prevent abuse.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();

  // Publication polling can trigger external HTTP calls — admin only.
  final db = context.read<DatabaseService>();
  final profileRes = await db.client
      .from('profiles')
      .select('role')
      .eq('id', userId)
      .maybeSingle();
  final role = profileRes?['role'] as String? ?? 'user';
  if (role != 'admin') {
    _logger.warning('[poll_publications] Non-admin attempt userId=$userId');
    return Response.json(
      statusCode: 403,
      body: {'error': 'Admin access required'},
    );
  }

  final rateLimited = checkRateLimit(
    pressScoutRateLimiter,
    extractClientIp(context),
  );
  if (rateLimited != null) return rateLimited;

  final presetSlug = context.request.uri.queryParameters['preset_id']?.trim();

  unawaited(
    logSecurityEvent(
      db.client,
      action: 'poll_publications',
      userId: userId,
      ip: extractClientIp(context),
      metadata: {if (presetSlug != null) 'preset_slug': presetSlug},
    ),
  );

  final poller = context.read<PublicationPollerService>();

  _logger.info(
    '[poll_publications] Manual poll triggered${presetSlug != null ? ' for preset "$presetSlug"' : ''}',
  );

  // Fire and forget — polling can take a few minutes.
  unawaited(
    poller
        .pollAll(force: true)
        .then((result) {
          _logger.info('[poll_publications] Poll completed: $result');
        })
        .catchError((Object e) {
          _logger.severe('[poll_publications] Poll failed: $e');
        }),
  );

  return Response.json(
    body: {
      'status': 'started',
      if (presetSlug != null) 'preset': presetSlug,
      'message':
          'Publication polling running in background — check server logs for progress',
    },
  );
}
