import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';

final _logger = Logger('daily_inbox_service');

class DailyInboxService {
  const DailyInboxService(this._db);

  final DatabaseService _db;

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

    // Compute shared cutoff once — used by both global and custom builds.
    final since = await _computeSince(now, dateStr);

    // ── Global cached digest ──────────────────────────────────────────────────

    final existing = await _db.client
        .from('daily_inbox')
        .select()
        .eq('date', dateStr)
        .gt('expires_at', now.toIso8601String())
        .maybeSingle();

    Map<String, dynamic>? row;

    if (existing != null) {
      _logger.info('[inbox] returning cached digest date=$dateStr');
      row = existing;
    } else {
      _logger.info('[inbox] generating fresh digest date=$dateStr');
      final stations = await _buildStations(now, since);

      if (stations.isNotEmpty) {
        final expiresAt = now.add(const Duration(hours: 24));
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
      }
    }

    // ── Just Dropped (live freshness layer) ──────────────────────────────────
    // Tracks published after the cached digest was built won't appear in the
    // global stations — this section catches them without invalidating the cache.

    if (row != null) {
      final generatedAt = DateTime.parse(row['generated_at'] as String).toUtc();
      final existingStations = (row['stations'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final justDropped = await _buildJustDroppedStation(
        generatedAt,
        now,
        since,
        excludeKeys: _stationTrackKeys(existingStations),
      );
      if (justDropped != null) {
        row = {
          ...row,
          'stations': [justDropped, ...existingStations],
        };
      }
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

  /// Computes the lower-bound date for "new" tracks.
  ///
  /// Uses the previous digest's generated_at so consecutive days don't overlap.
  /// Falls back to 24h ago on first ever digest.
  Future<DateTime> _computeSince(DateTime now, String todayDateStr) async {
    final prevDigest = await _db.client
        .from('daily_inbox')
        .select('generated_at, date')
        .lt('date', todayDateStr)
        .order('date', ascending: false)
        .limit(1)
        .maybeSingle();

    if (prevDigest != null) {
      final since = DateTime.parse(
        prevDigest['generated_at'] as String,
      ).toUtc();
      _logger.info('[inbox] since=$since (prev digest ${prevDigest['date']})');
      return since;
    }

    final since = now.subtract(const Duration(hours: 24));
    _logger.info('[inbox] since=$since (24h fallback — no prior digest)');
    return since;
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

  /// Queries `feed_items` for tracks published after [cacheGeneratedAt] so that
  /// content released since today's digest was cached is surfaced in real-time.
  ///
  /// Returns null when nothing new has dropped — callers skip the section.
  /// Never written to `daily_inbox`; rebuilt on every request like YOUR PICKS.
  Future<Map<String, dynamic>?> _buildJustDroppedStation(
    DateTime cacheGeneratedAt,
    DateTime now,
    DateTime since, {
    Set<String> excludeKeys = const {},
  }) async {
    // Skip when the digest was literally just generated — nothing can have
    // dropped in the gap of a few seconds.
    if (now.difference(cacheGeneratedAt).inMinutes < 1) return null;

    try {
      final items = await _db.client
          .from('feed_items')
          .select(
            'title, artist_name, platform, content_type, external_url, '
            'artwork_url, published_at, duration_seconds, updated_at',
          )
          .gt('updated_at', cacheGeneratedAt.toIso8601String())
          .gte('published_at', since.toIso8601String())
          .lte('published_at', now.toIso8601String())
          .inFilter('content_type', [
            'track',
            'release',
            'ep',
            'album',
            'video',
          ])
          .order('published_at', ascending: false)
          .limit(50);

      final tracks = (items as List)
          .cast<Map<String, dynamic>>()
          .where((item) => !excludeKeys.contains(_trackKey(item)))
          .take(15)
          .toList();

      if (tracks.isEmpty) {
        _logger.info(
          '[inbox] no late-ingested tracks since '
          '${cacheGeneratedAt.toIso8601String()}',
        );
        return null;
      }

      _logger.info(
        '[inbox] JUST DROPPED: ${tracks.length} late-ingested tracks '
        'since $cacheGeneratedAt',
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

  Set<String> _stationTrackKeys(List<Map<String, dynamic>> stations) {
    final keys = <String>{};
    for (final station in stations) {
      final tracks = station['tracks'] as List? ?? const [];
      for (final track in tracks) {
        if (track is Map<String, dynamic>) {
          keys.add(_trackKey(track));
        }
      }
    }
    return keys;
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
