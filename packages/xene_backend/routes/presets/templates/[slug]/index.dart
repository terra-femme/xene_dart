import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/preset_template_payload.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/json_utils.dart';

Future<Response> onRequest(RequestContext context, String slug) async {
  switch (context.request.method) {
    case HttpMethod.patch:
      return _patchTemplate(context, slug);
    default:
      return Response(statusCode: 405);
  }
}

Future<Response> _patchTemplate(RequestContext context, String slug) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  final dataOrError = presetTemplateDataFromBody(
    body,
    requireRequiredFields: false,
  );
  if (dataOrError.error != null) {
    return Response.json(statusCode: 400, body: {'error': dataOrError.error});
  }

  final updated = await context.read<DatabaseService>().updatePresetTemplate(
    slug,
    dataOrError.data,
  );
  if (updated == null) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Preset template not found or update failed'},
    );
  }

  return Response.json(body: toApiRow(updated));
}
