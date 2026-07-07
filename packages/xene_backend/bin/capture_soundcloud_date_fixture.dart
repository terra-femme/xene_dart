import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xene_backend/src/services/soundcloud_date_resolver.dart';

const _defaultUrls = [
  'https://soundcloud.com/rangerrecords/sets/phrase-kill-plan-final-test',
  'https://soundcloud.com/phrasednb/sets/phrase-kill-plan-final-test',
];

Future<void> main(List<String> args) async {
  final write = args.contains('--write');
  final suppliedUrls = args.where((arg) => arg != '--write').toList();
  final urls = suppliedUrls.isEmpty ? _defaultUrls : suppliedUrls;
  final env = _loadEnv();
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'User-Agent': 'Mozilla/5.0 Xene SoundCloud date audit'},
    ),
  );
  final token = await _clientToken(dio, env);
  final outputDir = Directory('test/fixtures/soundcloud/date_baseline');

  for (final suppliedUrl in urls) {
    final canonicalUrl = await _canonicalUrl(dio, suppliedUrl);
    final page = await _publicPageObject(dio, canonicalUrl);
    final id = page?['id'];
    if (id == null) {
      stderr.writeln('No playlist/track hydration found: $canonicalUrl');
      exitCode = 1;
      continue;
    }
    final kind = page?['kind']?.toString();
    final resource = kind == 'track' ? 'tracks' : 'playlists';
    final response = await dio.get<Map<String, dynamic>>(
      'https://api.soundcloud.com/$resource/$id',
      options: Options(headers: {'Authorization': 'OAuth $token'}),
    );
    final official = _sanitize(response.data ?? const {});
    final publicDates = {
      'display_date': page?['display_date'],
      'release_date': page?['release_date'],
    };
    const resolver = SoundCloudDateResolver();
    final conflictReason = await _duplicatePlaylistConflict(
      dio,
      token,
      official,
    );
    final resolution = resolver.resolve(
      official,
      verifiedDisplayAt: resolver.parseDate(publicDates['display_date']),
      verifiedConflictReason: conflictReason,
      now: DateTime.now().toUtc(),
    );
    final fixture = {
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'canonical_url': canonicalUrl,
      'official_api': official,
      'public_page': publicDates,
      'resolution': {
        'legacy_published_at': resolution.legacyPublishedAt.toIso8601String(),
        'v2_published_at': resolution.publishedAt.toIso8601String(),
        'release_at': resolution.releaseAt?.toIso8601String(),
        'is_upcoming': resolution.isUpcoming,
        'date_source': resolution.dateSource,
        'date_confidence': resolution.confidence,
        'conflict_reason': resolution.conflictReason,
      },
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(fixture);
    if (!write) {
      stdout.writeln(encoded);
      continue;
    }
    outputDir.createSync(recursive: true);
    final slug = Uri.parse(
      canonicalUrl,
    ).pathSegments.where((part) => part.isNotEmpty).join('_');
    final file = File('${outputDir.path}/live_$slug.json');
    file.writeAsStringSync('$encoded\n');
    stdout.writeln('Wrote ${file.path}');
  }
}

Map<String, String> _loadEnv() {
  for (final candidate in [File('../../.env'), File('.env')]) {
    if (!candidate.existsSync()) continue;
    final values = <String, String>{};
    for (final raw in candidate.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator < 1) continue;
      values[line.substring(0, separator).trim()] = line
          .substring(separator + 1)
          .trim()
          .replaceAll(RegExp(r'''^["']|["']$'''), '');
    }
    return values;
  }
  throw StateError('Could not find the workspace .env file.');
}

Future<String> _clientToken(Dio dio, Map<String, String> env) async {
  final clientId = env['SC_CLIENT_ID'];
  final clientSecret = env['SC_CLIENT_SECRET'];
  if (clientId == null || clientSecret == null) {
    throw StateError('SC_CLIENT_ID and SC_CLIENT_SECRET are required.');
  }
  final basic = base64Encode(utf8.encode('$clientId:$clientSecret'));
  final response = await dio.post<Map<String, dynamic>>(
    'https://secure.soundcloud.com/oauth/token',
    data: {'grant_type': 'client_credentials'},
    options: Options(
      contentType: Headers.formUrlEncodedContentType,
      headers: {'Authorization': 'Basic $basic'},
    ),
  );
  return response.data!['access_token'] as String;
}

Future<String> _canonicalUrl(Dio dio, String suppliedUrl) async {
  final response = await dio.get<dynamic>(
    suppliedUrl,
    options: Options(responseType: ResponseType.plain),
  );
  final finalUri = response.realUri;
  return Uri(
    scheme: finalUri.scheme,
    host: finalUri.host,
    port: finalUri.hasPort ? finalUri.port : null,
    path: finalUri.path,
  ).toString();
}

Future<Map<String, dynamic>?> _publicPageObject(
  Dio dio,
  String canonicalUrl,
) async {
  final response = await dio.get<String>(
    canonicalUrl,
    options: Options(responseType: ResponseType.plain),
  );
  final html = response.data ?? '';
  final match = RegExp(
    r'window\.__sc_hydration\s*=\s*(\[.*?\]);\s*</script>',
    dotAll: true,
  ).firstMatch(html);
  if (match == null) return null;
  final hydration = jsonDecode(match.group(1)!) as List<dynamic>;
  for (final raw in hydration) {
    if (raw is! Map) continue;
    final entry = Map<String, dynamic>.from(raw);
    final data = entry['data'];
    if (data is Map &&
        (data['kind'] == 'playlist' || data['kind'] == 'track')) {
      return Map<String, dynamic>.from(data);
    }
  }
  return null;
}

Future<String?> _duplicatePlaylistConflict(
  Dio dio,
  String token,
  Map<String, dynamic> item,
) async {
  if (item['kind'] != 'playlist') return null;
  final sourceIds = _trackIds(item);
  if (sourceIds.isEmpty) return null;
  final query = (item['title']?.toString() ?? '')
      .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), ' ')
      .trim();
  if (query.isEmpty) return null;
  final response = await dio.get<Map<String, dynamic>>(
    'https://api.soundcloud.com/playlists',
    queryParameters: {'q': query, 'limit': 20, 'linked_partitioning': true},
    options: Options(headers: {'Authorization': 'OAuth $token'}),
  );
  final candidates = response.data?['collection'];
  if (candidates is! List) return null;
  for (final raw in candidates) {
    if (raw is! Map || raw['id']?.toString() == item['id']?.toString()) {
      continue;
    }
    final candidate = Map<String, dynamic>.from(raw);
    final candidateIds = _trackIds(candidate);
    if (candidateIds.length == sourceIds.length &&
        candidateIds.containsAll(sourceIds)) {
      const resolver = SoundCloudDateResolver();
      final candidateDate =
          resolver.parseDate(candidate['display_date']) ??
          resolver.parseDate(candidate['created_at']);
      if (candidateDate != null &&
          !candidateDate.isAfter(DateTime.now().toUtc())) {
        return 'duplicate_playlist_same_tracks_with_past_date';
      }
    }
  }
  return null;
}

Set<String> _trackIds(Map<String, dynamic> playlist) {
  final tracks = playlist['tracks'];
  if (tracks is! List) return const {};
  return tracks
      .whereType<Map>()
      .map((track) => track['id']?.toString())
      .whereType<String>()
      .toSet();
}

Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
  const fields = {
    'kind',
    'id',
    'title',
    'created_at',
    'display_date',
    'release_date',
    'release_year',
    'release_month',
    'release_day',
    'last_modified',
    'permalink_url',
    'track_count',
  };
  final result = <String, dynamic>{
    for (final field in fields)
      if (input.containsKey(field)) field: input[field],
  };
  final tracks = input['tracks'];
  if (tracks is List) {
    result['tracks'] = tracks.whereType<Map>().map((raw) {
      final track = Map<String, dynamic>.from(raw);
      return {
        for (final field in fields)
          if (track.containsKey(field)) field: track[field],
      };
    }).toList();
  }
  return result;
}
