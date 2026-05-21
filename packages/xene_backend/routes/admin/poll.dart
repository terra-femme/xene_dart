import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/publication_poller_service.dart';

final _logger = Logger('admin.poll');

/// POST /admin/poll
/// Manually triggers a full publication RSS poll run.
/// Protected by X-Admin-Secret header matching the ADMIN_SECRET env var.
/// Exempt from JWT middleware — intended for cron/CI triggers, not user sessions.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final adminSecret = Platform.environment['ADMIN_SECRET'];
  if (adminSecret == null || adminSecret.isEmpty) {
    _logger.warning('[admin/poll] ADMIN_SECRET not configured — refusing');
    return Response.json(
      statusCode: 503,
      body: {'error': 'ADMIN_SECRET not configured on server'},
    );
  }

  final provided = context.request.headers['x-admin-secret'];
  if (provided != adminSecret) {
    _logger.warning('[admin/poll] Unauthorized poll attempt');
    return Response.json(statusCode: 401, body: {'error': 'Unauthorized'});
  }

  _logger.info('[admin/poll] Manual poll triggered');
  final poller = context.read<PublicationPollerService>();
  final result = await poller.pollAll();
  _logger.info('[admin/poll] Poll complete: $result');

  return Response.json(body: result);
}
