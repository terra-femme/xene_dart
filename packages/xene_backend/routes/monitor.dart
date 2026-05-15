import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/services/gemini_key_rotator.dart';

/// GET /monitor
/// Returns live in-memory LLM usage stats split into on-boarding and upkeep
/// buckets. Resets on server restart — intended for dev tooling only.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }
  final rotator = context.read<GeminiKeyRotator>();
  return Response.json(body: rotator.stats);
}
