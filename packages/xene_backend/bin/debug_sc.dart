import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:xene_backend/src/services/soundcloud_date_resolver.dart';

const _dateResolver = SoundCloudDateResolver();

/// Standalone diagnostic tool to inspect raw SoundCloud API responses.
/// Usage:
///   dart bin/debug_sc.dart <track_or_playlist_url>
///   dart bin/debug_sc.dart --profile <artist_profile_url> [title_search]
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart bin/debug_sc.dart <soundcloud_url>');
    print(
      '       dart bin/debug_sc.dart --profile <artist_profile_url> [title_search]',
    );
    print(
      'Example: dart bin/debug_sc.dart https://soundcloud.com/nixxyrain/absent-out-of-touch',
    );
    exit(1);
  }

  final inspectProfile = args.first == '--profile';
  final url = inspectProfile ? args[1] : args[0];
  final titleSearch = inspectProfile && args.length > 2
      ? args.sublist(2).join(' ').toLowerCase()
      : null;

  // 1. Load .env from the root of the monorepo.
  // Assuming the script is run from 'packages/xene_backend'
  final envFile = File('../../.env');
  if (!envFile.existsSync()) {
    print('Error: .env file not found at ${envFile.absolute.path}');
    print(
      'Please ensure you are running this script from the "packages/xene_backend" directory.',
    );
    exit(1);
  }

  final env = <String, String>{};
  for (var line in envFile.readAsLinesSync()) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split('=');
    if (parts.length >= 2) {
      env[parts[0].trim()] = parts.sublist(1).join('=').trim();
    }
  }

  final clientId = env['SC_CLIENT_ID'];
  final clientSecret = env['SC_CLIENT_SECRET'];

  if (clientId == null || clientSecret == null) {
    print('Error: SC_CLIENT_ID or SC_CLIENT_SECRET not found in .env');
    exit(1);
  }

  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.soundcloud.com',
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ),
  );

  print('Authenticating with SoundCloud...');
  try {
    final authString = base64Encode(utf8.encode('$clientId:$clientSecret'));
    final tokenResponse = await dio.post<Map<String, dynamic>>(
      'https://secure.soundcloud.com/oauth/token',
      data: {'grant_type': 'client_credentials'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Authorization': 'Basic $authString'},
      ),
    );

    final token = tokenResponse.data!['access_token'] as String;
    print('Authentication successful.\n');

    if (url.startsWith('/')) {
      print('Fetching API Path: $url');
      final response = await dio.get<dynamic>(
        url,
        queryParameters: {'linked_partitioning': true},
        options: Options(headers: {'Authorization': 'OAuth $token'}),
      );

      final encoder = JsonEncoder.withIndent('  ');
      print('\n--- API RESPONSE ---');
      print(encoder.convert(response.data));
      print('--- END API RESPONSE ---\n');
      return;
    }

    print('Resolving URL: $url');
    final response = await dio.get<Map<String, dynamic>>(
      '/resolve',
      queryParameters: {'url': url},
      options: Options(headers: {'Authorization': 'OAuth $token'}),
    );

    final data = response.data!;

    if (inspectProfile || data['kind'] == 'user') {
      await _inspectProfile(
        dio: dio,
        token: token,
        user: data,
        titleSearch: titleSearch,
      );
      return;
    }

    final encoder = JsonEncoder.withIndent('  ');
    print('\n--- RAW JSON OUTPUT ---');
    print(encoder.convert(data));
    print('--- END RAW JSON OUTPUT ---\n');

    // Quick analysis
    if (data['kind'] == 'track' || data['kind'] == 'playlist') {
      print('--- DATE ANALYSIS ---');
      print('created_at:   ${data['created_at']}');
      print('display_date: ${data['display_date']}');
      print('release_date: ${data['release_date']}');
      print(
        'release:      ${data['release_year']}/${data['release_month']}/${data['release_day']}',
      );
      print('---------------------\n');
    }
  } catch (e) {
    if (e is DioException) {
      print('Error fetching data: ${e.message}');
      if (e.response != null) {
        print('Status: ${e.response?.statusCode}');
        print('Response Body: ${e.response?.data}');
      }
    } else {
      print('An unexpected error occurred: $e');
    }
    exit(1);
  }
}

Future<void> _inspectProfile({
  required Dio dio,
  required String token,
  required Map<String, dynamic> user,
  String? titleSearch,
}) async {
  final userId = user['id'];
  final username = user['username'];
  final permalink = user['permalink'];
  final permalinkUrl = user['permalink_url'];

  print('--- PROFILE ---');
  print('id:            $userId');
  print('username:      $username');
  print('permalink:     $permalink');
  print('permalink_url: $permalinkUrl');
  if (titleSearch != null) print('title search:  $titleSearch');
  print('---------------\n');

  final collections = <String, List<dynamic>>{
    'own tracks': await _getCollection(dio, token, '/users/$userId/tracks'),
    'own playlists': await _getCollection(
      dio,
      token,
      '/users/$userId/playlists',
    ),
    'track reposts': await _getCollection(
      dio,
      token,
      '/users/$userId/reposts/tracks',
    ),
    'playlist reposts': await _getCollection(
      dio,
      token,
      '/users/$userId/reposts/playlists',
    ),
  };

  for (final entry in collections.entries) {
    print('=== ${entry.key.toUpperCase()} (${entry.value.length}) ===');
    final rows = <_DateRow>[];
    for (final raw in entry.value) {
      final row = _dateRow(entry.key, raw);
      if (row != null) rows.add(row);
    }
    rows.sort((a, b) => b.feedAt.compareTo(a.feedAt));

    final matching = titleSearch == null
        ? rows.take(12).toList()
        : rows
              .where((r) => r.title.toLowerCase().contains(titleSearch))
              .toList();

    if (matching.isEmpty) {
      print(titleSearch == null ? '(no rows)' : '(no title matches)');
    }
    for (final row in matching.take(30)) {
      _printRow(row);
    }
    print('');
  }
}

Future<List<dynamic>> _getCollection(Dio dio, String token, String path) async {
  const pageLimit = 50;
  const maxPages = 10;
  final items = <dynamic>[];
  String? nextPath = path;
  Map<String, dynamic>? queryParameters = {
    'linked_partitioning': true,
    'limit': pageLimit,
  };

  for (var page = 0; page < maxPages && nextPath != null; page++) {
    final response = await dio.get<dynamic>(
      nextPath,
      queryParameters: queryParameters,
      options: Options(headers: {'Authorization': 'OAuth $token'}),
    );
    final data = response.data;
    if (data is Map && data.containsKey('collection')) {
      final collection = data['collection'] as List<dynamic>? ?? [];
      items.addAll(collection);
      final nextHref = data['next_href'] as String?;
      if (nextHref == null || nextHref.isEmpty) break;
      final nextUri = Uri.parse(nextHref);
      nextPath = nextUri.path;
      queryParameters = nextUri.queryParameters;
    } else if (data is List) {
      items.addAll(data);
      break;
    } else {
      break;
    }
  }

  return items;
}

_DateRow? _dateRow(String source, dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final isTrackRepost = raw['type'] == 'track-repost' || raw['track'] != null;
  final isPlaylistRepost =
      raw['type'] == 'playlist-repost' || raw['playlist'] != null;
  final isRepost = isTrackRepost || isPlaylistRepost;
  final item = isTrackRepost
      ? raw['track']
      : isPlaylistRepost
      ? raw['playlist']
      : raw;
  if (item is! Map<String, dynamic>) return null;

  final feedAt = isRepost
      ? _parseSoundCloudDate(raw['created_at']) ?? _parsePublicTrackDate(item)
      : _parsePublicTrackDate(item);

  return _DateRow(
    source: source,
    kind: item['kind']?.toString() ?? 'unknown',
    id: item['id']?.toString() ?? '',
    title: item['title']?.toString() ?? '',
    user:
        (item['user'] is Map ? item['user']['username'] : null)?.toString() ??
        '',
    url: item['permalink_url']?.toString() ?? '',
    wrapperCreatedAt: raw['created_at']?.toString(),
    itemCreatedAt: item['created_at']?.toString(),
    displayDate: item['display_date']?.toString(),
    releaseDate: item['release_date']?.toString(),
    releaseYmd:
        '${item['release_year']}/${item['release_month']}/${item['release_day']}',
    feedAt: feedAt,
    isRepost: isRepost,
  );
}

DateTime _parsePublicTrackDate(Map<String, dynamic> item) {
  return _dateResolver.legacy(item, now: DateTime.now().toUtc());
}

DateTime? _parseSoundCloudDate(Object? value) => _dateResolver.parseDate(value);

void _printRow(_DateRow row) {
  final ageDays = DateTime.now().toUtc().difference(row.feedAt).inDays;
  final bucket = ageDays <= 7
      ? 'RECENT'
      : ageDays <= 31
      ? 'ARCHIVE'
      : 'OUT';
  print('[${row.source}] ${row.kind} ${row.isRepost ? 'REPOST' : 'OWN'}');
  print('  title:       ${row.title}');
  print('  user:        ${row.user}');
  print('  id:          ${row.id}');
  print('  url:         ${row.url}');
  print(
    '  feedAt:      ${row.feedAt.toIso8601String()} ($ageDays days, $bucket)',
  );
  print('  raw wrapper: ${row.wrapperCreatedAt}');
  print('  raw item:    ${row.itemCreatedAt}');
  print('  display:     ${row.displayDate}');
  print('  release:     ${row.releaseDate} / ${row.releaseYmd}');
}

class _DateRow {
  final String source;
  final String kind;
  final String id;
  final String title;
  final String user;
  final String url;
  final String? wrapperCreatedAt;
  final String? itemCreatedAt;
  final String? displayDate;
  final String? releaseDate;
  final String releaseYmd;
  final DateTime feedAt;
  final bool isRepost;

  _DateRow({
    required this.source,
    required this.kind,
    required this.id,
    required this.title,
    required this.user,
    required this.url,
    required this.wrapperCreatedAt,
    required this.itemCreatedAt,
    required this.displayDate,
    required this.releaseDate,
    required this.releaseYmd,
    required this.feedAt,
    required this.isRepost,
  });
}
