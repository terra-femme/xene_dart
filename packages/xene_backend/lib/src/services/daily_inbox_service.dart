import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';

final _logger = Logger('daily_inbox_service');

class DailyInboxService {
  const DailyInboxService(this._db);

  final DatabaseService _db;

  // Rolling lookback for "new" tracks (Fix A). Replaces the prior
  // previous-digest-generated_at boundary, which produced a narrow overnight
  // slice and silently dropped presets whose content lands later in the day
  // (e.g. RADIO / MEDIA). A fixed 24h window keeps the digest complete.
  static const _digestWindow = Duration(hours: 24);

  // Named stations are rebuilt when the cached row is older than this (Fix B)
  // so content dropping through the day appears without waiting for tomorrow.
  // The 24h availability countdown (expires_at) is preserved across rebuilds
  // so the "expires in" banner doesn't keep resetting.
  static const _digestRefreshInterval = Duration(hours: 3);

  /// JUST DROPPED highlights tracks published within this window — a real-time
  /// "what's hot right now" lens keyed on real publish time, independent of the
  /// snapshot. Intentionally overlaps named stations; in-memory only.
  static const _justDroppedWindow = Duration(hours: 1);

  // Templates + sources change rarely; cache them in-process (static → shared
  // across requests on the singleton service) so the per-request live merge
  // issues no reads for them. Keeps the digest lean on Supabase free tier.
  static List<Map<String, dynamic>>? _templatesCache;
  static List<Map<String, dynamic>>? _sourcesCache;
  static DateTime? _metaCachedAt;
  static const _metaCacheTtl = Duration(minutes: 10);

  /// Returns today's digest, optionally personalised with a "YOUR PICKS" station
  /// prepended for authenticated non-anonymous users who have a custom notch.
  ///
  /// The global station rows are cached in `daily_inbox` per calendar day.
  /// The custom section is generated fresh per request and never written to
  /// the cache — so it adds exactly 2 DB queries for real users, once per
  /// session (client caches the response in memory via dailyInboxProvider).
  Future<Map<String, dynamic>?> getOrGenerate({
    String? userId,
    bool isAnon = true,
  }) async {
    final now = DateTime.now().toUtc();
    final dateStr = now.toIso8601String().substring(0, 10);

    _logger.info(
      '[inbox] getOrGenerate date=$dateStr '
      'userId=${userId != null ? "present" : "none"} isAnon=$isAnon',
    );

    // Rolling 24h lookback shared by both global and custom builds (Fix A).
    final since = now.subtract(_digestWindow);

    // ── Global cached digest ──────────────────────────────────────────────────

    // Date-keyed row for today. Unlike before we do NOT filter on expires_at:
    // freshness is decided by generated_at age (Fix B) so the digest can refresh
    // intra-day instead of being frozen at the day's first request.
    final existing = await _db.client
        .from('daily_inbox')
        .select()
        .eq('date', dateStr)
        .maybeSingle();

    Map<String, dynamic>? row;

    final cacheAge = existing == null
        ? null
        : now.difference(
            DateTime.parse(existing['generated_at'] as String).toUtc(),
          );
    final isFresh = cacheAge != null && cacheAge < _digestRefreshInterval;

    if (isFresh) {
      _logger.info(
        '[inbox] returning cached digest date=$dateStr '
        'age=${cacheAge.inMinutes}m (< ${_digestRefreshInterval.inMinutes}m)',
      );
      row = existing;
    } else {
      _logger.info(
        '[inbox] ${existing == null ? "generating" : "refreshing"} digest '
        'date=$dateStr'
        '${cacheAge != null ? " (age=${cacheAge.inMinutes}m)" : ""}',
      );
      final stations = await _buildStations(now, since);

      if (stations.isNotEmpty) {
        // Preserve the original 24h availability countdown across intra-day
        // refreshes — only the day's first generation sets expires_at.
        final expiresAt = existing != null
            ? DateTime.parse(existing['expires_at'] as String).toUtc()
            : now.add(const Duration(hours: 24));
        row = await _db.client
            .from('daily_inbox')
            .upsert({
              'date': dateStr,
              'stations': stations,
              'generated_at': now.toIso8601String(),
              'expires_at': expiresAt.toIso8601String(),
            }, onConflict: 'date')
            .select()
            .single();

        _logger.info(
          '[inbox] stored digest date=$dateStr '
          'stations=${stations.length} expires=$expiresAt',
        );

        // Clean up rows older than 48h — fire and forget.
        final cutoff = now.subtract(const Duration(hours: 48));
        _db.client
            .from('daily_inbox')
            .delete()
            .lt('expires_at', cutoff.toIso8601String())
            .then((_) => _logger.fine('[inbox] old rows purged'))
            .catchError((e) => _logger.warning('[inbox] purge failed: $e'));
      } else {
        _logger.warning('[inbox] no stations with recent tracks date=$dateStr');
        // A stale-but-non-empty cached row beats dropping the digest entirely.
        row = existing;
      }
    }

    // ── Live layer (in-memory only — never persisted to Supabase) ────────────

    if (row != null) {
      final generatedAt = DateTime.parse(row['generated_at'] as String).toUtc();
      var stations = (row['stations'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      // (1) Source-aware merge: route snapshot-missed (late-ingested) items into
      //     their matching named station so high-frequency sources (RADIO/MEDIA)
      //     aren't stranded in JUST DROPPED between 3h rebuilds.
      final lateItems = await _fetchLateIngested(generatedAt, since, now);
      stations = await _mergeLateItemsIntoStations(stations, lateItems);

      // (2) JUST DROPPED: the freshest tracks by real publish time — a "what's
      //     hot now" highlight reel that intentionally overlaps named stations.
      final justDropped = await _buildJustDroppedStation(now);

      row = {
        ...row,
        'stations': [if (justDropped != null) justDropped, ...stations],
      };
    }

    // ── Custom picks (real users only) ────────────────────────────────────────

    if (userId != null && !isAnon) {
      final customStation = await _buildCustomStation(userId, now, since);
      if (customStation != null) {
        final globalStations = (row?['stations'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        _logger.info('[inbox] prepending YOUR PICKS for user=$userId');
        // Return an in-memory merged row — never persisted with the custom section.
        return {
          ...(row ??
              {
                'id': 'custom-only',
                'date': dateStr,
                'generated_at': now.toIso8601String(),
                'expires_at': now
                    .add(const Duration(hours: 24))
                    .toIso8601String(),
              }),
          'stations': [customStation, ...globalStations],
        };
      }
    }

    return row;
  }

  Future<List<Map<String, dynamic>>> _buildStations(
    DateTime now,
    DateTime since,
  ) async {
    final results = await Future.wait([
      _db.client
          .from('preset_templates')
          .select('id, slug, name, theme_color, notch_index')
          .eq('enabled', true)
          .eq('is_public', true)
          .order('notch_index'),
      _db.client
          .from('preset_template_sources')
          .select('template_id, display_name')
          .eq('enabled', true),
      _db.client
          .from('feed_items')
          .select(
            'title, artist_name, platform, content_type, external_url, artwork_url, published_at, duration_seconds',
          )
          .gte('published_at', since.toIso8601String())
          // Exclude pre-release tracks — artists set release_date to the future;
          // without this upper bound those items pass the >=since filter forever.
          .lte('published_at', now.toIso8601String())
          .inFilter('content_type', [
            'track',
            'release',
            'ep',
            'album',
            'video',
          ])
          .order('published_at', ascending: false),
    ]);

    final templates = (results[0] as List).cast<Map<String, dynamic>>();
    final sources = (results[1] as List).cast<Map<String, dynamic>>();
    final recentItems = (results[2] as List).cast<Map<String, dynamic>>();

    _logger.info(
      '[inbox] build: templates=${templates.length} '
      'sources=${sources.length} recentItems=${recentItems.length}',
    );

    // name → set of template_ids (case-insensitive)
    final nameToTemplateIds = <String, Set<String>>{};
    for (final src in sources) {
      final key = (src['display_name'] as String).toLowerCase();
      nameToTemplateIds
          .putIfAbsent(key, () => {})
          .add(src['template_id'] as String);
    }

    // group recent items by template_id
    final tracksByTemplate = <String, List<Map<String, dynamic>>>{};
    for (final item in recentItems) {
      final key = (item['artist_name'] as String? ?? '').toLowerCase();
      final tids = nameToTemplateIds[key] ?? {};
      for (final tid in tids) {
        tracksByTemplate.putIfAbsent(tid, () => []).add(item);
      }
    }

    final stations = <Map<String, dynamic>>[];
    for (final t in templates) {
      final tid = t['id'] as String;
      final tracks = tracksByTemplate[tid] ?? [];
      if (tracks.isEmpty) continue;
      stations.add({
        'slug': t['slug'],
        'name': t['name'],
        'theme_color': t['theme_color'],
        'tracks': tracks.take(15).toList(),
      });
    }

    _logger.info(
      '[inbox] built ${stations.length} stations: '
      '${stations.map((s) => "${s['name']}:${(s['tracks'] as List).length}").join(', ')}',
    );

    return stations;
  }

  /// Builds a personalised "YOUR PICKS" station from the user's custom notch.
  ///
  /// Returns null when the user has no custom sources or no tracks in the
  /// current window — callers can treat null as "nothing to show".
  /// Non-fatal: any DB error returns null so the global digest still renders.
  Future<Map<String, dynamic>?> _buildCustomStation(
    String userId,
    DateTime now,
    DateTime since,
  ) async {
    try {
      final sourcesRes = await _db.client
          .from('user_custom_preset_sources')
          .select('display_name')
          .eq('user_id', userId)
          .eq('enabled', true);

      final sources = (sourcesRes as List).cast<Map<String, dynamic>>();
      if (sources.isEmpty) {
        _logger.info('[inbox] no custom sources for user=$userId');
        return null;
      }

      final artistNames = sources
          .map((s) => (s['display_name'] as String?)?.trim() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      if (artistNames.isEmpty) return null;

      // Lowercase once — used for case-insensitive Dart-side matching below,
      // mirroring the same normalisation _buildStations does for global stations.
      final lowerNames = artistNames.map((n) => n.toLowerCase()).toSet();

      _logger.info(
        '[inbox] custom sources for user=$userId: ${artistNames.length} artists',
      );

      // Fetch the date-window items without an artist filter so Postgres
      // doesn't do a case-sensitive IN match — we filter in Dart instead.
      final rawItems = await _db.client
          .from('feed_items')
          .select(
            'title, artist_name, platform, content_type, external_url, artwork_url, published_at, duration_seconds',
          )
          .gte('published_at', since.toIso8601String())
          .lte('published_at', now.toIso8601String())
          .inFilter('content_type', [
            'track',
            'release',
            'ep',
            'album',
            'video',
          ])
          .order('published_at', ascending: false);

      final tracks = (rawItems as List)
          .cast<Map<String, dynamic>>()
          .where(
            (i) => lowerNames.contains(
              (i['artist_name'] as String? ?? '').toLowerCase(),
            ),
          )
          .take(15)
          .toList();

      if (tracks.isEmpty) {
        _logger.info(
          '[inbox] no recent custom tracks for user=$userId '
          '(checked ${artistNames.length} artists)',
        );
        return null;
      }

      _logger.info(
        '[inbox] YOUR PICKS: ${tracks.length} tracks for user=$userId',
      );

      return {
        'slug': 'your-picks',
        'name': 'YOUR PICKS',
        'theme_color': '#00BFA5',
        'tracks': tracks,
      };
    } catch (e) {
      _logger.warning(
        '[inbox] _buildCustomStation failed (non-fatal) user=$userId: $e',
      );
      return null;
    }
  }

  /// Fetches items ingested after the snapshot was built ([generatedAt]) within
  /// the rolling window — the content the cached named stations missed. Feeds
  /// the source-aware merge. Capped at 200 to cover batch ingests (a single
  /// poll can land 60+ items for one station). Non-fatal: returns [] on error.
  Future<List<Map<String, dynamic>>> _fetchLateIngested(
    DateTime generatedAt,
    DateTime since,
    DateTime now,
  ) async {
    try {
      final items = await _db.client
          .from('feed_items')
          .select(
            'title, artist_name, platform, content_type, external_url, '
            'artwork_url, published_at, duration_seconds',
          )
          .gt('updated_at', generatedAt.toIso8601String())
          .gte('published_at', since.toIso8601String())
          .lte('published_at', now.toIso8601String())
          .inFilter('content_type', const [
            'track',
            'release',
            'ep',
            'album',
            'video',
          ])
          .order('published_at', ascending: false)
          .limit(200);
      final list = (items as List).cast<Map<String, dynamic>>();
      _logger.info(
        '[inbox] live merge: ${list.length} late-ingested items since '
        '${generatedAt.toIso8601String()}',
      );
      return list;
    } catch (e) {
      _logger.warning('[inbox] _fetchLateIngested failed (non-fatal): $e');
      return const [];
    }
  }

  /// Routes [lateItems] into their matching named station (by preset source
  /// name, case-insensitive) so snapshot-missed content appears under its real
  /// station immediately. Dedupes per station and re-caps at 15; creates a
  /// station the snapshot omitted entirely. In-memory only — never persisted.
  Future<List<Map<String, dynamic>>> _mergeLateItemsIntoStations(
    List<Map<String, dynamic>> cachedStations,
    List<Map<String, dynamic>> lateItems,
  ) async {
    if (lateItems.isEmpty) return cachedStations;

    final (templates, sources) = await _loadTemplatesAndSources();

    // display_name (lower) → template_ids
    final nameToTemplateIds = <String, Set<String>>{};
    for (final src in sources) {
      final key = (src['display_name'] as String).toLowerCase();
      nameToTemplateIds
          .putIfAbsent(key, () => {})
          .add(src['template_id'] as String);
    }

    // template_id → its late items
    final lateByTemplate = <String, List<Map<String, dynamic>>>{};
    for (final item in lateItems) {
      final key = (item['artist_name'] as String? ?? '').toLowerCase();
      for (final tid in nameToTemplateIds[key] ?? const <String>{}) {
        lateByTemplate.putIfAbsent(tid, () => []).add(item);
      }
    }
    if (lateByTemplate.isEmpty) return cachedStations;

    // slug → mutable copy of the cached station
    final bySlug = <String, Map<String, dynamic>>{
      for (final s in cachedStations)
        s['slug'] as String: {
          ...s,
          'tracks': [...(s['tracks'] as List).cast<Map<String, dynamic>>()],
        },
    };

    int byPublishedDesc(Map<String, dynamic> a, Map<String, dynamic> b) =>
        (b['published_at'] as String? ?? '').compareTo(
          a['published_at'] as String? ?? '',
        );

    // Re-emit in notch order so any newly-created station slots into place.
    final ordered = <Map<String, dynamic>>[];
    for (final t in templates) {
      final tid = t['id'] as String;
      final slug = t['slug'] as String;
      final late = lateByTemplate[tid];
      final existing = bySlug[slug];

      if (existing != null && late != null && late.isNotEmpty) {
        final tracks = (existing['tracks'] as List)
            .cast<Map<String, dynamic>>();
        final seen = {for (final tr in tracks) _trackKey(tr)};
        for (final item in late) {
          if (seen.add(_trackKey(item))) tracks.add(item);
        }
        tracks.sort(byPublishedDesc);
        existing['tracks'] = tracks.take(15).toList();
        ordered.add(existing);
      } else if (existing != null) {
        ordered.add(existing);
      } else if (late != null && late.isNotEmpty) {
        final tracks = [...late]..sort(byPublishedDesc);
        ordered.add({
          'slug': slug,
          'name': t['name'],
          'theme_color': t['theme_color'],
          'tracks': tracks.take(15).toList(),
        });
      }
    }

    // Defensive: keep any cached station whose template is no longer listed
    // (e.g. a since-disabled preset still present in today's snapshot).
    final orderedSlugs = {for (final s in ordered) s['slug']};
    for (final s in cachedStations) {
      if (!orderedSlugs.contains(s['slug'])) ordered.add(bySlug[s['slug']]!);
    }

    _logger.info(
      '[inbox] merged late items → ${ordered.length} stations: '
      '${ordered.map((s) => "${s['name']}:${(s['tracks'] as List).length}").join(', ')}',
    );
    return ordered;
  }

  /// JUST DROPPED — the freshest tracks by real publish time (last
  /// [_justDroppedWindow]). A real-time highlight reel that intentionally
  /// overlaps named stations. Tiny capped query; null when nothing is fresh.
  Future<Map<String, dynamic>?> _buildJustDroppedStation(DateTime now) async {
    final cutoff = now.subtract(_justDroppedWindow);
    try {
      final items = await _db.client
          .from('feed_items')
          .select(
            'title, artist_name, platform, content_type, external_url, '
            'artwork_url, published_at, duration_seconds',
          )
          .gte('published_at', cutoff.toIso8601String())
          .lte('published_at', now.toIso8601String())
          .inFilter('content_type', const [
            'track',
            'release',
            'ep',
            'album',
            'video',
          ])
          .order('published_at', ascending: false)
          .limit(10);
      final tracks = (items as List).cast<Map<String, dynamic>>();
      if (tracks.isEmpty) {
        _logger.info(
          '[inbox] JUST DROPPED: nothing published in last '
          '${_justDroppedWindow.inMinutes}m',
        );
        return null;
      }
      _logger.info(
        '[inbox] JUST DROPPED: ${tracks.length} tracks '
        '(last ${_justDroppedWindow.inMinutes}m)',
      );
      return {
        'slug': 'just-dropped',
        'name': 'JUST DROPPED',
        'theme_color': '#FF4081',
        'tracks': tracks,
      };
    } catch (e) {
      _logger.warning(
        '[inbox] _buildJustDroppedStation failed (non-fatal): $e',
      );
      return null;
    }
  }

  /// Loads enabled+public templates and enabled sources, cached in-process for
  /// [_metaCacheTtl] so the per-request live merge needs no reads for them.
  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>
  _loadTemplatesAndSources() async {
    final cachedAt = _metaCachedAt;
    if (_templatesCache != null &&
        _sourcesCache != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _metaCacheTtl) {
      return (_templatesCache!, _sourcesCache!);
    }
    final results = await Future.wait([
      _db.client
          .from('preset_templates')
          .select('id, slug, name, theme_color, notch_index')
          .eq('enabled', true)
          .eq('is_public', true)
          .order('notch_index'),
      _db.client
          .from('preset_template_sources')
          .select('template_id, display_name')
          .eq('enabled', true),
    ]);
    _templatesCache = (results[0] as List).cast<Map<String, dynamic>>();
    _sourcesCache = (results[1] as List).cast<Map<String, dynamic>>();
    _metaCachedAt = DateTime.now();
    _logger.fine(
      '[inbox] cached templates=${_templatesCache!.length} '
      'sources=${_sourcesCache!.length}',
    );
    return (_templatesCache!, _sourcesCache!);
  }

  String _trackKey(Map<String, dynamic> item) {
    final platform = (item['platform'] as String? ?? '').toLowerCase();
    final url = (item['external_url'] as String? ?? '').trim();
    if (url.isNotEmpty) return '$platform:$url';

    final artist = (item['artist_name'] as String? ?? '').toLowerCase();
    final title = (item['title'] as String? ?? '').toLowerCase();
    final publishedAt = item['published_at']?.toString() ?? '';
    return '$platform:$artist:$title:$publishedAt';
  }
}
