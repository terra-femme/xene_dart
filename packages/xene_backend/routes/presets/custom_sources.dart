import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/database.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  switch (request.method) {
    case HttpMethod.get:
      return _listCustomSources(context);
    case HttpMethod.put:
      return _replaceCustomSources(context);
    default:
      return Response(statusCode: 405);
  }
}

Future<Response> _listCustomSources(RequestContext context) async {
  final userId = context.read<String>();

  final sources = await context.read<DatabaseService>().getCustomPresetSources(
    userId,
  );
  return Response.json(body: {'sources': sources});
}

Future<Response> _replaceCustomSources(RequestContext context) async {
  final userId = context.read<String>();

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  final rawSources = body['sources'];
  if (rawSources is! List) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'sources must be a list'},
    );
  }

  final sources = rawSources.cast<Map<String, dynamic>>();
  final saved = await context
      .read<DatabaseService>()
      .replaceCustomPresetSources(userId, sources);
  if (!saved) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Failed to save custom preset sources'},
    );
  }

  return Response.json(body: {'sources': sources});
}
