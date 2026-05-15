import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
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
