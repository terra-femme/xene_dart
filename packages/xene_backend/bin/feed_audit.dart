import 'dart:io';

import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/feed_cache.dart';
import 'package:xene_backend/src/services/bandcamp_service.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/youtube_service.dart';
import 'package:xene_domain/xene_domain.dart';

const _userIdDefault = 'local_user';
const _cacheDaysDefault = 31;
const _recentDays = 7;
const _envLoadedFlag = 'XENE_FEED_AUDIT_ENV_LOADED';

const _platforms = {'soundcloud', 'youtube', 'bandcamp'};

Future<void> main(List<String> args) async {
  final options = _AuditOptions.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  await _relaunchWithDotEnvIfNeeded(args);

  Logger.root.level = options.verbose ? Level.INFO : Level.WARNING;
  Logger.root.onRecord.listen((record) {
    stderr.writeln(
      '[${record.level.name}] ${record.loggerName}: ${record.message}',
    );
  });

  final db = DatabaseService();
  final artists = await _loadArtists(db, options);
  if (artists.isEmpty) {
    stderr.writeln('No artists matched the requested scope.');
    exitCode = 1;
    return;
  }

  final sc = SoundCloudService(db);
  final yt = YouTubeService(db);
  final bc = BandcampService(db);
  final now = DateTime.now().toUtc();

  // ── Build one StringBuffer per platform + one combined ───────────────────
  String _header(String platformLabel) => [
        '# Xene Feed Audit — $platformLabel',
        '',
        '- Generated: ${now.toIso8601String()}',
        '- User: `${options.userId}`',
        '- Scope: ${options.scopeLabel}',
        '- Platforms: $platformLabel',
        '- Mode: ${options.live ? 'live fetch + Supabase comparison' : 'Supabase cache only'}',
        '- Window: ${options.cacheDays} days',
        '',
        'Legend: `recent` = 0-$_recentDays calendar days · `archive` = ${_recentDays + 1}-${options.cacheDays} days · `outside` = older than ${options.cacheDays} days.',
        '',
      ].join('\n');

  final combinedReport = StringBuffer(_header('All Platforms'));
  final platformBuffers = <String, StringBuffer>{
    for (final p in options.platforms)
      p: StringBuffer(_header(_title(p))),
  };

  for (final artist in artists) {
    final artistName = _artistName(artist);
    final artistHeader = StringBuffer()
      ..writeln('## ${_md(artistName)}')
      ..writeln()
      ..writeln('| Field | Value |')
      ..writeln('| --- | --- |')
      ..writeln('| Artist id | `${artist['id'] ?? 'source-row'}` |')
      ..writeln(
        '| SoundCloud | ${_md(_firstNonEmpty([artist['soundcloud_url'], artist['soundcloud_username']]) ?? '-')} |',
      )
      ..writeln('| YouTube | ${_md(_youtubeIdentifier(artist) ?? '-')} |')
      ..writeln(
        '| Bandcamp | ${_md((artist['bandcamp_url'] as String?) ?? '-')} |',
      )
      ..writeln();

    combinedReport.write(artistHeader);
    for (final buf in platformBuffers.values) {
      buf.write(artistHeader);
    }

    for (final platform in options.platforms) {
      final source = _sourceForPlatform(artist, platform);
      String sectionText;

      if (source == null || source.isEmpty) {
        sectionText =
            '### ${_title(platform)}\n\nNo source configured for this artist/platform.\n\n';
      } else {
        stderr.writeln('Auditing $artistName / $platform');
        final cachedRows = await db.getCachedFeedItems(
          platform: platform,
          artistName: artistName,
          days: options.cacheDays,
          limit: options.limit,
        );
        final cachedItems = cachedRows
            .map(feedItemFromRow)
            .whereType<FeedItem>()
            .toList();
        final lastPolled = await db.getLastPolled(platform, artistName);
        final emptyMarker = await db.getSystemCache(
          'feed_empty_window:$platform:$artistName:${options.cacheDays}d',
        );

        final auditSink = <Map<String, dynamic>>[];
        List<FeedItem> liveItems = const [];
        Object? liveError;
        BcDebugReport? bcDebugReport;
        if (options.live) {
          try {
            liveItems = switch (platform) {
              'soundcloud' => await sc.getTracks(
                source,
                artistName,
                bypassMemoryCache: true,
                auditSink: auditSink,
              ),
              'youtube' => await yt.getVideos(
                source,
                artistName,
                auditSink: auditSink,
              ),
              'bandcamp' => await bc.getFeed(
                source,
                artistName,
                bypassMemoryCache: true,
                auditSink: auditSink,
              ),
              _ => const <FeedItem>[],
            };
          } catch (e) {
            liveError = e;
          }

          if (platform == 'bandcamp' && liveError == null) {
            try {
              bcDebugReport = await bc.getDebugReport(source, artistName);
            } catch (e) {
              stderr.writeln('[audit] Bandcamp debug report failed: $e');
            }
          }
        }

        sectionText = _buildPlatformSection(
          platform: platform,
          source: source,
          lastPolled: lastPolled,
          emptyMarker: emptyMarker,
          cachedItems: cachedItems,
          liveItems: liveItems,
          liveError: liveError,
          liveWasRun: options.live,
          now: now,
          cacheDays: options.cacheDays,
          limit: options.limit,
          bcDebugReport: bcDebugReport,
          auditSink: auditSink,
        );
      }

      combinedReport.write(sectionText);
      platformBuffers[platform]?.write(sectionText);
    }
  }

  if (options.outPath == null) {
    stdout.write(combinedReport.toString());
  } else {
    _writeReportFile(options.outPath!, combinedReport.toString());
    if (options.platforms.length > 1) {
      for (final platform in options.platforms) {
        final path = _platformPath(options.outPath!, platform);
        _writeReportFile(path, platformBuffers[platform]!.toString());
      }
    }
  }

  exit(0);
}

void _writeReportFile(String path, String text) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text);
  stdout.writeln('Wrote ${file.absolute.path}');
}

String _platformPath(String outPath, String platform) {
  final suffix = switch (platform) {
    'soundcloud' => '_sc',
    'youtube' => '_yt',
    'bandcamp' => '_bc',
    _ => '_$platform',
  };
  if (outPath.endsWith('.md')) {
    return '${outPath.substring(0, outPath.length - 3)}$suffix.md';
  }
  return '$outPath$suffix';
}

Future<List<Map<String, dynamic>>> _loadArtists(
  DatabaseService db,
  _AuditOptions options,
) async {
  final rows = options.preset == null || options.preset!.isEmpty
      ? await db.getArtists(options.userId)
      : await db.getArtistsForPreset(options.userId, options.preset!);

  final filtered = rows.where((row) {
    if (options.artistQuery == null) return true;
    final q = options.artistQuery!.toLowerCase();
    return _artistName(row).toLowerCase().contains(q);
  }).toList()..sort((a, b) => _artistName(a).compareTo(_artistName(b)));

  if (options.artistLimit == null) return filtered;
  return filtered.take(options.artistLimit!).toList();
}

String _buildPlatformSection({
  required String platform,
  required String source,
  required DateTime? lastPolled,
  required Map<String, dynamic>? emptyMarker,
  required List<FeedItem> cachedItems,
  required List<FeedItem> liveItems,
  required Object? liveError,
  required bool liveWasRun,
  required DateTime now,
  required int cacheDays,
  required int limit,
  BcDebugReport? bcDebugReport,
  List<Map<String, dynamic>>? auditSink,
}) {
  final report = StringBuffer();
  final liveIds = liveItems.map(_identity).toSet();
  final cachedIds = cachedItems.map(_identity).toSet();
  final liveMissingInCache = liveItems
      .where((i) => !cachedIds.contains(_identity(i)))
      .toList();
  final cacheMissingInLive = liveWasRun
      ? cachedItems.where((i) => !liveIds.contains(_identity(i))).toList()
      : const <FeedItem>[];

  report
    ..writeln('### ${_title(platform)}')
    ..writeln()
    ..writeln('| Check | Value |')
    ..writeln('| --- | --- |')
    ..writeln('| Source | ${_md(source)} |')
    ..writeln('| Last polled | ${lastPolled?.toIso8601String() ?? '-'} |')
    ..writeln(
      '| Verified-empty marker | ${emptyMarker == null ? '-' : _md(emptyMarker.toString())} |',
    )
    ..writeln('| Supabase rows in ${cacheDays}d | ${cachedItems.length} |')
    ..writeln(
      '| Live normalized items | ${!liveWasRun
          ? 'not run'
          : liveError == null
          ? liveItems.length
          : 'ERROR'} |',
    );
  if (liveError != null) {
    report.writeln('| Live error | ${_md(liveError.toString())} |');
  }
  report.writeln();

  if (liveItems.isNotEmpty) {
    _writeItemsTable(
      report,
      'Live Normalized Items',
      liveItems,
      now,
      cacheDays,
      limit,
      cachedIds: cachedIds,
    );
  }

  _writeItemsTable(
    report,
    'Supabase `feed_items` Rows',
    cachedItems,
    now,
    cacheDays,
    limit,
    liveIds: liveIds,
  );

  if (liveItems.isNotEmpty || cachedItems.isNotEmpty || liveError != null) {
    report
      ..writeln('#### Cross-check')
      ..writeln()
      ..writeln('| Bucket | Count | What to read |')
      ..writeln('| --- | ---: | --- |')
      ..writeln(
        '| Live but not in Supabase | ${liveWasRun ? liveMissingInCache.length : 'not run'} | Parser found it, but cache/upsert/query may be the issue. |',
      )
      ..writeln(
        '| Supabase but not live | ${liveWasRun ? cacheMissingInLive.length : 'not run'} | Cache contains rows not returned by current live fetch. Could be stale, deleted upstream, or a platform/API difference. |',
      )
      ..writeln(
        '| Duplicate live ids | ${liveWasRun ? _duplicateCount(liveItems) : 'not run'} | Same `platform:id` appears more than once before save. |',
      )
      ..writeln(
        '| Duplicate Supabase ids | ${_duplicateCount(cachedItems)} | Same `platform:id` appears more than once after read. |',
      )
      ..writeln();

    if (liveMissingInCache.isNotEmpty) {
      _writeCompactList(
        report,
        'Live but not in Supabase',
        liveMissingInCache,
        now,
        cacheDays,
      );
    }
    if (cacheMissingInLive.isNotEmpty && liveItems.isNotEmpty) {
      _writeCompactList(
        report,
        'Supabase but not live',
        cacheMissingInLive,
        now,
        cacheDays,
      );
    }
  }

  if (auditSink != null && auditSink.isNotEmpty) {
    switch (platform) {
      case 'soundcloud':
        _writeScFetchLog(report, auditSink);
        _writeScRawDatesTable(report, auditSink);
      case 'youtube':
        _writeYtFetchLog(report, auditSink);
        _writeYtRawDatesTable(report, auditSink);
      case 'bandcamp':
        _writeBcItemRawDatesTable(report, auditSink);
    }
  }

  if (bcDebugReport != null) {
    _writeBcDebugSection(report, bcDebugReport, now, cacheDays);
  }

  return report.toString();
}

void _writeItemsTable(
  StringBuffer report,
  String title,
  List<FeedItem> items,
  DateTime now,
  int cacheDays,
  int limit, {
  Set<String>? cachedIds,
  Set<String>? liveIds,
}) {
  report
    ..writeln('#### $title')
    ..writeln();

  if (items.isEmpty) {
    report
      ..writeln('No rows.')
      ..writeln();
    return;
  }

  final sorted = List<FeedItem>.from(items)
    ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

  final recent = sorted.where((i) => _zoneType(i.publishedAt, now, cacheDays) == 'recent').toList();
  final archive = sorted.where((i) => _zoneType(i.publishedAt, now, cacheDays) == 'archive').toList();
  final outside = sorted.where((i) => _zoneType(i.publishedAt, now, cacheDays) == 'outside').toList();

  report.writeln(
    '**Feed Lane Distribution:** '
    '${recent.length} recent (0–${_recentDays}d) · '
    '${archive.length} archive (${_recentDays + 1}–${cacheDays}d) · '
    '${outside.length} outside window',
  );
  report.writeln();

  void _writeSection(String header, List<FeedItem> lane) {
    report.writeln('##### $header (${lane.length} items)');
    report.writeln();
    if (lane.isEmpty) {
      report
        ..writeln('_No items._')
        ..writeln();
      return;
    }
    report
      ..writeln('| Date | Zone | Title | Type | Id | URL | Note |')
      ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
    var shown = 0;
    for (final item in lane) {
      if (shown >= limit) break;
      final id = _identity(item);
      final notes = <String>[
        if (cachedIds != null && !cachedIds.contains(id)) 'not in Supabase',
        if (liveIds != null && liveIds.isNotEmpty && !liveIds.contains(id))
          'not in live',
        if (item.externalUrl.isEmpty) 'missing URL',
        if ((item.title ?? '').trim().isEmpty) 'missing title',
      ];
      report.writeln(
        '| ${_date(item.publishedAt)} | ${_zone(item.publishedAt, now, cacheDays)} | '
        '${_md(item.title ?? 'Untitled')} | ${_md(item.contentType)} | `${_md(id)}` | '
        '${_md(item.externalUrl)} | ${_md(notes.isEmpty ? '-' : notes.join(', '))} |',
      );
      shown++;
    }
    if (lane.length > limit) {
      report.writeln(
        '| ... | ... | ${lane.length - limit} more omitted by `--limit` | ... | ... | ... | ... |',
      );
    }
    report.writeln();
  }

  _writeSection('Recent Feed — 0 to $_recentDays days', recent);
  _writeSection('Archive Feed — ${_recentDays + 1} to $cacheDays days', archive);
  if (outside.isNotEmpty) {
    _writeSection('Outside Window — older than $cacheDays days', outside);
  }
}

void _writeCompactList(
  StringBuffer report,
  String title,
  List<FeedItem> items,
  DateTime now,
  int cacheDays,
) {
  report
    ..writeln('#### $title Details')
    ..writeln()
    ..writeln('| Date | Zone | Title | Id | URL |')
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final item in items) {
    report.writeln(
      '| ${_date(item.publishedAt)} | ${_zone(item.publishedAt, now, cacheDays)} | '
      '${_md(item.title ?? 'Untitled')} | `${_md(_identity(item))}` | ${_md(item.externalUrl)} |',
    );
  }
  report.writeln();
}

void _writeScFetchLog(
  StringBuffer report,
  List<Map<String, dynamic>> sink,
) {
  final collections = sink.where((r) => r['type'] == 'fetch_collection').toList();
  final drops = sink.where((r) => r['type'] == 'fetch_drop').toList();

  report
    ..writeln('#### SoundCloud Fetch Log')
    ..writeln()
    ..writeln(
      '_One row per SC API collection endpoint called. '
      '`items_received` = raw JSON objects before any parsing or date filter._',
    )
    ..writeln()
    ..writeln('| Endpoint | Pages | Items Received | Early Exit | Error |')
    ..writeln('| --- | ---: | ---: | --- | --- |');
  for (final row in collections) {
    final earlyExit = row['early_exit'] == true ? 'yes (all old)' : '-';
    final error = row['error']?.toString() ?? '-';
    report.writeln(
      '| `${_md(row['endpoint']?.toString() ?? '-')}` '
      '| ${row['pages_fetched'] ?? '-'} '
      '| ${row['items_received'] ?? '-'} '
      '| $earlyExit '
      '| ${_md(error)} |',
    );
  }
  if (collections.isEmpty) {
    report.writeln('| — | — | — | — | No fetch_collection entries |');
  }
  report.writeln();

  if (drops.isNotEmpty) {
    report
      ..writeln(
        '**Dropped playlists** (playlist title filter — uploader name not in title and not the tracked artist):',
      )
      ..writeln()
      ..writeln('| Id | Title | Uploader | Is Repost | raw\\_created\\_at |')
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final row in drops) {
      report.writeln(
        '| `${_md(row['id']?.toString() ?? '-')}` '
        '| ${_md(row['title']?.toString() ?? '-')} '
        '| ${_md(row['uploader']?.toString() ?? '-')} '
        '| ${row['is_repost'] == true ? 'yes' : 'no'} '
        '| ${_md(row['raw_created_at']?.toString() ?? '-')} |',
      );
    }
    report.writeln();
  }
}

void _writeYtFetchLog(
  StringBuffer report,
  List<Map<String, dynamic>> sink,
) {
  final metas = sink.where((r) => r['type'] == 'fetch_meta').toList();

  report
    ..writeln('#### YouTube Fetch Log')
    ..writeln()
    ..writeln(
      '_API path is tried first; RSS is used as fallback if the API key is '
      'missing or the API returns 0 items._',
    )
    ..writeln()
    ..writeln('| Path | Channel ID | Uploads Playlist | RSS URL | Items Received | Error |')
    ..writeln('| --- | --- | --- | --- | ---: | --- |');
  for (final row in metas) {
    report.writeln(
      '| ${_md(row['path']?.toString() ?? '-')} '
      '| `${_md(row['channel_id']?.toString() ?? '-')}` '
      '| `${_md(row['uploads_playlist_id']?.toString() ?? '-')}` '
      '| ${_md(row['rss_url']?.toString() ?? '-')} '
      '| ${row['items_received'] ?? '-'} '
      '| ${_md(row['error']?.toString() ?? '-')} |',
    );
  }
  if (metas.isEmpty) {
    report.writeln('| — | — | — | — | — | No fetch_meta entries |');
  }
  report.writeln();
}

void _writeScRawDatesTable(
  StringBuffer report,
  List<Map<String, dynamic>> sink,
) {
  // Skip metadata entries (fetch_collection, fetch_drop) — item rows have no 'type'.
  final items = sink.where((r) => r['type'] == null).toList();

  report
    ..writeln('#### SoundCloud Raw Date Fields')
    ..writeln()
    ..writeln(
      '_Shows every candidate date field the parser considered per item. '
      '`usedField` is the one that won the max-date selection._',
    )
    ..writeln()
    ..writeln(
      '| Id | Path | repost\\_created\\_at | release\\_ymd | release\\_date | display\\_date | created\\_at | usedField | resolvedDate |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  for (final row in items) {
    report.writeln(
      '| `${_md(row['id']?.toString() ?? '-')}` '
      '| ${_md(row['path']?.toString() ?? '-')} '
      '| ${_md(row['raw_repost_created_at']?.toString() ?? '-')} '
      '| ${_md(row['raw_release_ymd']?.toString() ?? '-')} '
      '| ${_md(row['raw_release_date']?.toString() ?? '-')} '
      '| ${_md(row['raw_display_date']?.toString() ?? '-')} '
      '| ${_md(row['raw_created_at']?.toString() ?? '-')} '
      '| **${_md(row['usedField']?.toString() ?? '-')}** '
      '| ${_md(row['resolvedDate']?.toString() ?? '-')} |',
    );
  }
  report.writeln();
}

void _writeYtRawDatesTable(
  StringBuffer report,
  List<Map<String, dynamic>> sink,
) {
  // Skip fetch_meta entries — item rows have no 'type'.
  final items = sink.where((r) => r['type'] == null).toList();

  report
    ..writeln('#### YouTube Raw Date Fields')
    ..writeln()
    ..writeln(
      '_API path exposes both `videoPublishedAt` and `snippet.publishedAt`. '
      'RSS path exposes only the `<published>` element._',
    )
    ..writeln()
    ..writeln(
      '| Id | Path | videoPublishedAt | snippetPublishedAt | rssPublished | usedField | resolvedDate |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
  for (final row in items) {
    report.writeln(
      '| `${_md(row['id']?.toString() ?? '-')}` '
      '| ${_md(row['path']?.toString() ?? '-')} '
      '| ${_md(row['raw_videoPublishedAt']?.toString() ?? '-')} '
      '| ${_md(row['raw_snippetPublishedAt']?.toString() ?? '-')} '
      '| ${_md(row['raw_rssPublished']?.toString() ?? '-')} '
      '| **${_md(row['usedField']?.toString() ?? '-')}** '
      '| ${_md(row['resolvedDate']?.toString() ?? '-')} |',
    );
  }
  report.writeln();
}

void _writeBcItemRawDatesTable(
  StringBuffer report,
  List<Map<String, dynamic>> sink,
) {
  report
    ..writeln('#### Bandcamp Per-Item Raw Date Fields')
    ..writeln()
    ..writeln(
      '_Per normalized FeedItem returned by `getFeed`. '
      '`json` path = tralbum API detail; `grid`/`overflow` = ld+json release page; `rss` = RSS pubDate._',
    )
    ..writeln()
    ..writeln(
      '| Id | Path | release\\_date | publish\\_date | modified\\_date | featured\\_date | mod\\_date | datePublished | pubDate | usedField | resolvedDate |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  for (final row in sink) {
    final path = row['path']?.toString() ?? '-';
    // json path uses detail keys; grid/overflow use datePublished; rss uses pubDate.
    final relDate = row['raw_release_date']?.toString() ?? '-';
    final pubDate = row['raw_publish_date']?.toString() ?? '-';
    final modDate = row['raw_modified_date']?.toString() ?? '-';
    final featDate = row['raw_featured_date']?.toString() ?? '-';
    final modDate2 = row['raw_mod_date']?.toString() ?? '-';
    final datePub = row['raw_datePublished']?.toString() ?? '-';
    final rssPub = row['raw_pubDate']?.toString() ?? '-';
    report.writeln(
      '| `${_md(row['id']?.toString() ?? '-')}` '
      '| ${_md(path)} '
      '| ${_md(relDate)} '
      '| ${_md(pubDate)} '
      '| ${_md(modDate)} '
      '| ${_md(featDate)} '
      '| ${_md(modDate2)} '
      '| ${_md(datePub)} '
      '| ${_md(rssPub)} '
      '| **${_md(row['usedField']?.toString() ?? '-')}** '
      '| ${_md(row['resolvedDate']?.toString() ?? '-')} |',
    );
  }
  report.writeln();
}

void _writeBcDebugSection(
  StringBuffer report,
  BcDebugReport bcReport,
  DateTime now,
  int cacheDays,
) {
  report.writeln('#### Bandcamp Raw Date Inspection');
  report.writeln();

  // ── Blob table ──────────────────────────────────────────────────────────────
  final blob = bcReport.blobEntries;
  final missedCount = blob.where((e) => e.processZone == 'missed').length;
  report
    ..writeln(
      '**Blob entries:** ${blob.length} total · '
      '${blob.where((e) => e.processZone == 'json').length} via tralbum API (0–39) · '
      '${blob.where((e) => e.processZone == 'overflow').length} via page fetch (40–79) · '
      '$missedCount missed (≥80)',
    )
    ..writeln()
    ..writeln(
      '_`json` = fetched via tralbum API · `overflow` = fetched via individual release page · `missed` = beyond 80-item cap, not processed_',
    )
    ..writeln();

  if (blob.isEmpty) {
    report
      ..writeln('No data-client-items blob found on /music page.')
      ..writeln();
  } else {
    report
      ..writeln(
        '| Pos | Zone | Title | Type | featured\\_date | mod\\_date | Age (featured) | Note |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | --- | --- |');
    for (final entry in blob) {
      final featuredIso = entry.featuredDate != null
          ? _date(entry.featuredDate!)
          : entry.rawFeaturedDt != null
          ? 'raw:${entry.rawFeaturedDt}'
          : '-';
      final modIso = entry.modDate != null
          ? _date(entry.modDate!)
          : entry.rawModDt != null
          ? 'raw:${entry.rawModDt}'
          : '-';
      final age = entry.featuredDate != null
          ? _zone(entry.featuredDate!, now, cacheDays)
          : '-';
      final note = entry.processZone == 'missed' ? '⚠ beyond cap' : '';
      report.writeln(
        '| ${entry.position} | ${entry.processZone} | ${_md(entry.title ?? '-')} | '
        '${_md(entry.type ?? '-')} | $featuredIso | $modIso | $age | $note |',
      );
    }
    report.writeln();
  }

  // ── Grid URLs ────────────────────────────────────────────────────────────────
  report.writeln('**Grid HTML URLs** (top ${bcReport.gridUrls.length}):');
  report.writeln();
  if (bcReport.gridUrls.isEmpty) {
    report
      ..writeln('No `<ol id="music-grid">` found.')
      ..writeln();
  } else {
    for (final url in bcReport.gridUrls) {
      report.writeln('- `${_md(url)}`');
    }
    report.writeln();
  }

  // ── RSS table ────────────────────────────────────────────────────────────────
  report
    ..writeln('**RSS /feed entries** (${bcReport.rssEntries.length}):')
    ..writeln();
  if (bcReport.rssEntries.isEmpty) {
    report
      ..writeln('No RSS items found.')
      ..writeln();
  } else {
    report
      ..writeln('| Raw pubDate | Parsed Date | Zone | Title |')
      ..writeln('| --- | --- | --- | --- |');
    for (final rss in bcReport.rssEntries) {
      final parsedIso = rss.pubDate != null ? _date(rss.pubDate!) : '-';
      final age = rss.pubDate != null
          ? _zone(rss.pubDate!, now, cacheDays)
          : '-';
      report.writeln(
        '| ${_md(rss.rawPubDate)} | $parsedIso | $age | ${_md(rss.title)} |',
      );
    }
    report.writeln();
  }
}

String? _sourceForPlatform(Map<String, dynamic> artist, String platform) {
  return switch (platform) {
    'soundcloud' => _firstNonEmpty([
      artist['soundcloud_url'],
      artist['soundcloud_username'],
    ]),
    'youtube' => _youtubeIdentifier(artist),
    'bandcamp' => artist['bandcamp_url'] as String?,
    _ => null,
  };
}

String? _youtubeIdentifier(Map<String, dynamic> artist) {
  final channelId = artist['youtube_channel_id'] as String?;
  final ytUrl = artist['youtube_url'] as String?;
  if (channelId != null && channelId.startsWith('UC')) return channelId;
  return _firstNonEmpty([ytUrl, channelId]);
}

String? _firstNonEmpty(List<dynamic> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String _artistName(Map<String, dynamic> artist) {
  return (artist['name'] as String?) ??
      (artist['display_name'] as String?) ??
      (artist['soundcloud_username'] as String?) ??
      'Unknown';
}

String _identity(FeedItem item) => '${item.platform}:${item.id}';

String _date(DateTime date) => date.toUtc().toIso8601String().split('T').first;

String _zone(DateTime publishedAt, DateTime now, int cacheDays) {
  final ageDays = _ageDays(publishedAt, now);
  if (ageDays <= _recentDays) return 'recent (${ageDays}d)';
  if (ageDays <= cacheDays) return 'archive (${ageDays}d)';
  return 'outside (${ageDays}d)';
}

String _zoneType(DateTime publishedAt, DateTime now, int cacheDays) {
  final ageDays = _ageDays(publishedAt, now);
  if (ageDays <= _recentDays) return 'recent';
  if (ageDays <= cacheDays) return 'archive';
  return 'outside';
}

int _ageDays(DateTime publishedAt, DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final publishedUtc = publishedAt.toUtc();
  final publishedDay = DateTime.utc(
    publishedUtc.year,
    publishedUtc.month,
    publishedUtc.day,
  );
  return today.difference(publishedDay).inDays;
}

int _duplicateCount(List<FeedItem> items) {
  final seen = <String>{};
  var duplicates = 0;
  for (final item in items) {
    if (!seen.add(_identity(item))) duplicates++;
  }
  return duplicates;
}

String _title(String platform) {
  return switch (platform) {
    'soundcloud' => 'SoundCloud',
    'youtube' => 'YouTube',
    'bandcamp' => 'Bandcamp',
    _ => platform,
  };
}

String _md(String value) {
  return value
      .replaceAll('|', r'\|')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .trim();
}

Future<void> _relaunchWithDotEnvIfNeeded(List<String> args) async {
  if (Platform.environment[_envLoadedFlag] == '1') return;
  if (Platform.environment['SUPABASE_URL'] != null &&
      Platform.environment['SUPABASE_SERVICE_KEY'] != null) {
    return;
  }

  final envFile = _findDotEnv();
  if (envFile == null) return;

  final env = Map<String, String>.from(Platform.environment)
    ..addAll(_readDotEnv(envFile))
    ..[_envLoadedFlag] = '1';

  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'bin/feed_audit.dart', ...args],
    workingDirectory: Directory.current.path,
    environment: env,
    runInShell: true,
  );
  process.stdout.pipe(stdout);
  process.stderr.pipe(stderr);
  exit(await process.exitCode);
}

File? _findDotEnv() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final candidate = File('${dir.path}${Platform.pathSeparator}.env');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

Map<String, String> _readDotEnv(File file) {
  final env = <String, String>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final index = line.indexOf('=');
    if (index <= 0) continue;
    final key = line.substring(0, index).trim();
    var value = line.substring(index + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    env[key] = value;
  }
  return env;
}

void _printUsage() {
  stdout.writeln('''
Xene feed audit

Run from packages/xene_backend:
  dart run bin/feed_audit.dart --preset dnb-foundations --platform all --live --out ../../audit_reports/dnb-foundations.md

Options:
  --preset <slug>       Audit a preset. If omitted, audits followed artists.
  --artist <text>       Filter artists by name/display_name substring.
  --platform <name>     soundcloud, youtube, bandcamp, or all. Repeatable.
  --live                Fetch live platform data and compare to Supabase.
  --user <id>           User id. Default: $_userIdDefault.
  --days <n>            Supabase/cache window. Default: $_cacheDaysDefault.
  --limit <n>           Rows shown per table. Default: 80.
  --max-artists <n>     Cap artist count for a smaller first pass.
  --out <path>          Write Markdown report to a file.
  --verbose             Include backend service logs.
  --help                Show this help.
''');
}

class _AuditOptions {
  _AuditOptions({
    required this.help,
    required this.userId,
    required this.preset,
    required this.artistQuery,
    required this.platforms,
    required this.live,
    required this.cacheDays,
    required this.limit,
    required this.artistLimit,
    required this.outPath,
    required this.verbose,
  });

  final bool help;
  final String userId;
  final String? preset;
  final String? artistQuery;
  final List<String> platforms;
  final bool live;
  final int cacheDays;
  final int limit;
  final int? artistLimit;
  final String? outPath;
  final bool verbose;

  String get scopeLabel {
    final parts = <String>[
      if (preset != null) 'preset `$preset`' else 'followed artists',
      if (artistQuery != null) 'artist filter `$artistQuery`',
      if (artistLimit != null) 'max artists $artistLimit',
    ];
    return parts.join(', ');
  }

  static _AuditOptions parse(List<String> args) {
    var help = false;
    var userId = _userIdDefault;
    String? preset;
    String? artistQuery;
    var live = false;
    var cacheDays = _cacheDaysDefault;
    var limit = 80;
    int? artistLimit;
    String? outPath;
    var verbose = false;
    final platforms = <String>{};

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String nextValue() {
        if (i + 1 >= args.length) {
          throw ArgumentError('Missing value for $arg');
        }
        return args[++i];
      }

      switch (arg) {
        case '--help':
        case '-h':
          help = true;
        case '--user':
          userId = nextValue();
        case '--preset':
          preset = nextValue();
        case '--artist':
          artistQuery = nextValue();
        case '--platform':
          final value = nextValue().toLowerCase();
          if (value == 'all') {
            platforms.addAll(_platforms);
          } else if (_platforms.contains(value)) {
            platforms.add(value);
          } else {
            throw ArgumentError('Unknown platform: $value');
          }
        case '--live':
          live = true;
        case '--days':
          cacheDays = int.parse(nextValue());
        case '--limit':
          limit = int.parse(nextValue());
        case '--max-artists':
          artistLimit = int.parse(nextValue());
        case '--out':
          outPath = nextValue();
        case '--verbose':
          verbose = true;
        default:
          throw ArgumentError('Unknown option: $arg');
      }
    }

    return _AuditOptions(
      help: help,
      userId: userId,
      preset: preset,
      artistQuery: artistQuery,
      platforms: platforms.isEmpty ? _platforms.toList() : platforms.toList(),
      live: live,
      cacheDays: cacheDays,
      limit: limit,
      artistLimit: artistLimit,
      outPath: outPath,
      verbose: verbose,
    );
  }
}
