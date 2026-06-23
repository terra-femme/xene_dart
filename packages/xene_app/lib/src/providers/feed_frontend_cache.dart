import 'dart:collection';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';

// ─── Zone identifiers ────────────────────────────────────────────────────────

/// The three HTTP calls that make up a complete preset feed load.
abstract final class CacheZone {
  static const recentFast = 'recent_fast'; // SoundCloud + YouTube (phase-1)
  static const recentBc = 'recent_bc'; // Bandcamp (phase-2)
  static const archive = 'archive'; // 8–31d archive
}

// ─── Cache result ─────────────────────────────────────────────────────────────

enum CacheStatus { fresh, stale, miss }

/// Returned by [FeedFrontendCache.get] so callers can branch on hit/miss/stale
/// without a null check and without exposing internal entry state.
class CacheResult {
  const CacheResult._miss()
    : status = CacheStatus.miss,
      items = const [],
      isRefreshing = false;

  const CacheResult._({
    required this.status,
    required this.items,
    required this.isRefreshing,
  });

  final CacheStatus status;
  final List<FeedItem> items;

  /// True when a background refresh is already in-flight for this key.
  final bool isRefreshing;

  bool get isMiss => status == CacheStatus.miss;
  bool get isFresh => status == CacheStatus.fresh;
  bool get isStale => status == CacheStatus.stale;
  bool get hasData => status != CacheStatus.miss;

  static const miss = CacheResult._miss();
}

// ─── Internal entry ───────────────────────────────────────────────────────────

class _CacheEntry {
  _CacheEntry({
    required this.presetSlug,
    required this.zone,
    required this.items,
    required this.fetchedAt,
  });

  final String presetSlug;
  final String zone;
  final List<FeedItem> items;
  final DateTime fetchedAt;
  bool isRefreshing = false;

  Duration get age => DateTime.now().difference(fetchedAt);
}

// ─── Cache ────────────────────────────────────────────────────────────────────

/// In-memory, per-session feed cache keyed by preset slug + [CacheZone].
///
/// Three zones per preset: [CacheZone.recentFast], [CacheZone.recentBc],
/// [CacheZone.archive]. LRU eviction at [maxEntries] (default 30 = 10 presets
/// × 3 zones). Works on iOS, Android, and Web with no platform APIs.
///
/// Logging goes to both [debugPrint] (Flutter run terminal, Xcode console,
/// Android logcat) and [dart:developer] log (Flutter DevTools Logging tab +
/// browser F12 console on Web builds).
class FeedFrontendCache {
  FeedFrontendCache({this.maxEntries = 30});

  final int maxEntries;

  // LinkedHashMap preserves insertion order — LRU: oldest entry at front.
  final _store = LinkedHashMap<String, _CacheEntry>();

  // TTLs aligned to backend platform poll intervals.
  // recentFast / recentBc: 5 min — aggressive enough to feel fresh on re-visit.
  // archive: 10 min — archive items are stable, rarely change within a session.
  // These values are also defined in config.json as cache.recent_fast_minutes, etc.
  static const _ttls = <String, Duration>{
    CacheZone.recentFast: Duration(minutes: 5),
    CacheZone.recentBc: Duration(minutes: 5),
    CacheZone.archive: Duration(minutes: 10),
  };

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Look up [presetSlug] + [zone]. Promotes the entry to MRU on hit.
  /// Returns [CacheResult.miss] when the key has never been stored.
  CacheResult get(String presetSlug, String zone) {
    final key = _key(presetSlug, zone);
    final entry = _store[key];
    if (entry == null) {
      _log(presetSlug, zone, 'MISS', level: 500);
      return CacheResult.miss;
    }

    // LRU promotion: remove and re-insert at end.
    _store
      ..remove(key)
      ..[key] = entry;

    final ttl = _ttls[zone] ?? const Duration(minutes: 5);
    final isStale = entry.age > ttl;
    final status = isStale ? CacheStatus.stale : CacheStatus.fresh;

    _log(
      presetSlug,
      zone,
      isStale ? 'STALE-HIT' : 'HIT',
      detail:
          '${entry.items.length} items '
          'age=${_fmt(entry.age)} ttl=${_fmt(ttl)} '
          'refreshing=${entry.isRefreshing}',
      level: isStale ? 700 : 800,
    );

    return CacheResult._(
      status: status,
      items: List.unmodifiable(entry.items),
      isRefreshing: entry.isRefreshing,
    );
  }

  /// Store [items] for [presetSlug] + [zone]. Evicts LRU when over [maxEntries].
  /// Only call on a successful HTTP fetch — never cache 429 or empty-error results.
  void set(String presetSlug, String zone, List<FeedItem> items) {
    final key = _key(presetSlug, zone);
    _store
      ..remove(key) // re-insert at end = MRU
      ..[key] = _CacheEntry(
        presetSlug: presetSlug,
        zone: zone,
        items: List.unmodifiable(items),
        fetchedAt: DateTime.now(),
      );

    // Evict least-recently-used entries until within limit.
    while (_store.length > maxEntries) {
      final lru = _store.keys.first;
      _store.remove(lru);
      _logRaw(
        'EVICT-LRU key=$lru (entries now ${_store.length}/$maxEntries)',
        level: 900,
      );
    }

    _log(
      presetSlug,
      zone,
      'SET',
      detail: '${items.length} items (entries=${_store.length}/$maxEntries)',
      level: 800,
    );
  }

  /// Marks an entry as undergoing a background refresh so a second concurrent
  /// refresh is not scheduled for the same key.
  void markRefreshing(String presetSlug, String zone) {
    _store[_key(presetSlug, zone)]?.isRefreshing = true;
    _log(presetSlug, zone, 'REFRESH-MARK', level: 800);
  }

  /// Clears the refreshing flag. Call when a background refresh completes or fails.
  void clearRefreshing(String presetSlug, String zone) {
    _store[_key(presetSlug, zone)]?.isRefreshing = false;
    _log(presetSlug, zone, 'REFRESH-CLEAR', level: 800);
  }

  /// Removes all zones for [presetSlug]. Call before a force-refresh so the
  /// next [get] is a miss and fresh data is fetched.
  void invalidatePreset(String presetSlug) {
    final keys = _store.keys
        .where((k) => k.startsWith('$presetSlug:'))
        .toList();
    for (final k in keys) {
      _store.remove(k);
    }
    _logRaw(
      'INVALIDATE preset=$presetSlug removed=${keys.length} zones',
      level: 900,
    );
  }

  /// Clears the entire cache. Call on sign-out or account switch.
  void invalidateAll() {
    final count = _store.length;
    _store.clear();
    _logRaw('INVALIDATE-ALL cleared=$count', level: 900);
  }

  /// Diagnostic snapshot — safe to call from any context (e.g., debug overlay).
  Map<String, dynamic> get debugStats => {
    'entries': _store.length,
    'maxEntries': maxEntries,
    'keys': _store.keys.toList(),
    'detail': {
      for (final e in _store.entries)
        e.key: {
          'count': e.value.items.length,
          'age': _fmt(e.value.age),
          'refreshing': e.value.isRefreshing,
        },
    },
  };

  // ── Private helpers ─────────────────────────────────────────────────────────

  String _key(String preset, String zone) => '$preset:$zone';

  void _log(
    String preset,
    String zone,
    String event, {
    String? detail,
    int level = 800,
  }) {
    final msg =
        '[FeedCache] $event preset=$preset zone=$zone'
        '${detail != null ? " $detail" : ""}';
    debugPrint(msg);
    dev.log(msg, name: 'FeedCache', level: level);
  }

  void _logRaw(String msg, {int level = 800}) {
    final full = '[FeedCache] $msg';
    debugPrint(full);
    dev.log(full, name: 'FeedCache', level: level);
  }

  static String _fmt(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m${d.inSeconds % 60}s';
    return '${d.inHours}h${d.inMinutes % 60}m';
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

/// App-lifetime cache. Not auto-disposed — outlives preset changes, navigation,
/// and route pushes. Call [FeedFrontendCache.invalidateAll] on sign-out.
final feedFrontendCacheProvider = Provider<FeedFrontendCache>((ref) {
  return FeedFrontendCache();
});
