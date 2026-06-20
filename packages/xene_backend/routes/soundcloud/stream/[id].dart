import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final rateLimited = checkRateLimit(streamRateLimiter, userId);
  if (rateLimited != null) return rateLimited;

  // SoundCloud track IDs are numeric. Reject anything else before it is
  // interpolated into the upstream `/tracks/$id/streams` path — blocks path /
  // parameter injection against the SC API using the app's client credentials.
  if (int.tryParse(id) == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Invalid track id'},
    );
  }

  final scService = context.read<SoundCloudService>();
  final streamUrl = await scService.getStreamUrl(id);

  if (streamUrl == null) {
    return Response.json(
      body: {'error': 'Could not resolve stream URL'},
      statusCode: HttpStatus.notFound,
    );
  }

  return Response.json(body: {'stream_url': streamUrl});
}
