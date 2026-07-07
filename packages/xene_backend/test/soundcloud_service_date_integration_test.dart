import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';

class _MockDatabase extends Mock implements DatabaseService {}

class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.playlist);

  final Map<String, dynamic> playlist;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (options.uri.host == 'soundcloud.com') {
      final hydration = jsonEncode([
        {
          'hydratable': 'playlist',
          'data': {
            ...playlist,
            'display_date': '2026-01-28T02:47:51Z',
            'release_date': '2026-11-07T00:00:00Z',
          },
        },
      ]);
      return ResponseBody.fromString(
        '<script>window.__sc_hydration = $hydration;</script>',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
        },
      );
    }
    if (path == '/resolve') {
      return _json({
        'id': 42,
        'username': 'Ranger Records',
        'avatar_url': null,
      });
    }
    if (path == '/users/42/playlists') {
      return _json({
        'collection': [playlist],
        'next_href': null,
      });
    }
    if (path == '/playlists') {
      return _json({
        'collection': [
          {
            'kind': 'playlist',
            'id': 2112403133,
            'title': 'Phrase - Kill Plan / Final Test (Ranger Records)',
            'created_at': '2025/11/11 04:28:30 +0000',
            'tracks': [
              {'id': 2200721063},
              {'id': 2210240468},
            ],
          },
          playlist,
        ],
      });
    }
    if (path == '/users/42/tracks' ||
        path == '/users/42/reposts/tracks' ||
        path == '/users/42/reposts/playlists') {
      return _json({'collection': <dynamic>[], 'next_href': null});
    }
    return _json({'error': 'not found', 'path': path}, status: 404);
  }

  ResponseBody _json(Object value, {int status = 200}) {
    return ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _MockDatabase db;
  late Map<String, dynamic> playlist;

  setUp(() {
    db = _MockDatabase();
    when(
      () => db.getSystemCache(any()),
    ).thenAnswer((_) async => {'access_token': 'fixture-token'});
    when(() => db.saveFeedItems(any())).thenAnswer((_) async {});

    playlist = {
      'kind': 'playlist',
      'id': 2181845408,
      'title': 'Phrase - Kill Plan / Final Test [RNGR006]',
      'created_at': '2026/01/28 02:47:51 +0000',
      'display_date': null,
      'release_date': null,
      'release_year': 2026,
      'release_month': 11,
      'release_day': 7,
      'last_modified': '2026/01/28 02:49:34 +0000',
      'permalink_url':
          'https://soundcloud.com/rangerrecords/sets/phrase-kill-plan-final-test',
      'track_count': 2,
      'duration': 120000,
      'user': {'username': 'Ranger Records'},
      'tracks': [
        {
          'id': 2200721063,
          'created_at': '2025/10/28 12:57:48 +0000',
          'display_date': '2025-11-04T18:00:38Z',
        },
        {
          'id': 2210240468,
          'created_at': '2025/11/10 18:50:05 +0000',
          'display_date': '2025-11-10T18:50:05Z',
        },
      ],
    };
  });

  SoundCloudService service({required bool v2, required DateTime now}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.soundcloud.com'))
      ..httpClientAdapter = _FixtureAdapter(playlist);
    return SoundCloudService(db, dio: dio, now: () => now, dateResolverV2: v2);
  }

  test('legacy service retains Ranger as a future-dated item', () async {
    final items = await service(
      v2: false,
      now: DateTime.utc(2026, 7, 6),
    ).getTracks('rangerrecords', 'Ranger Records');

    expect(items, hasLength(1));
    expect(items.single.publishedAt, DateTime.utc(2026, 11, 7, 12));
    expect(items.single.isUpcoming, isFalse);
  });

  test(
    'V2 uses verified public date and marks conflict, without dropping',
    () async {
      final items = await service(
        v2: true,
        now: DateTime.utc(2026, 1, 29),
      ).getTracks('rangerrecords', 'Ranger Records');

      expect(items, hasLength(1));
      expect(items.single.publishedAt, DateTime.utc(2026, 1, 28, 2, 47, 51));
      expect(items.single.releaseAt, DateTime.utc(2026, 11, 7, 12));
      expect(items.single.isUpcoming, isFalse);
      expect(items.single.dateConfidence, 'conflicting');
      verify(() => db.saveFeedItems(any())).called(1);
    },
  );

  test(
    'V2 backfills a stale future row even when no longer in feed window',
    () async {
      final items = await service(
        v2: true,
        now: DateTime.utc(2026, 7, 6),
      ).getTracks('rangerrecords', 'Ranger Records');

      expect(items, isEmpty);
      final captured =
          verify(() => db.saveFeedItems(captureAny())).captured.single
              as List<Map<String, dynamic>>;
      expect(captured, hasLength(1));
      expect(captured.single['published_at'], '2026-01-28T02:47:51.000Z');
      expect(captured.single['date_confidence'], 'conflicting');
      expect(captured.single['is_upcoming'], isFalse);
    },
  );
}
