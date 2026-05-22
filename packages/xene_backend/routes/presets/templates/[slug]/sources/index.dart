import 'dart:async';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/json_utils.dart';

final _logger = Logger('presets.sources');

Future<Response> onRequest(RequestContext context, String slug) async {
  switch (context.request.method) {
    case HttpMethod.get:
      return _listSources(context, slug);
    case HttpMethod.post:
      return _addSource(context, slug);
    case HttpMethod.delete:
      return _removeSource(context, slug);
    default:
      return Response(statusCode: 405);
  }
}

Future<Response> _listSources(RequestContext context, String slug) async {
  final rows = await context
      .read<DatabaseService>()
      .getPresetTemplateSourcesForAdmin(slug);
  return Response.json(body: rows.map(_sourceToApiRow).toList());
}

Future<Response> _addSource(RequestContext context, String slug) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  final scProfileUrl =
      (body['soundcloud_url'] as String?)?.trim() ??
      (body['soundcloudUrl'] as String?)?.trim();
  if (scProfileUrl == null || scProfileUrl.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'soundcloud_url is required'},
    );
  }

  final soundcloud = context.read<SoundCloudService>();
  final profile = await soundcloud.resolveProfileUrl(scProfileUrl);
  if (profile == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Could not resolve SoundCloud profile'},
    );
  }

  final scName = profile['username'] as String?;
  final scUsername = profile['permalink'] as String?;
  final resolvedUrl = profile['permalink_url'] as String?;
  if (scName == null ||
      scName.isEmpty ||
      scUsername == null ||
      scUsername.isEmpty ||
      resolvedUrl == null ||
      resolvedUrl.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {
        'error': 'Resolved SoundCloud profile was missing identity fields',
      },
    );
  }

  final db = context.read<DatabaseService>();
  final existing = await db.getArtistBySoundCloudUsername(scUsername);
  if (existing != null && existing['manually_verified'] == true) {
    _logger.info('[presets.sources] Reusing verified artist: $scUsername');
    final saved = await db.addSoundCloudSourceToPreset(slug, {
      ...existing,
      'name': scName,
      'soundcloud_username': scUsername,
      'soundcloud_url': resolvedUrl,
    });
    if (saved == null) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Could not add source'},
      );
    }
    unawaited(
      _warmSoundCloudSource(
        db: db,
        soundcloud: soundcloud,
        artistName: scName,
        scUrl: resolvedUrl,
      ),
    );
    return Response.json(statusCode: 201, body: _sourceToApiRow(saved));
  }

  final source = {
    ...body,
    'name': scName,
    'soundcloud_url': resolvedUrl,
    'soundcloud_username': scUsername,
  };

  final saved = await db.addSoundCloudSourceToPreset(slug, source);
  if (saved == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Could not add SoundCloud source to preset'},
    );
  }

  _logger.info('[presets.sources] Source added: $scName to preset=$slug');
  unawaited(
    _warmSoundCloudSource(
      db: db,
      soundcloud: soundcloud,
      artistName: scName,
      scUrl: resolvedUrl,
    ),
  );
  return Response.json(statusCode: 201, body: _sourceToApiRow(saved));
}

Future<void> _warmSoundCloudSource({
  required DatabaseService db,
  required SoundCloudService soundcloud,
  required String artistName,
  required String scUrl,
}) async {
  try {
    _logger.info('[presets.sources] Warming SoundCloud feed for $artistName');
    await db.deleteSystemCache('feed_empty_window:soundcloud:$artistName:31d');
    final items = await soundcloud.getTracks(
      scUrl,
      artistName,
      bypassMemoryCache: true,
    );
    await db.setLastPolled('soundcloud', artistName);
    _logger.info(
      '[presets.sources] SoundCloud warmup done for $artistName (${items.length} items)',
    );
  } catch (e) {
    _logger.warning(
      '[presets.sources] SoundCloud warmup failed for $artistName: $e',
    );
  }
}

Future<Response> _removeSource(RequestContext context, String slug) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final sourceId = context.request.uri.queryParameters['source_id']?.trim();
  if (sourceId == null || sourceId.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'source_id query parameter is required'},
    );
  }

  final db = context.read<DatabaseService>();
  final source = await db.getPresetTemplateSource(sourceId);
  final removed = await db.removePresetTemplateSource(slug, sourceId);
  if (!removed) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Preset source not found'},
    );
  }
  await _clearSourceFeedCache(db, source);
  return Response(statusCode: 204);
}

Future<void> _clearSourceFeedCache(
  DatabaseService db,
  Map<String, dynamic>? source,
) async {
  if (source == null) return;
  final artistName = (source['display_name'] ?? source['soundcloud_username'])
      ?.toString();
  if (artistName == null || artistName.isEmpty) return;

  await db.deleteFeedItemsForArtist(artistName);
  await db.deleteSystemCache('last_polled:soundcloud:$artistName');
  await db.deleteSystemCache('feed_empty_window:soundcloud:$artistName:31d');
  _logger.info(
    '[presets.sources] Cleared feed cache for removed source $artistName',
  );
}

Map<String, dynamic> _sourceToApiRow(Map<String, dynamic> row) {
  final artist = row['artist'];
  final source = toApiRow(row)..remove('artist');
  return {
    ...source,
    if (artist is Map<String, dynamic>) 'artist': toApiRow(artist),
  };
}
