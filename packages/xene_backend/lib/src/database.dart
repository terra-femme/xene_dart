import 'dart:io';
import 'dart:math';
import 'package:supabase/supabase.dart';
import 'package:logging/logging.dart';

final _logger = Logger('Database');

const _optionalFeedItemColumns = {
  'is_repost',
  'reposted_by_name',
  'reposted_at',
  'feed_source_path',
};

class DatabaseService {
  SupabaseClient? _client;

  SupabaseClient get client {
    if (_client == null) {
      final url = Platform.environment['SUPABASE_URL'];
      final key = Platform.environment['SUPABASE_SERVICE_KEY'];

      if (url == null || key == null) {
        throw StateError('SUPABASE_URL and SUPABASE_SERVICE_KEY must be set.');
      }

      _client = SupabaseClient(url, key);
    }
    return _client!;
  }

  Future<List<Map<String, dynamic>>> getCachedFeedItems({
    required String platform,
    String? artistName,
    int limit = 500,
    int days = 31,
  }) async {
    try {
      final now = DateTime.now().toLocal();
      final cutoff = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: days)).toUtc().toIso8601String();

      var query = client
          .from('feed_items')
          .select()
          .eq('platform', platform)
          .gte('published_at', cutoff);

      if (artistName != null) {
        query = query.eq('artist_name', artistName);
      }

      final response = await query
          .order('published_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.severe('Error fetching cached feed items for $platform: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchFeedItems(
    String query, {
    int limit = 50,
    Set<String>? artistNames,
  }) async {
    try {
      // Strip PostgREST .or() delimiter chars before interpolating into the
      // filter string. Commas split conditions; parens close the or() group;
      // dots separate operator from value. Artist names like "LaMeduza, Alibi"
      // would otherwise produce malformed conditions and return garbage results.
      final safe = query
          .toLowerCase()
          .replaceAll(',', ' ')
          .replaceAll('(', ' ')
          .replaceAll(')', ' ')
          .trim();
      final q = '%$safe%';
      _logger.info(
        '[db] searchFeedItems query="$query" safe="$safe" limit=$limit '
        'artistNames=${artistNames?.length ?? 'all'}',
      );
      var request = client
          .from('feed_items')
          .select()
          .or('title.ilike.$q,body.ilike.$q,artist_name.ilike.$q');

      if (artistNames != null) {
        request = request.inFilter('artist_name', artistNames.toList());
      }

      final response = await request
          .order('published_at', ascending: false)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(response);
      _logger.info('[db] searchFeedItems returned ${rows.length} rows');
      return rows;
    } catch (e) {
      _logger.severe('[db] searchFeedItems error: $e');
      return [];
    }
  }

  Future<void> saveFeedItems(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    final seen = <String>{};
    final deduped = items.where((item) {
      final key = '${item['platform']}:${item['internal_id']}';
      return seen.add(key);
    }).toList();
    if (deduped.length < items.length) {
      _logger.warning(
        '[db] saveFeedItems: dropped ${items.length - deduped.length} duplicate(s) before upsert',
      );
    }

    try {
      // Dedup within the batch — Postgres 21000 if the same conflict key
      // appears twice in one upsert (e.g. SC reposts returning duplicate internal_id).
      await client
          .from('feed_items')
          .upsert(deduped, onConflict: 'platform,internal_id');
    } catch (e) {
      // Log but do NOT rethrow — a persistence failure must not abort the live
      // fetch. The caller still receives the fetched items, last_polled is still
      // stamped, and the 6h cache window prevents an infinite retry hammer loop.
      // The save will be retried on the next TTL expiry.
      if (await _trySaveWithoutOptionalFeedColumns(deduped)) return;
      _logger.severe('Error saving feed items (non-fatal): $e');
    }
  }

  Future<bool> _trySaveWithoutOptionalFeedColumns(
    List<Map<String, dynamic>> items,
  ) async {
    if (!items.any((item) => _optionalFeedItemColumns.any(item.containsKey))) {
      return false;
    }
    try {
      final compatible = items
          .map(
            (item) => Map<String, dynamic>.from(item)
              ..removeWhere(
                (key, value) => _optionalFeedItemColumns.contains(key),
              ),
          )
          .toList();
      await client
          .from('feed_items')
          .upsert(compatible, onConflict: 'platform,internal_id');
      _logger.warning(
        'Saved feed items without repost metadata. Add optional feed_items columns to persist repost attribution: $_optionalFeedItemColumns',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- YouTube Cache Helpers ---

  /// Retrieve cached channel_id from database for a YouTube URL.
  Future<String?> getYouTubeChannelId(String ytUrl) async {
    try {
      final response = await client
          .from('youtube_channel_cache')
          .select('channel_id')
          .eq('yt_url', ytUrl)
          .maybeSingle();

      return response?['channel_id'] as String?;
    } catch (e) {
      _logger.fine('Could not query youtube_channel_cache: $e');
      return null;
    }
  }

  /// Store channel_id mapping in database.
  Future<void> saveYouTubeChannelId(String ytUrl, String channelId) async {
    try {
      await client.from('youtube_channel_cache').upsert({
        'yt_url': ytUrl,
        'channel_id': channelId,
      });
    } catch (e) {
      _logger.severe('Error saving channel_id for $ytUrl: $e');
    }
  }

  // --- Artist Helpers ---

  /// Retrieve all artists followed by a user.
  Future<List<Map<String, dynamic>>> getArtists(String userId) async {
    try {
      final followRows = await client
          .from('user_artist_follows')
          .select('artist_id')
          .eq('user_id', userId);
      final ids = List<Map<String, dynamic>>.from(
        followRows,
      ).map((r) => r['artist_id'] as String).toList();
      if (ids.isEmpty) return [];
      final response = await client
          .from('artists')
          .select()
          .inFilter('id', ids)
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.severe('Error fetching artists for $userId: $e');
      return [];
    }
  }

  /// Retrieve enabled public preset templates in dial order.
  Future<List<Map<String, dynamic>>> getPresetTemplates() async {
    try {
      final response = await client
          .from('preset_templates')
          .select()
          .eq('is_public', true)
          .eq('enabled', true)
          .order('notch_index');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.severe('Error fetching preset templates: $e');
      return [];
    }
  }

  /// Retrieve all public preset templates for the admin playground.
  Future<List<Map<String, dynamic>>> getAllPresetTemplates() async {
    try {
      final response = await client
          .from('preset_templates')
          .select()
          .eq('is_public', true)
          .order('notch_index');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.severe('Error fetching all preset templates: $e');
      return [];
    }
  }

  /// Insert a new public preset template.
  Future<Map<String, dynamic>?> createPresetTemplate(
    Map<String, dynamic> data,
  ) async {
    try {
      if (data['is_default'] == true) {
        await client
            .from('preset_templates')
            .update({'is_default': false})
            .eq('is_public', true);
      }
      final response = await client
          .from('preset_templates')
          .insert(data)
          .select()
          .single();
      _logger.info('[db] createPresetTemplate: created ${response['slug']}');
      return response;
    } catch (e) {
      _logger.severe('Error creating preset template: $e');
      return null;
    }
  }

  /// Partial-update a public preset template by slug.
  Future<Map<String, dynamic>?> updatePresetTemplate(
    String slug,
    Map<String, dynamic> data,
  ) async {
    try {
      if (data['is_default'] == true) {
        await client
            .from('preset_templates')
            .update({'is_default': false})
            .eq('is_public', true)
            .neq('slug', slug);
      }
      final response = await client
          .from('preset_templates')
          .update(data)
          .eq('slug', slug)
          .eq('is_public', true)
          .select()
          .maybeSingle();
      _logger.info(
        '[db] updatePresetTemplate: updated $slug fields=${data.keys.toList()}',
      );
      return response;
    } catch (e) {
      _logger.severe('Error updating preset template $slug: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPresetTemplateBySlug(String slug) async {
    try {
      final response = await client
          .from('preset_templates')
          .select()
          .eq('slug', slug)
          .eq('is_public', true)
          .maybeSingle();
      return response;
    } catch (e) {
      _logger.severe('Error fetching preset template $slug: $e');
      return null;
    }
  }

  /// Resolve publication pipes for a preset using deterministic matching only.
  ///
  /// Matching order:
  /// 1. Direct curated preset_publications rows.
  /// 2. Artist genre_tags overlap with press_publications.genres.
  /// 3. Preset slug tokens overlap with press_publications.genres.
  ///
  /// LLM fallback intentionally lives outside this method so it cannot be used
  /// accidentally in the normal feed path.
  Future<List<Map<String, dynamic>>> getPublicationMatchesForPreset(
    String userId,
    String presetSlug, {
    int limit = 8,
  }) async {
    final slug = presetSlug.trim().isEmpty ? 'custom' : presetSlug.trim();

    final curated = await _getCuratedPresetPublications(slug, limit: limit);
    if (curated.isNotEmpty) return curated;

    final artists = await getArtistsForPreset(userId, slug);
    final artistGenreKeys = <String>{};
    for (final artist in artists) {
      final tags = artist['genre_tags'] as List?;
      if (tags == null) continue;
      for (final tag in tags) {
        artistGenreKeys.addAll(_tagKeys(tag.toString()));
      }
    }

    if (artistGenreKeys.isNotEmpty) {
      final byArtistTags = await _scorePublicationsByTags(
        artistGenreKeys,
        matchMethod: 'tag_overlap',
        contextSlug: slug,
        limit: limit,
      );
      if (byArtistTags.isNotEmpty) return byArtistTags;
    }

    final presetKeys = _tagKeys(slug.replaceAll('-', ' '));
    return _scorePublicationsByTags(
      presetKeys,
      matchMethod: 'preset_genre',
      contextSlug: slug,
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> _getCuratedPresetPublications(
    String presetSlug, {
    required int limit,
  }) async {
    try {
      final response = await client
          .from('preset_publications')
          .select('priority, reason, press_publications(*)')
          .eq('preset_slug', presetSlug)
          .order('priority')
          .limit(limit);

      final rows = List<Map<String, dynamic>>.from(response);
      final matches = <Map<String, dynamic>>[];
      for (final row in rows) {
        final publication = row['press_publications'];
        if (publication is! Map) continue;
        final pub = Map<String, dynamic>.from(publication);
        if (pub['enabled'] == false) continue;
        matches.add({
          ...pub,
          'match_method': 'preset_curated',
          'context_slug': presetSlug,
          'confidence': 1.0,
          'reason': row['reason'],
          'priority': row['priority'],
        });
      }
      return matches;
    } catch (e) {
      _logger.warning(
        '[db] getCuratedPresetPublications failed for $presetSlug: $e',
      );
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _scorePublicationsByTags(
    Set<String> targetKeys, {
    required String matchMethod,
    required String contextSlug,
    required int limit,
  }) async {
    if (targetKeys.isEmpty) return [];
    try {
      final response = await client
          .from('press_publications')
          .select()
          .eq('enabled', true);
      final publications = List<Map<String, dynamic>>.from(response);

      final scored = <Map<String, dynamic>>[];
      for (final pub in publications) {
        final rawGenres = pub['genres'] as List? ?? const [];
        final pubKeys = <String>{};
        for (final genre in rawGenres) {
          pubKeys.addAll(_tagKeys(genre.toString()));
        }
        final overlap = targetKeys.intersection(pubKeys);
        if (overlap.isEmpty) continue;

        final confidence = overlap.length / pubKeys.length.clamp(1, 99);
        scored.add({
          ...pub,
          'match_method': matchMethod,
          'context_slug': contextSlug,
          'confidence': confidence.clamp(0.0, 1.0),
          'reason': 'Matched tags: ${overlap.toList()..sort()}',
        });
      }

      scored.sort((a, b) {
        final byConfidence = (b['confidence'] as num).compareTo(
          a['confidence'] as num,
        );
        if (byConfidence != 0) return byConfidence;
        final byTier = (a['tier'] as num? ?? 2).compareTo(
          b['tier'] as num? ?? 2,
        );
        if (byTier != 0) return byTier;
        return (a['name'] as String? ?? '').compareTo(
          b['name'] as String? ?? '',
        );
      });

      return scored.take(limit).toList();
    } catch (e) {
      _logger.warning('[db] scorePublicationsByTags failed: $e');
      return [];
    }
  }

  Set<String> _tagKeys(String value) {
    final normalised = _searchKey(value);
    if (normalised.isEmpty) return {};

    final keys = <String>{normalised};

    // Drum & Bass — "drum & bass" → "drumbass", "drum and bass" → "drumandbass",
    // "DnB", "d&b" → "db", neurofunk, darkstep, techstep, drumstep all resolve to 'dnb'.
    if ((normalised.contains('drum') && normalised.contains('bass')) ||
        normalised.contains('dnb') ||
        normalised == 'db' ||
        normalised == 'neurofunk' ||
        normalised == 'darkstep' ||
        normalised == 'techstep' ||
        normalised == 'drumstep') {
      keys.add('dnb');
      keys.add('drumandbass');
    }

    // Liquid DnB — subset of DnB; maps to both 'liquid' and 'dnb' buckets
    if (normalised.contains('liquid')) {
      keys.add('liquid');
      keys.add('dnb');
      keys.add('drumandbass');
    }

    // Jungle — ancestral to DnB, covered by overlapping publications
    if (normalised.contains('jungle') || normalised == 'raggajungle') {
      keys.add('jungle');
      keys.add('dnb');
    }

    // House — covers "house", "deephouse", "techhouse", "housemusic", etc.
    if (normalised.contains('house')) {
      keys.add('house');
      keys.add('electronic');
    }

    // Techno
    if (normalised.contains('techno')) {
      keys.add('techno');
      keys.add('electronic');
    }

    // Electronic (broad) — covers "electronic", "electronica", "edm"
    if (normalised.contains('electronic') ||
        normalised == 'edm' ||
        normalised == 'electronica') {
      keys.add('electronic');
    }

    // Ambient — covers "ambient", "darkambient", "drone"
    if (normalised.contains('ambient') ||
        normalised == 'drone' ||
        normalised == 'darkambient') {
      keys.add('ambient');
      keys.add('electronic');
    }

    // Experimental / noise / avant-garde
    if (normalised.contains('experimental') ||
        normalised == 'noise' ||
        normalised == 'avantgarde' ||
        normalised == 'abstract') {
      keys.add('experimental');
    }

    // Hip Hop — "hip hop" → "hiphop", "hip-hop" → "hiphop", "rap", "trap"
    if (normalised.contains('hiphop') ||
        normalised == 'rap' ||
        normalised == 'trap') {
      keys.add('hiphop');
    }

    // R&B / Soul — "r&b" strips to "rb"; "rnb", "r and b" → "randb".
    // Both 'rb' and 'rnb' are added so publication "r&b" and artist "rnb" match.
    if (normalised == 'rb' ||
        normalised == 'rnb' ||
        normalised.contains('randb') ||
        normalised.contains('soul') ||
        normalised == 'neosoul' ||
        normalised == 'rhythmandblues') {
      keys.add('rb');
      keys.add('rnb');
    }

    // Grime — also maps to hip hop publications
    if (normalised.contains('grime')) {
      keys.add('grime');
      keys.add('hiphop');
    }

    // UK Garage / 2-step
    if (normalised.contains('garage') ||
        normalised.contains('ukg') ||
        normalised == '2step') {
      keys.add('ukg');
      keys.add('garage');
      keys.add('electronic');
    }

    // Trance
    if (normalised.contains('trance')) {
      keys.add('trance');
      keys.add('electronic');
    }

    // Dubstep / bass music
    if (normalised.contains('dubstep') || normalised == 'brostep') {
      keys.add('dubstep');
      keys.add('bass');
      keys.add('electronic');
    }
    if (normalised == 'bass' ||
        normalised == 'bassmusic' ||
        normalised == 'ukbass') {
      keys.add('bass');
      keys.add('electronic');
    }

    // Jazz
    if (normalised.contains('jazz')) {
      keys.add('jazz');
    }

    // Folk
    if (normalised.contains('folk') || normalised == 'singersongwriter') {
      keys.add('folk');
    }

    // Indie
    if (normalised.contains('indie')) {
      keys.add('indie');
    }

    // Alternative
    if (normalised.contains('alternative') || normalised == 'altrock') {
      keys.add('alternative');
    }

    // Pop — explicit list to avoid false-matching 'hiphop' (contains 'pop')
    if (normalised == 'pop' ||
        normalised == 'synthpop' ||
        normalised == 'dreampop' ||
        normalised == 'electropop' ||
        normalised == 'indiepop' ||
        normalised == 'bubblegum') {
      keys.add('pop');
    }

    // Dance / club music
    if (normalised == 'dance' ||
        normalised == 'dancemusic' ||
        normalised == 'clubmusic' ||
        normalised == 'clubbing') {
      keys.add('dance');
      keys.add('electronic');
    }

    // Rock — "rock", "indie rock" → "indierock", "hard rock" → "hardrock", "alt-rock"
    if (normalised.contains('rock') && !normalised.contains('electronic')) {
      keys.add('rock');
    }

    // Punk — "punk", "punk rock" → "punkrock", "post-punk" → "postpunk"
    if (normalised.contains('punk')) {
      keys.add('punk');
      keys.add('rock');
      keys.add('alternative');
    }

    return keys;
  }

  String _searchKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  Future<List<Map<String, dynamic>>> getPresetTemplateSourcesForAdmin(
    String slug,
  ) async {
    try {
      final template = await getPresetTemplateBySlug(slug);
      final templateId = template?['id'] as String?;
      if (templateId == null) return [];

      final response = await client
          .from('preset_template_sources')
          .select()
          .eq('template_id', templateId)
          .order('created_at');
      final rows = List<Map<String, dynamic>>.from(response);
      final artistIds = rows
          .map((row) => row['artist_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final artistsById = <String, Map<String, dynamic>>{};
      if (artistIds.isNotEmpty) {
        final artistRows = await client
            .from('artists')
            .select()
            .inFilter('id', artistIds);
        for (final artist in List<Map<String, dynamic>>.from(artistRows)) {
          artistsById[artist['id'] as String] = artist;
        }
      }

      return rows.map((row) {
        final artistId = row['artist_id'] as String?;
        final artist = artistId == null ? null : artistsById[artistId];
        return {
          'id': row['id'],
          'template_id': row['template_id'],
          'artist_id': artistId,
          'enabled': row['enabled'],
          'platform': row['platform'],
          'display_name': row['display_name'],
          'soundcloud_username': row['soundcloud_username'],
          'soundcloud_url': row['soundcloud_url'],
          'bandcamp_url': row['bandcamp_url'],
          'youtube_channel_id': row['youtube_channel_id'],
          'youtube_url': row['youtube_url'],
          'artist': artist,
        };
      }).toList();
    } catch (e) {
      _logger.severe('Error fetching preset template sources for $slug: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> addSoundCloudSourceToPreset(
    String slug,
    Map<String, dynamic> source,
  ) async {
    try {
      final template = await getPresetTemplateBySlug(slug);
      final templateId = template?['id'] as String?;
      if (templateId == null) return null;

      final name = (source['name'] ?? source['displayName'] ?? 'Unknown')
          .toString();
      final username =
          (source['soundcloud_username'] ?? source['soundcloudUsername'])
              ?.toString();
      final url = (source['soundcloud_url'] ?? source['soundcloudUrl'])
          ?.toString();
      if (username == null || username.isEmpty) return null;

      final artistRow = _curatedArtistRowFromSource(
        source: source,
        name: name.isEmpty ? username : name,
        username: username,
        url: url,
      );

      final artist = await client
          .from('artists')
          .upsert(artistRow, onConflict: 'soundcloud_username')
          .select()
          .single();
      final artistId = artist['id'] as String;

      final existing = await client
          .from('preset_template_sources')
          .select()
          .eq('template_id', templateId)
          .eq('artist_id', artistId)
          .maybeSingle();

      if (existing != null) {
        final updated = await client
            .from('preset_template_sources')
            .update({
              'enabled': true,
              'display_name': artist['name'],
              'soundcloud_username': username,
              'soundcloud_url': url,
            })
            .eq('id', existing['id'])
            .select()
            .single();
        return {'source': updated, 'artist': artist};
      }

      final inserted = await client
          .from('preset_template_sources')
          .insert({
            'template_id': templateId,
            'artist_id': artistId,
            'platform': 'soundcloud',
            'display_name': artist['name'],
            'soundcloud_username': username,
            'soundcloud_url': url,
            'enabled': true,
            'metadata': <String, dynamic>{},
          })
          .select()
          .single();
      return {'source': inserted, 'artist': artist};
    } catch (e) {
      _logger.severe('Error adding SoundCloud source to preset $slug: $e');
      return null;
    }
  }

  Map<String, dynamic> _curatedArtistRowFromSource({
    required Map<String, dynamic> source,
    required String name,
    required String username,
    required String? url,
  }) {
    const allowed = {
      'name',
      'entity_type',
      'soundcloud_username',
      'soundcloud_url',
      'soundcloud_authority',
      'youtube_channel_id',
      'youtube_url',
      'youtube_authority',
      'spotify_id',
      'spotify_url',
      'spotify_authority',
      'beatport_artist_id',
      'beatport_artist_name',
      'beatport_url',
      'beatport_authority',
      'bandcamp_url',
      'bandcamp_authority',
      'instagram_username',
      'instagram_url',
      'instagram_authority',
      'twitter_username',
      'twitter_url',
      'twitter_authority',
      'twitch_login',
      'twitch_url',
      'twitch_authority',
      'apple_music_id',
      'deezer_id',
      'tidal_id',
      'website_url',
      'analysis',
      'edges',
      'confidence',
      'identity_confidence',
      'coverage_level',
      'conflict_state',
      'last_discovered_at',
    };

    final row = <String, dynamic>{
      for (final entry in source.entries)
        if (allowed.contains(entry.key) && entry.value != null)
          entry.key: entry.value,
      'name': name,
      'entity_type': source['entity_type'] ?? 'artist',
      'manually_verified': true,
      'soundcloud_username': username,
      'soundcloud_url': url,
      'soundcloud_authority': source['soundcloud_authority'] ?? 'HIGH',
      'confidence': source['confidence'] ?? 1.0,
      'identity_confidence': source['identity_confidence'] ?? 'HIGH',
      'coverage_level': source['coverage_level'] ?? 'COMPLETE',
      'conflict_state': source['conflict_state'] ?? false,
      'edges': source['edges'] is List ? source['edges'] : <dynamic>[],
    };
    return row;
  }

  Future<bool> removePresetTemplateSource(String slug, String sourceId) async {
    try {
      final template = await getPresetTemplateBySlug(slug);
      final templateId = template?['id'] as String?;
      if (templateId == null) return false;
      await client
          .from('preset_template_sources')
          .delete()
          .eq('id', sourceId)
          .eq('template_id', templateId);
      return true;
    } catch (e) {
      _logger.severe('Error removing preset source $sourceId from $slug: $e');
      return false;
    }
  }

  /// Retrieve the user's last active preset slug, if one has been saved.
  Future<String?> getUserPresetSelection(String userId) async {
    try {
      final response = await client
          .from('user_preset_selection')
          .select('active_preset_slug')
          .eq('user_id', userId)
          .maybeSingle();
      return response?['active_preset_slug'] as String?;
    } catch (e) {
      _logger.severe('Error fetching preset selection for $userId: $e');
      return null;
    }
  }

  /// Persist the active preset slug for a user.
  Future<bool> saveUserPresetSelection(String userId, String slug) async {
    try {
      await client.from('user_preset_selection').upsert({
        'user_id': userId,
        'active_preset_slug': slug,
      });
      _logger.info('[db] saveUserPresetSelection: $userId -> $slug');
      return true;
    } catch (e) {
      _logger.severe('Error saving preset selection for $userId: $e');
      return false;
    }
  }

  /// Resolve a preset slug into artist-like source rows consumed by feed.merged.
  Future<List<Map<String, dynamic>>> getArtistsForPreset(
    String userId,
    String presetSlug,
  ) async {
    if (presetSlug == 'custom') {
      final customSources = await getCustomPresetSources(userId);
      if (customSources.isNotEmpty) return customSources;

      _logger.info(
        '[db] custom preset has no sources for $userId; falling back to followed artists',
      );
      return getArtists(userId);
    }

    try {
      final template = await client
          .from('preset_templates')
          .select('id')
          .eq('slug', presetSlug)
          .eq('enabled', true)
          .eq('is_public', true)
          .maybeSingle();
      final templateId = template?['id'] as String?;
      if (templateId == null) return [];

      final response = await client
          .from('preset_template_sources')
          .select()
          .eq('template_id', templateId)
          .eq('enabled', true);
      final rows = List<Map<String, dynamic>>.from(response)..shuffle(Random());
      return _resolvePresetSourceRows(rows);
    } catch (e) {
      _logger.severe('Error fetching preset sources for $presetSlug: $e');
      return [];
    }
  }

  /// Retrieve per-user custom notch sources as artist-like rows.
  Future<List<Map<String, dynamic>>> getCustomPresetSources(
    String userId,
  ) async {
    try {
      final response = await client
          .from('user_custom_preset_sources')
          .select()
          .eq('user_id', userId)
          .eq('enabled', true);
      final rows = List<Map<String, dynamic>>.from(response)..shuffle(Random());
      return _resolvePresetSourceRows(rows);
    } catch (e) {
      _logger.severe('Error fetching custom preset sources for $userId: $e');
      return [];
    }
  }

  /// Replace a user's custom notch sources in one operation.
  Future<bool> replaceCustomPresetSources(
    String userId,
    List<Map<String, dynamic>> sources,
  ) async {
    try {
      await client
          .from('user_custom_preset_sources')
          .delete()
          .eq('user_id', userId);

      if (sources.isEmpty) return true;

      final now = DateTime.now().toUtc().toIso8601String();
      final rows = <Map<String, dynamic>>[];
      for (final source in sources) {
        rows.add({
          'user_id': userId,
          'artist_id': source['artist_id'] ?? source['artistId'],
          'platform': source['platform'] ?? 'soundcloud',
          'display_name': source['display_name'] ?? source['displayName'],
          'soundcloud_username':
              source['soundcloud_username'] ?? source['soundcloudUsername'],
          'soundcloud_url': source['soundcloud_url'] ?? source['soundcloudUrl'],
          'bandcamp_url': source['bandcamp_url'] ?? source['bandcampUrl'],
          'youtube_channel_id':
              source['youtube_channel_id'] ?? source['youtubeChannelId'],
          'youtube_url': source['youtube_url'] ?? source['youtubeUrl'],
          'enabled': source['enabled'] != false,
          'metadata': source['metadata'] ?? <String, dynamic>{},
          'created_at': now,
        });
      }

      await client.from('user_custom_preset_sources').insert(rows);
      _logger.info(
        '[db] replaceCustomPresetSources: ${rows.length} sources for $userId',
      );
      return true;
    } catch (e) {
      _logger.severe('Error replacing custom preset sources for $userId: $e');
      return false;
    }
  }

  List<Map<String, dynamic>> _presetSourcesToArtistRows(
    List<Map<String, dynamic>> rows,
  ) {
    return rows.map((row) {
      return <String, dynamic>{
        'id': row['id'],
        'name': row['display_name'] ?? 'Unknown',
        'entity_type': 'artist',
        'soundcloud_username': row['soundcloud_username'],
        'soundcloud_url': row['soundcloud_url'],
        'bandcamp_url': row['bandcamp_url'],
        'youtube_channel_id': row['youtube_channel_id'],
        'youtube_url': row['youtube_url'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _resolvePresetSourceRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final artistIds = rows
        .map((row) => row['artist_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    final resolved = <Map<String, dynamic>>[];
    final artistRowsById = <String, Map<String, dynamic>>{};
    if (artistIds.isNotEmpty) {
      try {
        final artistRows = await client
            .from('artists')
            .select()
            .inFilter('id', artistIds);
        for (final artistRow in List<Map<String, dynamic>>.from(artistRows)) {
          final id = artistRow['id'] as String?;
          if (id != null) artistRowsById[id] = artistRow;
        }
      } catch (e) {
        _logger.severe('Error resolving preset artist ids: $e');
      }
    }

    for (final row in rows) {
      final artistId = row['artist_id'] as String?;
      if (artistId == null) continue;

      final artistRow = artistRowsById[artistId];
      if (artistRow == null) continue;
      resolved.add(_mergePresetSourceWithArtist(row, artistRow));
    }

    final fallbackRows = rows.where((row) => row['artist_id'] == null).toList();
    resolved.addAll(_presetSourcesToArtistRows(fallbackRows));
    resolved.shuffle(Random());
    return resolved;
  }

  Map<String, dynamic> _mergePresetSourceWithArtist(
    Map<String, dynamic> source,
    Map<String, dynamic> artist,
  ) {
    final merged = Map<String, dynamic>.from(artist);

    void overrideIfPresent(String key) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        merged[key] = value.trim();
      } else if (value != null && value is! String) {
        merged[key] = value;
      }
    }

    final displayName = source['display_name'];
    if (displayName is String && displayName.trim().isNotEmpty) {
      merged['name'] = displayName.trim();
    }

    overrideIfPresent('soundcloud_username');
    overrideIfPresent('soundcloud_url');
    overrideIfPresent('bandcamp_url');
    overrideIfPresent('youtube_channel_id');
    overrideIfPresent('youtube_url');

    return merged;
  }

  /// Retrieve a specific artist by ID.
  Future<Map<String, dynamic>?> getArtistById(String id) async {
    try {
      final response = await client
          .from('artists')
          .select()
          .eq('id', id)
          .maybeSingle();
      return response;
    } catch (e) {
      _logger.severe('Error fetching artist $id: $e');
      return null;
    }
  }

  /// Insert a new global artist and create a follow relationship for the user.
  Future<Map<String, dynamic>?> createArtist(Map<String, dynamic> data) async {
    try {
      final userId = data['user_id'] as String?;
      final artistData = Map<String, dynamic>.from(data)..remove('user_id');
      if (userId != null) artistData['created_by'] = userId;
      final response = await client
          .from('artists')
          .insert(artistData)
          .select()
          .single();
      _logger.info('[db] createArtist: created ${response['name']}');
      if (userId != null) {
        await client.from('user_artist_follows').upsert({
          'user_id': userId,
          'artist_id': response['id'],
        });
        _logger.info(
          '[db] createArtist: follow created user=$userId artist=${response['id']}',
        );
      }
      return response;
    } catch (e) {
      _logger.severe('Error creating artist: $e');
      return null;
    }
  }

  /// Partial-update a global artist row — verifies the user follows it first.
  Future<Map<String, dynamic>?> updateArtist(
    String id,
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      final follow = await client
          .from('user_artist_follows')
          .select()
          .eq('user_id', userId)
          .eq('artist_id', id)
          .maybeSingle();
      if (follow == null) {
        _logger.warning(
          '[db] updateArtist: user $userId does not follow artist $id — rejected',
        );
        return null;
      }
      final response = await client
          .from('artists')
          .update(data)
          .eq('id', id)
          .select()
          .maybeSingle();
      _logger.info(
        '[db] updateArtist: updated $id fields=${data.keys.toList()}',
      );
      return response;
    } catch (e) {
      _logger.severe('Error updating artist $id: $e');
      return null;
    }
  }

  /// Update an artist row without checking follow relationship (admin / preset playground use only).
  Future<Map<String, dynamic>?> updateArtistAdmin(
    String id,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await client
          .from('artists')
          .update(data)
          .eq('id', id)
          .select()
          .maybeSingle();
      _logger.info('[db] updateArtistAdmin: $id fields=${data.keys.toList()}');
      return response;
    } catch (e) {
      _logger.severe('Error in updateArtistAdmin for $id: $e');
      return null;
    }
  }

  /// Find a global artist by SoundCloud username.
  Future<Map<String, dynamic>?> getArtistBySoundCloudUsername(
    String username,
  ) async {
    try {
      return await client
          .from('artists')
          .select()
          .eq('soundcloud_username', username)
          .maybeSingle();
    } catch (e) {
      _logger.severe('Error fetching artist by SC username $username: $e');
      return null;
    }
  }

  /// Merge new genre tags into an artist's genre_tags array (additive, deduped).
  /// Matches by soundcloudUsername or bandcampUrl — whichever is provided.
  /// Non-fatal: a failure here must never abort a feed fetch.
  Future<void> updateArtistGenreTags(
    List<String> tags, {
    String? soundcloudUsername,
    String? bandcampUrl,
  }) async {
    if (tags.isEmpty) return;
    try {
      Map<String, dynamic>? row;
      if (soundcloudUsername != null) {
        row = await getArtistBySoundCloudUsername(soundcloudUsername);
      } else if (bandcampUrl != null) {
        final normalised = bandcampUrl.trim().replaceAll(RegExp(r'/$'), '');
        row = await client
            .from('artists')
            .select()
            .ilike('bandcamp_url', normalised)
            .maybeSingle();
      }
      if (row == null) {
        _logger.fine(
          '[db] updateArtistGenreTags: no artist found '
          '(sc=$soundcloudUsername bc=$bandcampUrl) — skipping',
        );
        return;
      }
      final existingRaw = row['genre_tags'] as List?;
      final existing = existingRaw?.cast<String>() ?? <String>[];
      final cleaned = tags
          .map((t) => t.trim().toLowerCase())
          .where((t) => t.isNotEmpty)
          .toSet();
      final merged = {...existing, ...cleaned}.toList()..sort();
      await client
          .from('artists')
          .update({'genre_tags': merged})
          .eq('id', row['id'] as String);
      _logger.info(
        '[db] updateArtistGenreTags: artist=${row['name']} '
        '→ ${merged.length} tags: $merged',
      );
    } catch (e) {
      _logger.warning('[db] updateArtistGenreTags failed (non-fatal): $e');
    }
  }

  /// Partial-update a preset_template_sources row directly.
  /// Used when the source has no linked artist_id.
  Future<Map<String, dynamic>?> updatePresetTemplateSource(
    String sourceId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await client
          .from('preset_template_sources')
          .update(data)
          .eq('id', sourceId)
          .select()
          .maybeSingle();
      _logger.info(
        '[db] updatePresetTemplateSource: $sourceId fields=${data.keys.toList()}',
      );
      return response;
    } catch (e) {
      _logger.severe('[db] updatePresetTemplateSource error for $sourceId: $e');
      return null;
    }
  }

  /// Fetch a single preset_template_sources row by ID.
  Future<Map<String, dynamic>?> getPresetTemplateSource(String sourceId) async {
    try {
      return await client
          .from('preset_template_sources')
          .select()
          .eq('id', sourceId)
          .maybeSingle();
    } catch (e) {
      _logger.severe('Error fetching preset source $sourceId: $e');
      return null;
    }
  }

  /// Unfollow an artist — removes the follow row; artist identity persists globally.
  Future<bool> deleteArtist(String id, String userId) async {
    try {
      await client
          .from('user_artist_follows')
          .delete()
          .eq('user_id', userId)
          .eq('artist_id', id);
      _logger.info('[db] deleteArtist: unfollowed $id for user $userId');
      return true;
    } catch (e) {
      _logger.severe('Error unfollowing artist $id: $e');
      return false;
    }
  }

  /// Record a create/update/delete action on an artist for audit purposes.
  /// Non-fatal — a failure here must never abort the caller.
  Future<void> logArtistAction({
    required String userId,
    required String artistId,
    required String action,
    Map<String, dynamic>? changedFields,
  }) async {
    try {
      await client.from('artist_audit_log').insert({
        'user_id': userId,
        'artist_id': artistId,
        'action': action,
        if (changedFields != null && changedFields.isNotEmpty)
          'changed_fields': changedFields,
      });
    } catch (e) {
      _logger.warning('[db] logArtistAction failed (non-fatal): $e');
    }
  }

  /// Retrieve all artists across all users (used by background press scout job).
  Future<List<Map<String, dynamic>>> getAllArtistsForScouting() async {
    try {
      final response = await client
          .from('artists')
          .select('id, name, entity_type, last_press_scout_at');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.severe('Error fetching all artists for scouting: $e');
      return [];
    }
  }

  // --- Artist Articles ---

  /// Save a list of articles (upsert on artist_id + url conflict).
  Future<bool> saveArtistArticles(List<Map<String, dynamic>> articles) async {
    if (articles.isEmpty) return false;
    try {
      await client
          .from('artist_articles')
          .upsert(articles, onConflict: 'artist_id,url');
      _logger.info(
        '[db] saveArtistArticles: upserted ${articles.length} articles',
      );
      return true;
    } catch (e) {
      _logger.severe('Error saving artist articles: $e');
      return false;
    }
  }

  /// Retrieve articles for a specific artist, newest first.
  Future<List<Map<String, dynamic>>> getArtistArticles(
    String artistId, {
    int limit = 10,
  }) async {
    try {
      final response = await client
          .from('artist_articles')
          .select()
          .eq('artist_id', artistId)
          .order('published_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.severe('Error fetching articles for artist $artistId: $e');
      return [];
    }
  }

  /// Retrieve all articles for a list of artist IDs ordered by recency.
  Future<List<Map<String, dynamic>>> getAllArtistArticles(
    List<String> artistIds, {
    int limit = 15,
  }) async {
    if (artistIds.isEmpty) return [];
    try {
      final response = await client
          .from('artist_articles')
          .select()
          .inFilter('artist_id', artistIds)
          .order('published_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.severe(
        'Error fetching articles for ${artistIds.length} artists: $e',
      );
      return [];
    }
  }

  /// Fetch articles spread across artists so no single artist dominates.
  /// Pulls up to [perArtist] recent articles per artist, then interleaves
  /// them in round-robin order with a randomised artist sequence.
  Future<List<Map<String, dynamic>>> getSpreadArtistArticles(
    List<String> artistIds, {
    int totalLimit = 12,
    int perArtist = 3,
  }) async {
    if (artistIds.isEmpty) return [];
    try {
      final fetchLimit = (artistIds.length * perArtist).clamp(totalLimit, 150);
      final response = await client
          .from('artist_articles')
          .select()
          .inFilter('artist_id', artistIds)
          .order('published_at', ascending: false)
          .limit(fetchLimit);

      final all = List<Map<String, dynamic>>.from(response);

      // Group by artist_id, preserving recency order within each group.
      final byArtist = <String, List<Map<String, dynamic>>>{};
      for (final article in all) {
        final id = article['artist_id'] as String;
        byArtist.putIfAbsent(id, () => []).add(article);
      }

      // Shuffle artist order so the carousel varies each load.
      final artistOrder = byArtist.keys.toList()..shuffle();

      // Round-robin interleave: take one article from each artist per round.
      final spread = <Map<String, dynamic>>[];
      var round = 0;
      outer:
      while (true) {
        var added = false;
        for (final artistId in artistOrder) {
          final list = byArtist[artistId]!;
          if (round < list.length) {
            spread.add(list[round]);
            added = true;
            if (spread.length >= totalLimit) break outer;
          }
        }
        if (!added) break;
        round++;
      }

      _logger.info(
        '[db] getSpreadArtistArticles: ${spread.length} articles across ${byArtist.length} artists',
      );
      return spread;
    } catch (e) {
      _logger.severe(
        'Error fetching spread articles for ${artistIds.length} artists: $e',
      );
      return [];
    }
  }

  /// Stamp last_press_scout_at for an artist to now.
  Future<void> updateLastPressScout(String artistId) async {
    try {
      await client
          .from('artists')
          .update({
            'last_press_scout_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', artistId);
      _logger.info('[db] updateLastPressScout: stamped $artistId');
    } catch (e) {
      _logger.severe('Error updating last_press_scout_at for $artistId: $e');
    }
  }

  // --- Platform Connections ---

  /// Retrieve a stored platform OAuth connection for a user.
  Future<Map<String, dynamic>?> getPlatformConnection(
    String userId,
    String platform,
  ) async {
    try {
      final response = await client
          .from('platform_connections')
          .select()
          .eq('user_id', userId)
          .eq('platform', platform)
          .maybeSingle();
      return response;
    } catch (e) {
      _logger.severe(
        'Error fetching platform connection $platform for $userId: $e',
      );
      return null;
    }
  }

  /// Upsert a platform connection row (encrypted token storage).
  Future<bool> savePlatformConnection(Map<String, dynamic> data) async {
    try {
      await client.from('platform_connections').upsert(data);
      _logger.info(
        '[db] savePlatformConnection: saved ${data['platform']} for ${data['user_id']}',
      );
      return true;
    } catch (e) {
      _logger.severe('Error saving platform connection: $e');
      return false;
    }
  }

  /// Bulk-import SC followed artists for a user.
  /// Upserts each artist into the global artists table, then creates follow rows
  /// for any not already followed. Returns {imported, total} counts.
  Future<Map<String, int>> importSoundCloudArtists(
    String userId,
    List<Map<String, dynamic>> scArtists,
  ) async {
    _logger.info(
      '[db] importSoundCloudArtists: ${scArtists.length} artists for user=$userId',
    );
    try {
      final usernames = scArtists
          .map((a) => a['soundcloud_username'] as String?)
          .whereType<String>()
          .toList();

      // Look up which of these artists already exist globally.
      final existingRows = await client
          .from('artists')
          .select('id, soundcloud_username')
          .inFilter('soundcloud_username', usernames);
      final existingByUsername = <String, String>{
        for (final r in List<Map<String, dynamic>>.from(existingRows))
          r['soundcloud_username'] as String: r['id'] as String,
      };

      // Look up which artists this user already follows.
      final followRows = await client
          .from('user_artist_follows')
          .select('artist_id')
          .eq('user_id', userId);
      final followedIds = {
        for (final r in List<Map<String, dynamic>>.from(followRows))
          r['artist_id'] as String,
      };

      _logger.info(
        '[db] importSoundCloudArtists: ${existingByUsername.length} known globally, ${followedIds.length} already followed by $userId',
      );

      final now = DateTime.now().toUtc().toIso8601String();
      var imported = 0;

      for (final a in scArtists) {
        final username = a['soundcloud_username'] as String?;
        if (username == null) continue;

        String artistId;
        if (existingByUsername.containsKey(username)) {
          artistId = existingByUsername[username]!;
        } else {
          final created = await client
              .from('artists')
              .insert({
                'name': a['name'] as String,
                'entity_type': 'artist',
                'soundcloud_username': username,
                'soundcloud_url': a['soundcloud_url'] as String?,
                'created_at': now,
              })
              .select()
              .single();
          artistId = created['id'] as String;
          existingByUsername[username] = artistId;
          _logger.fine(
            '[db] importSoundCloudArtists: created global artist $username id=$artistId',
          );
        }

        if (!followedIds.contains(artistId)) {
          await client.from('user_artist_follows').upsert({
            'user_id': userId,
            'artist_id': artistId,
            'followed_at': now,
          });
          followedIds.add(artistId);
          imported++;
        }
      }

      _logger.info(
        '[db] importSoundCloudArtists: $imported new follows for $userId',
      );
      return {'imported': imported, 'total': scArtists.length};
    } catch (e) {
      _logger.severe('[db] importSoundCloudArtists failed: $e');
      rethrow;
    }
  }

  /// Delete feed items older than [days] days (nightly cleanup job).
  Future<void> deleteOldFeedItems({int days = 365}) async {
    try {
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(Duration(days: days))
          .toIso8601String();
      await client.from('feed_items').delete().lt('published_at', cutoff);
      _logger.info(
        '[db] deleteOldFeedItems: deleted items older than $days days',
      );
    } catch (e) {
      _logger.severe('Error deleting old feed items: $e');
    }
  }

  /// Delete all feed_items for an artist (called when artist is removed from user's list).
  Future<void> deleteFeedItemsForArtist(String artistName) async {
    try {
      await client.from('feed_items').delete().ilike('artist_name', artistName);
      _logger.info(
        '[db] deleteFeedItemsForArtist: cleared feed items for $artistName (case-insensitive)',
      );
    } catch (e) {
      _logger.severe('Error deleting feed items for $artistName: $e');
    }
  }

  /// Delete feed_items for one artist/platform pair before a manual refresh.
  /// Throws on DB error so callers can treat a failed delete as a failed refresh
  /// rather than silently continuing with stale rows in place.
  Future<void> deleteFeedItemsForArtistPlatform(
    String artistName,
    String platform,
  ) async {
    await client
        .from('feed_items')
        .delete()
        .eq('artist_name', artistName)
        .eq('platform', platform);
    _logger.info(
      '[db] deleteFeedItemsForArtistPlatform: cleared $platform feed items for $artistName',
    );
  }

  /// Stamp when a platform was last polled for an artist.
  /// Writes to system_cache with key `last_polled:{platform}:{artistName}`.
  /// Mirrors database.py :: set_last_polled.
  Future<void> setLastPolled(String platform, String artistName) async {
    final key = 'last_polled:$platform:$artistName';
    await setSystemCache(key, {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    _logger.fine('[db] setLastPolled: $artistName ($platform)');
  }

  /// Read when a platform was last polled for an artist.
  /// Returns null if never polled or the cache entry is missing.
  /// Mirrors database.py :: get_last_polled.
  Future<DateTime?> getLastPolled(String platform, String artistName) async {
    final key = 'last_polled:$platform:$artistName';
    final cached = await getSystemCache(key);
    if (cached == null) return null;
    final ts = cached['timestamp'] as String?;
    if (ts == null) return null;
    return DateTime.tryParse(ts)?.toUtc();
  }

  // --- System Cache Helpers ---

  /// Retrieve a value from the system_cache table if not expired.
  /// ELI5: Checking our "Sticky Notes" to see if we already wrote something down.
  Future<Map<String, dynamic>?> getSystemCache(String key) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final response = await client
          .from('system_cache')
          .select('value, expires_at')
          .eq('key', key)
          .maybeSingle();

      if (response != null) {
        final expiresAt = response['expires_at'] as String?;
        if (expiresAt != null) {
          if (expiresAt.compareTo(now) < 0) {
            _logger.fine('System cache expired for key: $key');
            return null;
          }
        }
        return response['value'] as Map<String, dynamic>?;
      }
    } catch (e) {
      _logger.severe('Error reading system_cache for $key: $e');
    }
    return null;
  }

  /// Store a value in the system_cache table.
  /// ELI5: Writing a "Sticky Note" with an expiration date.
  Future<bool> setSystemCache(
    String key,
    Map<String, dynamic> value, {
    DateTime? expiresAt,
  }) async {
    try {
      final data = {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (expiresAt != null) {
        data['expires_at'] = expiresAt.toUtc().toIso8601String();
      }

      await client.from('system_cache').upsert(data);
      return true;
    } catch (e) {
      _logger.severe('Error writing system_cache for $key: $e');
      return false;
    }
  }

  /// Try to claim a short-lived lease represented by a system_cache row.
  ///
  /// Returns an owner token when this process claimed the lease, or null when a
  /// non-expired lease already exists. The insert relies on system_cache.key
  /// being unique, which is already required by the upsert-based cache helpers.
  Future<String?> tryClaimSystemCacheLease(
    String key, {
    required Duration ttl,
    Map<String, dynamic> metadata = const {},
  }) async {
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();
    try {
      final existing = await client
          .from('system_cache')
          .select('value, expires_at')
          .eq('key', key)
          .maybeSingle();

      if (existing != null) {
        final expiresAtRaw = existing['expires_at'] as String?;
        final expiresAt = expiresAtRaw == null
            ? null
            : DateTime.tryParse(expiresAtRaw)?.toUtc();
        if (expiresAt != null && expiresAt.isAfter(now)) {
          return null;
        }

        // Clear expired or malformed leases before trying to claim.
        await client.from('system_cache').delete().eq('key', key);
      }

      final owner =
          '${now.microsecondsSinceEpoch}-${Random().nextInt(0x7fffffff)}';
      await client.from('system_cache').insert({
        'key': key,
        'value': {'owner': owner, 'claimed_at': nowIso, ...metadata},
        'expires_at': now.add(ttl).toIso8601String(),
        'updated_at': nowIso,
      });
      return owner;
    } catch (e) {
      // Most commonly a unique-key race: another process claimed first.
      _logger.fine('System cache lease not claimed for $key: $e');
      return null;
    }
  }

  /// Release a lease only if it is still owned by the given owner token.
  Future<void> releaseSystemCacheLease(String key, String owner) async {
    try {
      final existing = await client
          .from('system_cache')
          .select('value')
          .eq('key', key)
          .maybeSingle();
      final value = existing?['value'] as Map<String, dynamic>?;
      if (value?['owner'] != owner) return;
      await client.from('system_cache').delete().eq('key', key);
    } catch (e) {
      _logger.fine('Error releasing system_cache lease for $key: $e');
    }
  }

  Future<void> deleteSystemCache(String key) async {
    try {
      await client.from('system_cache').delete().eq('key', key);
    } catch (e) {
      _logger.severe('Error deleting system_cache for $key: $e');
    }
  }
}
