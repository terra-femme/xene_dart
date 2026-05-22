import 'dart:io';

import 'package:cron/cron.dart';
import 'package:logging/logging.dart';

import '../feed_cache.dart';
import '../database.dart';
import '../repositories/publication_repository.dart';
import 'soundcloud_service.dart';
import 'youtube_service.dart';
import 'beatport_service.dart';
import 'bandcamp_service.dart';
import 'press_scout_service.dart';
import 'publication_poller_service.dart';

final _logger = Logger('SchedulerService');

const _youtubeRefreshTtl = Duration(hours: 24);
const _youtubeDefaultBatchSize = 10;

class SchedulerService {
  SchedulerService({
    required this.db,
    required this.soundcloud,
    required this.youtube,
    required this.beatport,
    required this.bandcamp,
    required this.pressScout,
    required this.publicationPoller,
    required this.publicationRepo,
  });

  final DatabaseService db;
  final SoundCloudService soundcloud;
  final YouTubeService youtube;
  final BeatportService beatport;
  final BandcampService bandcamp;
  final PressScoutService pressScout;
  final PublicationPollerService publicationPoller;
  final PublicationRepository publicationRepo;

  final _cron = Cron();

  void start() {
    _logger.info('Starting Tiered Scheduler...');

    // Bandcamp warmup: 10s after startup — serial across artists (same as cron job)
    // so last_polled is stamped before the first user request arrives.
    // Without this, a fresh backend start triggers live BC scrapes on the first
    // request, which can exceed the frontend receive timeout.
    Future<void>.delayed(const Duration(seconds: 10), () async {
      _logger.info('[Scheduler] Startup Bandcamp warmup starting');
      try {
        final artists = await db.getArtists('local_user');
        for (final artist in artists) {
          final bc = artist['bandcamp_url'] as String?;
          final name = artist['name'] as String? ?? 'Bandcamp';
          if (bc != null) {
            await fetchWithCache(
              db,
              'bandcamp',
              name,
              const Duration(hours: 24),
              () => bandcamp.getFeed(bc, name),
              cacheDays: 31,
            );
          }
        }
        _logger.info('[Scheduler] Startup Bandcamp warmup done');
      } catch (e) {
        _logger.warning('[Scheduler] Startup Bandcamp warmup failed: $e');
      }
    });

    // Run press scout once 30 seconds after startup so articles populate
    // immediately on first boot instead of waiting up to 12 hours for cron.
    Future<void>.delayed(const Duration(seconds: 30), () async {
      _logger.info('[Scheduler] Startup press scout warmup starting');
      try {
        await pressScout.scoutArticlesForActiveArtists();
        _logger.info('[Scheduler] Startup press scout warmup done');
      } catch (e) {
        _logger.warning('[Scheduler] Startup press scout warmup failed: $e');
      }
    });

    // Run publication RSS poller 60 seconds after startup.
    // Gated by PUBLICATION_STARTUP_POLL=true so dev restarts don't trigger
    // unnecessary re-polls. Set the env var in production only.
    if (Platform.environment['PUBLICATION_STARTUP_POLL'] == 'true') {
      Future<void>.delayed(const Duration(seconds: 60), () async {
        _logger.info('[Scheduler] Startup publication poller warmup starting');
        try {
          final result = await publicationPoller.pollAll();
          _logger.info(
            '[Scheduler] Startup publication poller warmup done: '
            'polled=${result['publications_polled']} '
            'articles=${result['articles_saved']}',
          );
        } catch (e) {
          _logger.warning(
            '[Scheduler] Startup publication poller warmup failed: $e',
          );
        }
      });
    }

    // 1. SoundCloud: Every 8 hours (3x/day)
    // Fix B: use fetchWithCache so last_polled is stamped automatically —
    // consistent with merged.dart's TTL gate.
    _cron.schedule(Schedule.parse('0 */8 * * *'), () async {
      _logger.info('[Scheduler] Starting SoundCloud Sync');
      final artists = await db.getArtists('local_user');
      for (final artist in artists) {
        final scUrl = artist['soundcloud_url'] as String?;
        final scUsername = artist['soundcloud_username'] as String?;
        final sc = (scUrl != null && scUrl.isNotEmpty) ? scUrl : scUsername;
        final name = artist['name'] as String? ?? '';
        if (sc != null) {
          await fetchWithCache(
            db,
            'soundcloud',
            name,
            const Duration(hours: 6),
            () => soundcloud.getTracks(sc, name),
          );
        }
      }
    });

    // 2. Bandcamp: Every 6 hours (4x/day)
    // Fix B: use fetchWithCache so last_polled is stamped automatically —
    // consistent with merged.dart's TTL gate.
    _cron.schedule(Schedule.parse('0 */6 * * *'), () async {
      _logger.info('[Scheduler] Starting Bandcamp Sync');
      final artists = await db.getArtists('local_user');
      for (final artist in artists) {
        final bc = artist['bandcamp_url'] as String?;
        final name = artist['name'] as String? ?? 'Bandcamp';
        if (bc != null) {
          await fetchWithCache(
            db,
            'bandcamp',
            name,
            const Duration(hours: 24),
            () => bandcamp.getFeed(bc, name),
            cacheDays: 31,
          );
        }
      }
    });

    // 3. YouTube: Every 12 hours, but only refreshes stale artists and caps
    // each run so API quota usage spreads out instead of spiking.
    _cron.schedule(Schedule.parse('0 */12 * * *'), () async {
      _logger.info('[Scheduler] Starting YouTube Sync');
      final artists = await db.getArtists('local_user');
      final candidates = <_YouTubeRefreshCandidate>[];
      for (final artist in artists) {
        final name = artist['name'] as String? ?? 'YouTube';
        final yt =
            artist['youtube_channel_id'] as String? ??
            artist['youtube_url'] as String?;
        if (yt == null || yt.isEmpty) continue;

        final lastPolled = await db.getLastPolled('youtube', name);
        final isFresh =
            lastPolled != null &&
            DateTime.now().toUtc().difference(lastPolled) < _youtubeRefreshTtl;
        if (isFresh) continue;

        candidates.add(
          _YouTubeRefreshCandidate(
            name: name,
            identifier: yt,
            lastPolled: lastPolled,
          ),
        );
      }

      candidates.sort((a, b) {
        final aTime =
            a.lastPolled ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final bTime =
            b.lastPolled ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        return aTime.compareTo(bTime);
      });

      final batchSize =
          int.tryParse(
            Platform.environment['YOUTUBE_REFRESH_BATCH_SIZE'] ?? '',
          ) ??
          int.tryParse(
            Platform.environment['XENE_YOUTUBE_REFRESH_BATCH_SIZE'] ?? '',
          ) ??
          _youtubeDefaultBatchSize;
      final batch = candidates.take(batchSize.clamp(1, 100).toInt()).toList();
      _logger.info(
        '[Scheduler] YouTube Sync candidates=${candidates.length} batch=${batch.length} ttl=${_youtubeRefreshTtl.inHours}h',
      );

      for (final candidate in batch) {
        await fetchWithCache(
          db,
          'youtube',
          candidate.name,
          _youtubeRefreshTtl,
          () => youtube.getVideos(candidate.identifier, candidate.name),
        );
      }
    });

    // 4. Beatport: Once daily at midnight
    _cron.schedule(Schedule.parse('0 0 * * *'), () async {
      _logger.info('[Scheduler] Starting Beatport Sync');
      final artists = await db.getArtists('local_user');
      for (final artist in artists) {
        final bpId = artist['beatport_artist_id'] as String?;
        if (bpId != null) {
          await beatport.getLabelReleases(
            bpId,
            labelName: artist['name'] as String? ?? 'Beatport',
          );
        }
      }
    });

    // 5. Press scout: Twice daily at noon and midnight (staggered from cleanup)
    _cron.schedule(Schedule.parse('0 */12 * * *'), () async {
      _logger.info('[Scheduler] Starting Press Scout');
      await pressScout.scoutArticlesForActiveArtists();
    });

    // 6. Publication RSS poller: Every 4 hours (6x/day)
    // Serial execution per PublicationPollerService design — one feed at a time.
    _cron.schedule(Schedule.parse('0 */4 * * *'), () async {
      _logger.info('[Scheduler] Starting Publication RSS Poll');
      final result = await publicationPoller.pollAll();
      _logger.info(
        '[Scheduler] Publication RSS Poll complete: '
        'polled=${result['publications_polled']} '
        'succeeded=${result['succeeded']} '
        'failed=${result['failed']} '
        'articles=${result['articles_saved']}',
      );
    });

    // 7. Feed cache cleanup: Once daily at 3am (delete items older than 31 days)
    //    Also purges expired publication articles in the same window.
    _cron.schedule(Schedule.parse('0 3 * * *'), () async {
      _logger.info('[Scheduler] Starting Feed Cache Cleanup');
      await db.deleteOldFeedItems(days: 31);
      final deleted = await publicationRepo.deleteExpiredArticles();
      _logger.info(
        '[Scheduler] Expired publication articles deleted: $deleted',
      );
    });

    _logger.info('Tiered Scheduler Active (7 jobs registered).');
  }

  void stop() {
    _cron.close();
  }
}

class _YouTubeRefreshCandidate {
  const _YouTubeRefreshCandidate({
    required this.name,
    required this.identifier,
    required this.lastPolled,
  });

  final String name;
  final String identifier;
  final DateTime? lastPolled;
}
