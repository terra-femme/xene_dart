import 'package:cron/cron.dart';
import 'package:logging/logging.dart';
import 'soundcloud_service.dart';
import 'youtube_service.dart';
import 'beatport_service.dart';
import 'bandcamp_service.dart';
import '../database.dart';

final _logger = Logger('SchedulerService');

class SchedulerService {
  SchedulerService({
    required this.db,
    required this.soundcloud,
    required this.youtube,
    required this.beatport,
    required this.bandcamp,
  });

  final DatabaseService db;
  final SoundCloudService soundcloud;
  final YouTubeService youtube;
  final BeatportService beatport;
  final BandcampService bandcamp;

  final _cron = Cron();

  /// ELI5: Starting the "Alarm Clock" system.
  void start() {
    _logger.info('Starting Tiered Scheduler...');

    // 1. SoundCloud: Every 8 hours (3x/day)
    _cron.schedule(Schedule.parse('0 */8 * * *'), () async {
      _logger.info('[Scheduler] Starting SoundCloud Sync');
      final artists = await db.getArtists('local_user');
      for (final artist in artists) {
        final sc = artist['soundcloud_username'] as String?;
        if (sc != null) {
          await soundcloud.getTracks(sc, artist['name'] as String?);
        }
      }
    });

    // 2. Bandcamp: Every 6 hours (4x/day)
    _cron.schedule(Schedule.parse('0 */6 * * *'), () async {
      _logger.info('[Scheduler] Starting Bandcamp Sync');
      final artists = await db.getArtists('local_user');
      for (final artist in artists) {
        final bc = artist['bandcamp_url'] as String?;
        if (bc != null) {
          await bandcamp.getFeed(bc, artist['name'] as String? ?? 'Bandcamp');
        }
      }
    });

    // 3. YouTube: Every 12 hours (2x/day)
    _cron.schedule(Schedule.parse('0 */12 * * *'), () async {
      _logger.info('[Scheduler] Starting YouTube Sync');
      final artists = await db.getArtists('local_user');
      for (final artist in artists) {
        final yt = artist['youtube_channel_id'] as String? ?? artist['youtube_url'] as String?;
        if (yt != null) {
          await youtube.getVideos(yt, artist['name'] as String? ?? 'YouTube');
        }
      }
    });

    _logger.info('Tiered Scheduler Active.');
  }

  void stop() {
    _cron.close();
  }
}
