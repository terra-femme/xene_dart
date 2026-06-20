import 'dart:async';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/utils/audit_logger.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';

final _logger = Logger('presets.sources.move');

/// POST /presets/templates/{slug}/sources/{sourceId}/move
///
/// Moves a source from [slug] to the preset identified by [target_slug] in
/// the request body. Returns 204 on success, 409 if the artist already exists
/// in the target preset, 404 if either preset or source is not found.
Future<Response> onRequest(
  RequestContext context,
  String slug,
  String sourceId,
) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  // Global preset source mutation — admin only.
  final guard = await requireAdminUser(context);
  if (guard != null) return guard;

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  final targetSlug = (body['target_slug'] as String?)?.trim();
  if (targetSlug == null || targetSlug.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'target_slug is required'},
    );
  }

  if (targetSlug == slug) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Source is already in this preset'},
    );
  }

  final db = context.read<DatabaseService>();
  final error = await db.movePresetTemplateSource(sourceId, targetSlug);

  if (error != null) {
    final statusCode = error.contains('already exists')
        ? 409
        : error.contains('not found')
        ? 404
        : 500;
    _logger.warning(
      '[presets.sources.move] Failed move $sourceId $slug->$targetSlug: $error',
    );
    return Response.json(statusCode: statusCode, body: {'error': error});
  }

  _logger.info(
    '[presets.sources.move] Moved source $sourceId from $slug to $targetSlug',
  );
  unawaited(
    logSecurityEvent(
      db.client,
      action: 'preset_source_move',
      userId: context.read<String>(),
      targetId: sourceId,
      ip: extractClientIp(context),
      metadata: {'from': slug, 'to': targetSlug},
    ),
  );
  return Response(statusCode: 204);
}
