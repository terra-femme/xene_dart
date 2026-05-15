import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/feed_cache.dart';
import 'package:xene_backend/src/services/discovery_service.dart';
import 'package:xene_backend/src/services/bandcamp_service.dart';
import 'package:xene_backend/src/services/press_scout_service.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/youtube_service.dart';
import 'package:xene_backend/src/utils/json_utils.dart';

final _logger = Logger('discovery.save_discovery');

/// POST /discovery/save-discovery
/// Saves a confirmed artist discovery result to the artists table.
/// Header: X-User-Id (defaults to local_user)
/// Body: fully mapped and scored artist JSON from GET /discovery/auto-discover
Future<Response> onRequest(RequestContext context) async {
  print('DEBUG: [save_discovery] POST request received');
  _logger.info('[save_discovery] Ping! Request reached route.');
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final userId = context.request.headers['x-user-id'] ?? 'local_user';
  _logger.info('[save_discovery] userId=$userId');

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  final db = context.read<DatabaseService>();
  final pressScout = context.read<PressScoutService>();
  final discovery = context.read<DiscoveryService>();
  final soundcloud = context.read<SoundCloudService>();
  final youtube = context.read<YouTubeService>();
  final bandcamp = context.read<BandcampService>();
  final engine = IdentityEngine();

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

  final name = body['name'] as String? ?? '';
  if (name.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': '"name" is required in the discovery result'},
    );
  }

  _logger.info(
    '[save_discovery] ▶ body received — keys: ${body.keys.toList()}',
  );
  _logger.info(
    '[save_discovery] body name="${body['name']}" soundcloud_url=${body['soundcloud_url']} soundcloud_username=${body['soundcloud_username']}',
  );
  _logger.info(
    '[save_discovery] body identity_confidence=${body['identity_confidence']} coverage_level=${body['coverage_level']}',
  );

  // body is already mapped by DiscoveryService.autoDiscover — just re-score it.
  // Do NOT call mapAiResultToArtistFields again: that function expects raw nested
  // LLM JSON (soundcloudRss.url, youtube.id, etc.) and would strip all flat
  // platform fields (soundcloud_url, youtube_channel_id, etc.) that were set by
  // the discovery pipeline before the result was returned to the client.
  final scoring = engine.calculateNodeConfidence(body);
  _logger.info(
    '[save_discovery] scoring: confidence=${scoring['confidence']} identity_confidence=${scoring['identity_confidence']} coverage_level=${scoring['coverage_level']}',
  );

  final now = DateTime.now().toUtc().toIso8601String();
  final row = <String, dynamic>{
    ...body,
    'created_at': now,
    'manually_verified': false,
    'confidence': scoring['confidence'],
    'identity_confidence': scoring['identity_confidence'],
    'coverage_level': scoring['coverage_level'],
    'conflict_state': false,
    'edges': (body['edges'] is List) ? body['edges'] : <Map<String, dynamic>>[],
  };
  // user_id belongs in user_artist_follows, not in the global artists table.
  row.remove('user_id');

  // Strip any keys not in the artists table schema.
  // This prevents PGRST204 if unknown fields (e.g. facebook_authority, discogs_authority)
  // slip through from the discovery pipeline.
  // Exact column list from the artists table in Supabase.
  // Any key not in this set gets stripped before upsert to prevent PGRST204.
  // Source of truth: SELECT table_name, column_name FROM information_schema.columns
  const _kArtistColumns = {
    'id', 'name', 'entity_type', 'manually_verified',
    'created_at', 'last_discovered_at', 'last_press_scout_at',
    // SoundCloud
    'soundcloud_username', 'soundcloud_url', 'soundcloud_authority',
    // YouTube
    'youtube_channel_id', 'youtube_url', 'youtube_authority',
    // Spotify
    'spotify_id', 'spotify_url', 'spotify_authority',
    // Beatport
    'beatport_artist_id',
    'beatport_artist_name',
    'beatport_url',
    'beatport_authority',
    // Bandcamp
    'bandcamp_url', 'bandcamp_authority',
    // Instagram
    'instagram_username', 'instagram_url', 'instagram_authority',
    // Twitter/X
    'twitter_username', 'twitter_url', 'twitter_authority',
    // Twitch
    'twitch_login', 'twitch_url', 'twitch_authority',
    // Streaming-only identifiers
    'apple_music_id', 'deezer_id', 'tidal_id',
    // General
    'website_url', 'analysis', 'edges',
    // Scoring
    'confidence', 'identity_confidence', 'coverage_level', 'conflict_state',
  };

  final unknownKeys = row.keys
      .where((k) => !_kArtistColumns.contains(k))
      .toList();
  if (unknownKeys.isNotEmpty) {
    _logger.warning(
      '[save_discovery] ⚠ stripping ${unknownKeys.length} unknown column(s): $unknownKeys',
    );
    for (final k in unknownKeys) {
      row.remove(k);
    }
  }

  _logger.info('[save_discovery] row to upsert — keys: ${row.keys.toList()}');
  _logger.info(
    '[save_discovery] row name=${row['name']} soundcloud_username=${row['soundcloud_username']}',
  );
  _logger.info('[save_discovery] Saving artist: $name userId=$userId');

  try {
    _logger.info(
      '[save_discovery] → calling Supabase upsert onConflict=soundcloud_username',
    );
    final upserted = await db.client
        .from('artists')
        .upsert(row, onConflict: 'soundcloud_username')
        .select()
        .single();

    // Create or refresh the follow relationship for this user.
    await db.client.from('user_artist_follows').upsert({
      'user_id': userId,
      'artist_id': upserted['id'],
    });
    _logger.info(
      '[save_discovery] ✓ follow upserted user=$userId artist=${upserted['id']}',
    );

    _logger.info(
      '[save_discovery] ✓ Supabase upsert OK — id=${upserted['id']} name=${upserted['name']}',
    );

    unawaited(
      _warmSavedArtistFeed(
        db: db,
        soundcloud: soundcloud,
        youtube: youtube,
        bandcamp: bandcamp,
        artist: upserted,
      ),
    );

    // Keep the save path deterministic-first. LLM/search enrichment only runs
    // when the saved row still looks incomplete, or when explicitly enabled.
    if (_shouldRunBackgroundLlmEnrichment(upserted)) {
      unawaited(_enrichWithLlm(discovery, db, upserted));
    } else {
      _logger.info(
        '[save_discovery] Skipping LLM enrichment for ${upserted['name']} - deterministic discovery is already strong',
      );
    }

    if (_pressScoutOnSaveEnabled()) {
      unawaited(_scoutSavedArtist(pressScout, db, upserted));
    } else {
      _logger.info(
        '[save_discovery] Press scout on-save disabled; scheduled scout will handle ${upserted['name']}',
      );
    }

    return Response.json(statusCode: 201, body: toApiRow(upserted));
  } catch (e) {
    print('CRITICAL: [save_discovery] DATABASE ERROR: $e');
    _logger.severe('[save_discovery] Upsert failed for $name: $e');
    return Response.json(
      statusCode: 500,
      body: {'error': 'Failed to save artist: $e', 'details': e.toString()},
    );
  }
}

bool _pressScoutOnSaveEnabled() {
  final value =
      Platform.environment['XENE_PRESS_SCOUT_ON_SAVE'] ??
      Platform.environment['PRESS_SCOUT_ON_SAVE'];
  return value == '1' || value?.toLowerCase() == 'true';
}

Future<void> _warmSavedArtistFeed({
  required DatabaseService db,
  required SoundCloudService soundcloud,
  required YouTubeService youtube,
  required BandcampService bandcamp,
  required Map<String, dynamic> artist,
}) async {
  final name = artist['name'] as String? ?? 'Unknown';
  final scUsername = artist['soundcloud_username'] as String?;
  final scUrl = artist['soundcloud_url'] as String?;
  final ytChannelId = artist['youtube_channel_id'] as String?;
  final ytUrl = artist['youtube_url'] as String?;
  final bcUrl = artist['bandcamp_url'] as String?;

  final tasks = <Future<List<FeedItem>>>[];

  final scIdentifier = (scUrl != null && scUrl.isNotEmpty) ? scUrl : scUsername;
  if (scIdentifier != null && scIdentifier.isNotEmpty) {
    tasks.add(
      fetchWithCache(
        db,
        'soundcloud',
        name,
        Duration.zero,
        () => soundcloud.getTracks(scIdentifier, name),
      ),
    );
  }

  if (bcUrl != null && bcUrl.isNotEmpty) {
    tasks.add(
      fetchWithCache(
        db,
        'bandcamp',
        name,
        Duration.zero,
        () => bandcamp.getFeed(bcUrl, name),
        cacheDays: 31,
      ),
    );
  }

  final ytId = (ytChannelId != null && ytChannelId.startsWith('UC'))
      ? ytChannelId
      : (ytUrl ?? ytChannelId);
  if (ytId != null && ytId.isNotEmpty) {
    tasks.add(
      fetchWithCache(
        db,
        'youtube',
        name,
        Duration.zero,
        () => youtube.getVideos(ytId, name),
      ),
    );
  }

  if (tasks.isEmpty) {
    _logger.info(
      '[save_discovery] Feed warmup skipped for $name - no platform links',
    );
    return;
  }

  try {
    _logger.info(
      '[save_discovery] Feed warmup started for $name (${tasks.length} task(s))',
    );
    final results = await Future.wait(tasks, eagerError: false);
    final itemCount = results.fold<int>(0, (sum, items) => sum + items.length);
    _logger.info(
      '[save_discovery] Feed warmup finished for $name: $itemCount items',
    );
  } catch (e) {
    _logger.warning('[save_discovery] Feed warmup failed for $name: $e');
  }
}

bool _shouldRunBackgroundLlmEnrichment(Map<String, dynamic> artist) {
  final force =
      Platform.environment['XENE_LLM_ENRICH_ON_SAVE'] ??
      Platform.environment['LLM_ENRICH_ON_SAVE'];
  if (force == '1' || force?.toLowerCase() == 'true') return true;

  final confidence = artist['identity_confidence'] as String?;
  final coverage = artist['coverage_level'] as String?;
  final analysis = artist['analysis'] as String?;
  final hasUsefulAnalysis = analysis != null && analysis.trim().isNotEmpty;

  final hasCoreLink =
      artist['youtube_url'] != null ||
      artist['bandcamp_url'] != null ||
      artist['spotify_url'] != null ||
      artist['website_url'] != null;
  final hasBandcamp = artist['bandcamp_url'] != null;
  final bandcampIsHighAuthority = artist['bandcamp_authority'] == 'HIGH';
  final strongAuthorities = [
    artist['soundcloud_authority'],
    artist['youtube_authority'],
    artist['bandcamp_authority'],
    artist['spotify_authority'],
    artist['website_authority'],
  ].where((value) => value == 'HIGH').length;

  final deterministicStrong =
      confidence == 'HIGH' &&
      coverage == 'COMPLETE' &&
      hasCoreLink &&
      hasBandcamp &&
      bandcampIsHighAuthority &&
      strongAuthorities >= 2;
  if (deterministicStrong) return false;

  return !hasUsefulAnalysis ||
      confidence != 'HIGH' ||
      coverage != 'COMPLETE' ||
      !hasBandcamp ||
      !hasCoreLink;
}

Future<void> _enrichWithLlm(
  DiscoveryService discovery,
  DatabaseService db,
  Map<String, dynamic> savedArtist,
) async {
  final name = savedArtist['name'] as String? ?? '';
  final scUsername = savedArtist['soundcloud_username'] as String?;
  final scUrl = savedArtist['soundcloud_url'] as String?;
  final artistId = savedArtist['id'] as String?;
  if (name.isEmpty || scUsername == null || artistId == null) return;

  print('[save_discovery] → LLM background enrichment fired for $name');
  _logger.info(
    '[save_discovery] LLM enrichment started for $name (id=$artistId)',
  );

  try {
    final enriched = await discovery.autoDiscover(
      name,
      scProfileUrl: scUrl,
      scUsername: scUsername,
      // skipLlm defaults to false — full pipeline including LLM
    );
    if (enriched.isEmpty) {
      _logger.warning(
        '[save_discovery] LLM enrichment returned empty for $name',
      );
      return;
    }

    // Only patch fields that come exclusively from LLM (type, streaming IDs,
    // analysis). Never overwrite HIGH-authority SC/Discogs fields already saved.
    final patch = <String, dynamic>{};
    for (final key in [
      'entity_type',
      'spotify_id',
      'spotify_url',
      'apple_music_id',
      'deezer_id',
      'tidal_id',
      'analysis',
    ]) {
      if (key == 'entity_type') {
        final entityType = _normalizeEntityType(enriched[key]);
        if (entityType != null && entityType != savedArtist[key]) {
          patch[key] = entityType;
        }
      } else if (enriched[key] != null && savedArtist[key] == null) {
        patch[key] = enriched[key];
      }
    }
    // Always update scoring — LLM improves confidence metrics
    for (final key in ['confidence', 'identity_confidence', 'coverage_level']) {
      if (enriched[key] != null) patch[key] = enriched[key];
    }

    if (patch.isEmpty) {
      _logger.info(
        '[save_discovery] LLM enrichment: no new fields to patch for $name',
      );
      return;
    }

    await db.client.from('artists').update(patch).eq('id', artistId);
    _logger.info(
      '[save_discovery] ✓ LLM enrichment patched ${patch.keys.toList()} for $name',
    );
  } catch (e) {
    _logger.warning('[save_discovery] LLM enrichment failed for $name: $e');
  }
}

String? _normalizeEntityType(Object? value) {
  final entityType = value?.toString().trim().toLowerCase();
  if (entityType == null || entityType.isEmpty || entityType == 'null') {
    return null;
  }
  const validEntityTypes = {
    'artist',
    'band',
    'label',
    'organization',
    'venue',
    'brand',
    'other',
  };
  if (validEntityTypes.contains(entityType)) return entityType;
  return 'other';
}

Future<void> _scoutSavedArtist(
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
          'snippet': art['snippet'] ?? art['Snippet'] ?? 'No snippet available',
          'source': art['source'] ?? art['Source'] ?? art['site_tier'],
          'published_at': pubDateVal,
        };
      }).toList();

      if (await db.saveArtistArticles(dbArticles)) {
        await db.updateLastPressScout(artistId);
      }
    }
  } catch (e) {
    _logger.warning('[save_discovery] Press scout failed for $name: $e');
  }
}
