import 'dart:async';
import 'dart:io';

import 'package:cron/cron.dart';
import 'package:logging/logging.dart';

import '../feed_cache.dart';
import '../database.dart';
import '../utils/audit_logger.dart';
import 'soundcloud_service.dart';
import 'youtube_service.dart';
import 'beatport_service.dart';
import 'bandcamp_service.dart';
import 'press_scout_service.dart';
import 'publication_poller_service.dart';
import 'capacity_service.dart';

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
    required this.capacity,
  });

  final DatabaseService db;
  final SoundCloudService soundcloud;
  final YouTubeService youtube;
  final BeatportService beatport;
  final BandcampService bandcamp;
  final PressScoutService pressScout;
  final PublicationPollerService publicationPoller;
  final CapacityService capacity;

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

    // 4. Beatport: DISABLED (will re-enable when adding as feed source)
    // _cron.schedule(Schedule.parse('0 0 * * *'), () async {
    //   _logger.info('[Scheduler] Starting Beatport Sync');
    //   final artists = await db.getArtists('local_user');
    //   for (final artist in artists) {
    //     final bpId = artist['beatport_artist_id'] as String?;
    //     if (bpId != null) {
    //       await beatport.getLabelReleases(
    //         bpId,
    //         labelName: artist['name'] as String? ?? 'Beatport',
    //       );
    //     }
    //   }
    // });

    // 5. Press scout: DISABLED (manual trigger via dashboard only)
    // _cron.schedule(Schedule.parse('0 */12 * * *'), () async {
    //   _logger.info('[Scheduler] Starting Press Scout');
    //   await pressScout.scoutArticlesForActiveArtists();
    // });

    // 6. Publication RSS poller: DISABLED (manual trigger via dashboard only)
    // _cron.schedule(Schedule.parse('0 */4 * * *'), () async {
    //   _logger.info('[Scheduler] Starting Publication RSS Poll');
    //   final result = await publicationPoller.pollAll();
    //   _logger.info(
    //     '[Scheduler] Publication RSS Poll complete: '
    //     'polled=${result['publications_polled']} '
    //     'succeeded=${result['succeeded']} '
    //     'failed=${result['failed']} '
    //     'articles=${result['articles_saved']}',
    //   );
    // });

    // 7. Capacity check: Every 6 hours — monitors user count and storage usage
    _cron.schedule(Schedule.parse('0 */6 * * *'), () async {
      _logger.info('[Scheduler] Starting Capacity Check');
      try {
        final status = await capacity.getStatus();
        _logger.info(
          '[Scheduler] Capacity check: users=${status.userCount}/${2000} (${status.userCapPercent.toStringAsFixed(1)}%) '
          'storage=${status.storageUsedMb.toStringAsFixed(1)}MB/${50}MB (${status.storageCapPercent.toStringAsFixed(1)}%)',
        );

        // Log alert if either threshold is exceeded
        if (status.userAlert != null) {
          unawaited(
            logSecurityEvent(
              db.client,
              action: 'capacity_alert_users',
              metadata: {
                'user_count': status.userCount,
                'user_cap_percent': status.userCapPercent,
                'alert_level': status.userAlert,
              },
            ),
          );
          _logger.warning(
            '[Scheduler] USER CAPACITY ALERT: ${status.userAlert} (${status.userCapPercent.toStringAsFixed(1)}%)',
          );
        }

        if (status.storageAlert != null) {
          unawaited(
            logSecurityEvent(
              db.client,
              action: 'capacity_alert_storage',
              metadata: {
                'storage_used_mb': status.storageUsedMb,
                'storage_cap_percent': status.storageCapPercent,
                'alert_level': status.storageAlert,
              },
            ),
          );
          _logger.warning(
            '[Scheduler] STORAGE CAPACITY ALERT: ${status.storageAlert} (${status.storageCapPercent.toStringAsFixed(1)}%)',
          );
        }
      } catch (e) {
        _logger.severe('[Scheduler] Capacity check failed: $e');
      }
    });

    // 8. Feed cache cleanup: Once daily at 3am (delete items older than 31 days)
    _cron.schedule(Schedule.parse('0 3 * * *'), () async {
      _logger.info('[Scheduler] Starting Feed Cache Cleanup');
      await db.deleteOldFeedItems(days: 31);
    });

    _logger.info('Tiered Scheduler Active (2 active jobs + 3 disabled/manual jobs registered).');
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
