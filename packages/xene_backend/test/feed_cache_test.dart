import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xene_domain/xene_domain.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/feed_cache.dart';

class MockDatabaseService extends Mock implements DatabaseService {}

// A minimal valid DB row matching the feed_items schema.
Map<String, dynamic> _makeRow(String id, String artistName) => {
  'internal_id': id,
  'platform': 'soundcloud',
  'artist_name': artistName,
  'content_type': 'track',
  'title': 'Test Track',
  'body': null,
  'media_url': null,
  'artwork_url': null,
  'external_url': 'https://soundcloud.com/test/$id',
  'published_at': DateTime.now().toUtc().toIso8601String(),
  'duration_seconds': 300,
  'play_count': null,
  'like_count': null,
  'waveform_url': null,
  'track_count': null,
};

FeedItem _makeItem(String id, String artistName) => FeedItem(
  id: id,
  platform: 'soundcloud',
  artistName: artistName,
  contentType: 'track',
  externalUrl: 'https://soundcloud.com/test/$id',
  publishedAt: DateTime.now().toUtc(),
);

void main() {
  late MockDatabaseService db;

  setUp(() {
    db = MockDatabaseService();
    when(
      () => db.getCachedFeedItems(
        platform: any(named: 'platform'),
        artistName: any(named: 'artistName'),
        days: any(named: 'days'),
      ),
    ).thenAnswer((_) async => []);
    when(() => db.getSystemCache(any())).thenAnswer((_) async => null);
    when(() => db.setLastPolled(any(), any())).thenAnswer((_) async {});
    when(
      () => db.setSystemCache(any(), any(), expiresAt: any(named: 'expiresAt')),
    ).thenAnswer((_) async => true);
    when(() => db.deleteSystemCache(any())).thenAnswer((_) async {});
  });

  group('fetchWithCache', () {
    const platform = 'soundcloud';
    const artist = 'Bicep';
    const ttl = Duration(hours: 6);

    test('cache HIT — returns DB rows, skips live fetch', () async {
      // last_polled is 1 minute ago → fresh
      when(() => db.getLastPolled(platform, artist)).thenAnswer(
        (_) async =>
            DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );

      final row = _makeRow('track_001', artist);
      when(
        () => db.getCachedFeedItems(
          platform: platform,
          artistName: artist,
          days: any(named: 'days'),
        ),
      ).thenAnswer((_) async => [row]);

      var liveCalled = false;
      final result = await fetchWithCache(db, platform, artist, ttl, () async {
        liveCalled = true;
        return [];
      });

      expect(
        liveCalled,
        isFalse,
        reason: 'Live fetch must NOT fire on cache hit',
      );
      expect(result.length, equals(1));
      expect(result.first.id, equals('track_001'));
      verifyNever(() => db.setLastPolled(any(), any()));
    });

    test(
      'cache MISS (never polled) — fires live fetch, stamps last_polled',
      () async {
        when(
          () => db.getLastPolled(platform, artist),
        ).thenAnswer((_) async => null);
        when(() => db.setLastPolled(platform, artist)).thenAnswer((_) async {});

        final liveItem = _makeItem('track_live', artist);
        final result = await fetchWithCache(
          db,
          platform,
          artist,
          ttl,
          () async => [liveItem],
        );

        expect(result.length, equals(1));
        expect(result.first.id, equals('track_live'));
        verify(() => db.setLastPolled(platform, artist)).called(1);
      },
    );

    test('cache MISS (stale) — fires live fetch, stamps last_polled', () async {
      // last_polled is 7 hours ago → stale vs 6h TTL
      when(() => db.getLastPolled(platform, artist)).thenAnswer(
        (_) async => DateTime.now().toUtc().subtract(const Duration(hours: 7)),
      );
      when(() => db.setLastPolled(platform, artist)).thenAnswer((_) async {});

      final liveItem = _makeItem('track_stale', artist);
      final result = await fetchWithCache(
        db,
        platform,
        artist,
        ttl,
        () async => [liveItem],
      );

      expect(result.first.id, equals('track_stale'));
      verify(() => db.setLastPolled(platform, artist)).called(1);
    });

    test('live fetch failure — serves stale rows instead of empty', () async {
      when(
        () => db.getLastPolled(platform, artist),
      ).thenAnswer((_) async => null);

      final staleRow = _makeRow('stale_001', artist);
      when(
        () => db.getCachedFeedItems(
          platform: platform,
          artistName: artist,
          days: any(named: 'days'),
        ),
      ).thenAnswer((_) async => [staleRow]);

      // Live fetch throws
      final result = await fetchWithCache(db, platform, artist, ttl, () async {
        throw Exception('API timeout');
      });

      expect(result.length, equals(1));
      expect(result.first.id, equals('stale_001'));
      verifyNever(() => db.setLastPolled(any(), any()));
    });

    test('live fetch returns empty — stamps verified-empty marker', () async {
      when(
        () => db.getLastPolled(platform, artist),
      ).thenAnswer((_) async => null);

      final result = await fetchWithCache(
        db,
        platform,
        artist,
        ttl,
        () async => [],
      );

      expect(result, isEmpty);
      verify(() => db.setLastPolled(platform, artist)).called(1);
      verify(
        () => db.setSystemCache(
          'feed_empty_window:$platform:$artist:31d',
          any(),
          expiresAt: any(named: 'expiresAt'),
        ),
      ).called(1);
    });

    test('cache HIT with 0 rows — falls through to live fetch', () async {
      // Fresh timestamp but no rows in DB (artist was added after last poll)
      when(() => db.getLastPolled(platform, artist)).thenAnswer(
        (_) async =>
            DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
      when(
        () => db.getCachedFeedItems(
          platform: platform,
          artistName: artist,
          days: any(named: 'days'),
        ),
      ).thenAnswer((_) async => []);
      when(() => db.setLastPolled(platform, artist)).thenAnswer((_) async {});

      final liveItem = _makeItem('track_fallthrough', artist);
      var liveCalled = false;
      final result = await fetchWithCache(db, platform, artist, ttl, () async {
        liveCalled = true;
        return [liveItem];
      });

      expect(
        liveCalled,
        isTrue,
        reason: 'Must fall through to live fetch when rows are empty',
      );
      expect(result.first.id, equals('track_fallthrough'));
    });
  });

  group('feedItemFromRow', () {
    test('maps all snake_case DB columns to FeedItem fields', () {
      final row = {
        'internal_id': 'abc123',
        'platform': 'soundcloud',
        'artist_name': 'Bicep',
        'content_type': 'track',
        'title': 'Rain',
        'body': 'A description',
        'media_url': 'https://cdn.example.com/media.mp3',
        'artwork_url': 'https://cdn.example.com/art.jpg',
        'external_url': 'https://soundcloud.com/bicep/rain',
        'published_at': '2024-01-15T12:00:00.000Z',
        'duration_seconds': 240,
        'play_count': 1000,
        'like_count': 50,
        'waveform_url': 'https://cdn.example.com/wave.png',
        'track_count': null,
      };

      final item = feedItemFromRow(row);

      expect(item, isNotNull);
      expect(item!.id, equals('abc123'));
      expect(item.artistName, equals('Bicep'));
      expect(item.mediaUrl, equals('https://cdn.example.com/media.mp3'));
      expect(item.waveformUrl, equals('https://cdn.example.com/wave.png'));
      expect(item.durationSeconds, equals(240));
      expect(item.publishedAt, equals(DateTime.utc(2024, 1, 15, 12)));
    });

    test('returns null for malformed row', () {
      final item = feedItemFromRow({'bad': 'data'});
      expect(item, isNull);
    });
  });
}
