import 'package:dart_frog/dart_frog.dart';

/// GET /auth/soundcloud — DEPRECATED (410 Gone)
/// Replaced by POST /auth/soundcloud/nonce, which requires an authenticated JWT.
Future<Response> onRequest(RequestContext context) async {
  return Response.json(
    statusCode: 410,
    body: {
      'error': 'Use POST /auth/soundcloud/nonce to initiate SoundCloud OAuth',
    },
  );
}
