import 'dart:async';

import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/preset_template_payload.dart';
import 'package:xene_backend/src/utils/audit_logger.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/json_utils.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';

Future<Response> onRequest(RequestContext context) async {
  switch (context.request.method) {
    case HttpMethod.get:
      return _listTemplates(context);
    case HttpMethod.post:
      return _createTemplate(context);
    default:
      return Response(statusCode: 405);
  }
}

Future<Response> _listTemplates(RequestContext context) async {
  final rows = await context.read<DatabaseService>().getAllPresetTemplates();
  return Response.json(body: rows.map(toApiRow).toList());
}

Future<Response> _createTemplate(RequestContext context) async {
  // Creating a preset template writes GLOBAL content shown to every user, so it
  // requires admin — not merely a real (non-anonymous) account. Mirrors the
  // guard on the other preset-mutation routes ([slug] PATCH, sources POST/DELETE,
  // youtube POST, move POST). Reads (_listTemplates) stay public.
  final guard = await requireAdminUser(context);
  if (guard != null) return guard;

  final body = await _readJsonBody(context);
  if (body == null) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  final dataOrError = presetTemplateDataFromBody(
    body,
    requireRequiredFields: true,
  );
  if (dataOrError.error != null) {
    return Response.json(statusCode: 400, body: {'error': dataOrError.error});
  }

  final created = await context.read<DatabaseService>().createPresetTemplate(
    dataOrError.data,
  );
  if (created == null) {
    return Response.json(
      statusCode: 409,
      body: {'error': 'Failed to create preset template'},
    );
  }

  unawaited(
    logSecurityEvent(
      context.read<DatabaseService>().client,
      action: 'preset_template_create',
      userId: context.read<String>(),
      targetId: created['id']?.toString(),
      ip: extractClientIp(context),
      metadata: {'slug': created['slug'], 'name': created['name']},
    ),
  );

  return Response.json(statusCode: 201, body: toApiRow(created));
}

Future<Map<String, dynamic>?> _readJsonBody(RequestContext context) async {
  try {
    return await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}
