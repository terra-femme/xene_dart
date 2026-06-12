import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/publication_poller_service.dart';
import 'package:xene_backend/src/utils/audit_logger.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';

final _logger = Logger('admin.poll');

/// Constant-time string equality — prevents timing oracle attacks on secrets.
/// Always compares all characters even if a mismatch is found early.
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return result == 0;
}

/// POST /admin/poll
/// Manually triggers a full publication RSS poll run.
/// Protected by X-Admin-Secret header matching the ADMIN_SECRET env var.
/// Exempt from JWT middleware — intended for cron/CI triggers, not user sessions.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  // Global rate limit — keyed by empty string so all callers share one bucket.
  // Caps brute-force attempts on X-Admin-Secret regardless of source IP.
  final rateLimited = checkRateLimit(adminPollRateLimiter, '');
  if (rateLimited != null) return rateLimited;

  final adminSecret = Platform.environment['ADMIN_SECRET'];
  if (adminSecret == null || adminSecret.isEmpty) {
    _logger.warning('[admin/poll] ADMIN_SECRET not configured — refusing');
    return Response.json(
      statusCode: 503,
      body: {'error': 'ADMIN_SECRET not configured on server'},
    );
  }

  final provided = context.request.headers['x-admin-secret'] ?? '';
  if (!_constantTimeEquals(provided, adminSecret)) {
    _logger.warning('[admin/poll] Unauthorized poll attempt');
    return Response.json(statusCode: 401, body: {'error': 'Unauthorized'});
  }

  final force = context.request.uri.queryParameters['force'] == 'true';
  _logger.info('[admin/poll] Manual poll triggered (force=$force)');

  final db = context.read<DatabaseService>();
  unawaited(
    logSecurityEvent(
      db.client,
      action: 'admin_poll',
      ip: extractClientIp(context),
      metadata: {'force': force},
    ),
  );

  final poller = context.read<PublicationPollerService>();
  final result = await poller.pollAll(force: force);
  _logger.info('[admin/poll] Poll complete: $result');

  return Response.json(body: result);
}
