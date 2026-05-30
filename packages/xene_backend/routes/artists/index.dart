import 'dart:async';

import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/services/press_scout_service.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/utils/json_utils.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  switch (request.method) {
    case HttpMethod.get:
      return _listArtists(context);
    case HttpMethod.post:
      return _createArtist(context);
    default:
      return Response(statusCode: 405);
  }
}

Future<Response> _listArtists(RequestContext context) async {
  final userId = context.read<String>();

  final db = context.read<DatabaseService>();
  final rows = await db.getArtists(userId);

  final result = rows.map((row) {
    final camel = toApiRow(row);
    // Normalize edges: old rows may have {} (Map) stored instead of [] (List).
    if (camel['edges'] is! List) camel['edges'] = <dynamic>[];
    final et = camel['entityType'] as String?;
    return {...camel, 'isLabel': et == 'label' || et == 'organization'};
  }).toList();

  return Response.json(body: result);
}

Future<Response> _createArtist(RequestContext context) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();

  final db = context.read<DatabaseService>();
  final pressScout = context.read<PressScoutService>();
  final soundcloud = context.read<SoundCloudService>();

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  final scUrl = body['soundcloud_url'] as String?;
  if (scUrl != null && scUrl.isNotEmpty) {
    final profile = await soundcloud.resolveProfileUrl(scUrl);
    if (profile == null) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Could not resolve SoundCloud profile'},
      );
    }
    body['name'] = profile['username'];
    body['soundcloud_username'] = profile['permalink'];
    body['soundcloud_url'] = profile['permalink_url'];
  }

  final data = {...body, 'user_id': userId, 'last_press_scout_at': null};

  final created = await db.createArtist(data);
  if (created == null) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Failed to create artist'},
    );
  }

  unawaited(
    db.logArtistAction(
      userId: userId,
      artistId: created['id'].toString(),
      action: 'create',
    ),
  );
  // Fire-and-forget press scout for the new artist
  unawaited(_scoutNewArtist(pressScout, db, created));

  return Response.json(statusCode: 201, body: created);
}

Future<void> _scoutNewArtist(
  PressScoutService pressScout,
  DatabaseService db,
  Map<String, dynamic> artist,
) async {
  final artistId = artist['id'] as String?;
  final name = artist['name'] as String? ?? 'unknown';
  final entityType = (artist['entity_type'] as String?) ?? 'artist';

  if (artistId == null) return;

  try {
    final articles = await pressScout.scoutOnDemand(artistId, name, entityType);
    if (articles.isNotEmpty) {
      final dbArticles = articles.map((art) {
        final rawDate = art['published_date'] ?? art['Date'];
        final pubDate = rawDate?.toString().trim().toLowerCase();
        final pubDateVal =
            (pubDate != null &&
                pubDate != 'n/a' &&
                pubDate != 'unknown' &&
                pubDate.isNotEmpty)
            ? rawDate.toString()
            : null;
        return {
          'artist_id': artistId,
          'title': art['title'] ?? art['Title'] ?? 'Untitled',
          'url': art['url'] ?? art['URL'] ?? '#',
          if ((art['snippet'] ?? art['Snippet'])
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true)
            'snippet': (art['snippet'] ?? art['Snippet']).toString().trim(),
          'source': art['source'] ?? art['Source'] ?? art['site_tier'],
          'published_at': pubDateVal,
        };
      }).toList();

      if (await db.saveArtistArticles(dbArticles)) {
        await db.updateLastPressScout(artistId);
      }
    }
  } catch (e) {
    // Fire-and-forget — log but don't surface to caller
    print('[artists] Press scout failed for new artist $name: $e');
  }
}
