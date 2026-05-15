import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/services/gemini_key_rotator.dart';

/// GET /discovery/status
/// Reports whether LLM providers are available for artist discovery.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final rotator = context.read<GeminiKeyRotator>();

  return Response.json(body: {
    'has_providers': rotator.hasKeys,
    'gemini_keys': rotator.keyCount,
    'providers': rotator.hasKeys ? ['gemini-2.5-flash'] : [],
  });
}
