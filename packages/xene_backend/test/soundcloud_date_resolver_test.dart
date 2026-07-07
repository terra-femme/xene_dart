import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xene_backend/src/services/soundcloud_date_resolver.dart';

void main() {
  const resolver = SoundCloudDateResolver();
  final now = DateTime.utc(2026, 7, 6);

  Map<String, dynamic> fixture(String name) {
    final file = File('test/fixtures/soundcloud/date_baseline/$name.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json;
  }

  test('legacy behavior: future release metadata wins for Ranger', () {
    final json = fixture('ranger_phrase_playlist');
    final item = json['official_api'] as Map<String, dynamic>;
    expect(resolver.legacy(item, now: now), DateTime.utc(2026, 11, 7, 12));
  });

  test('legacy behavior: Phrase falls back to playlist creation', () {
    final json = fixture('phrase_playlist');
    final item = json['official_api'] as Map<String, dynamic>;
    expect(
      resolver.legacy(item, now: now),
      DateTime.utc(2025, 11, 11, 4, 28, 30),
    );
  });

  test('V2 uses verified display date and rejects conflicting future date', () {
    final json = fixture('ranger_phrase_playlist');
    final item = json['official_api'] as Map<String, dynamic>;
    final page = json['public_page'] as Map<String, dynamic>;
    final result = resolver.resolve(
      item,
      verifiedDisplayAt: resolver.parseDate(page['display_date']),
      verifiedConflictReason: 'duplicate_playlist_same_tracks_with_past_date',
      now: now,
    );

    expect(result.publishedAt, DateTime.utc(2026, 1, 28, 2, 47, 51));
    expect(result.releaseAt, DateTime.utc(2026, 11, 7, 12));
    expect(result.isUpcoming, isFalse);
    expect(result.confidence, 'conflicting');
  });

  test('V2 retains a credible future release separately', () {
    final item = <String, dynamic>{
      'created_at': '2026-07-01T10:00:00Z',
      'display_date': '2026-07-01T10:00:00Z',
      'release_date': '2026-08-14',
      'tracks': <dynamic>[],
    };
    final result = resolver.resolve(item, now: now);
    expect(result.publishedAt, DateTime.utc(2026, 7, 1, 10));
    expect(result.releaseAt, DateTime.utc(2026, 8, 14, 12));
    expect(result.isUpcoming, isTrue);
  });

  test('old playlist tracks alone do not prove a release-date conflict', () {
    final item = <String, dynamic>{
      'kind': 'playlist',
      'created_at': '2026-03-04T09:45:54Z',
      'release_date': '2026-12-25',
      'tracks': [
        {'id': 1, 'created_at': '2026-01-01T00:00:00Z'},
        {'id': 2, 'created_at': '2026-02-01T00:00:00Z'},
      ],
    };
    final result = resolver.resolve(
      item,
      verifiedDisplayAt: DateTime.utc(2026, 3, 4, 9, 45, 54),
      now: now,
    );
    expect(result.isUpcoming, isTrue);
    expect(result.conflictReason, isNull);
  });

  test('repost date controls both legacy and V2 feed placement', () {
    final item = <String, dynamic>{
      'created_at': '2025-01-01T00:00:00Z',
      'release_date': '2025-02-01',
    };
    final repostedAt = DateTime.utc(2026, 7, 5, 18);
    expect(resolver.legacy(item, repostedAt: repostedAt, now: now), repostedAt);
    expect(
      resolver.resolve(item, repostedAt: repostedAt, now: now).publishedAt,
      repostedAt,
    );
  });

  test('malformed and missing dates fall back to frozen now', () {
    final result = resolver.resolve(<String, dynamic>{
      'created_at': 'not-a-date',
    }, now: now);
    expect(result.publishedAt, now);
    expect(result.dateSource, 'first_seen_at');
  });
}
