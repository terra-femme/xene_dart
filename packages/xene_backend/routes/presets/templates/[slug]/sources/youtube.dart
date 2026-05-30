import 'dart:async';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/youtube_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/json_utils.dart';

final _logger = Logger('presets.sources.youtube');

/// POST /presets/templates/{slug}/sources/youtube
/// Dev-only: add a YouTube-only source (no SoundCloud required).
Future<Response> onRequest(RequestContext context, String slug) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  final displayName = (body['display_name'] as String?)?.trim();
  final youtubeUrl = (body['youtube_url'] as String?)?.trim();

  if (displayName == null || displayName.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'display_name is required'},
    );
  }
  if (youtubeUrl == null || youtubeUrl.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'youtube_url is required'},
    );
  }

  final db = context.read<DatabaseService>();
  final saved = await db.addYouTubeSourceToPreset(
    slug,
    displayName,
    youtubeUrl,
  );
  if (saved == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Could not add YouTube source to preset'},
    );
  }

  _logger.info(
    '[presets.sources.youtube] Added "$displayName" to preset=$slug',
  );
  unawaited(
    _warmYouTubeSource(
      db: db,
      youtube: context.read<YouTubeService>(),
      displayName: displayName,
      youtubeUrl: youtubeUrl,
    ),
  );

  return Response.json(statusCode: 201, body: _sourceToApiRow(saved));
}

Future<void> _warmYouTubeSource({
  required DatabaseService db,
  required YouTubeService youtube,
  required String displayName,
  required String youtubeUrl,
}) async {
  try {
    _logger.info(
      '[presets.sources.youtube] Warming YouTube feed for $displayName',
    );
    await db.deleteSystemCache('feed_empty_window:youtube:$displayName:31d');
    await youtube.getVideos(youtubeUrl, displayName);
    _logger.info('[presets.sources.youtube] Warmup done for $displayName');
  } catch (e) {
    _logger.warning(
      '[presets.sources.youtube] Warmup failed for $displayName: $e',
    );
  }
}

Map<String, dynamic> _sourceToApiRow(Map<String, dynamic> row) {
  final artist = row['artist'];
  final source = toApiRow(row)..remove('artist');
  return {
    ...source,
    if (artist is Map<String, dynamic>) 'artist': toApiRow(artist),
  };
}
