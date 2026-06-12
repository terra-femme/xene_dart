// Daily disappearing inbox models — plain immutable Dart classes (no Freezed/code-gen).
// Shape mirrors the daily_inbox.stations JSONB column from Supabase.

class DailyInboxMessage {
  const DailyInboxMessage({
    required this.id,
    required this.date,
    required this.generatedAt,
    required this.expiresAt,
    required this.stations,
  });

  final String id;
  final String date;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final List<DailyInboxStation> stations;

  bool get isActive => expiresAt.isAfter(DateTime.now().toUtc());

  Duration get timeRemaining {
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  factory DailyInboxMessage.fromJson(Map<String, dynamic> j) =>
      DailyInboxMessage(
        id: j['id'] as String,
        date: j['date'] as String,
        generatedAt: DateTime.parse(j['generated_at'] as String),
        expiresAt: DateTime.parse(j['expires_at'] as String),
        stations: (j['stations'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(DailyInboxStation.fromJson)
            .toList(),
      );
}

class DailyInboxStation {
  const DailyInboxStation({
    required this.slug,
    required this.name,
    required this.themeColor,
    required this.tracks,
  });

  final String slug;
  final String name;
  final String themeColor;
  final List<DailyInboxTrack> tracks;

  factory DailyInboxStation.fromJson(Map<String, dynamic> j) =>
      DailyInboxStation(
        slug: j['slug'] as String,
        name: j['name'] as String,
        themeColor: j['theme_color'] as String? ?? '#222222',
        tracks: (j['tracks'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(DailyInboxTrack.fromJson)
            .toList(),
      );
}

class DailyInboxTrack {
  const DailyInboxTrack({
    required this.title,
    required this.artistName,
    required this.platform,
    required this.contentType,
    required this.externalUrl,
    this.artworkUrl,
    required this.publishedAt,
    this.durationSeconds,
  });

  final String title;
  final String artistName;
  final String platform;
  final String contentType;
  final String externalUrl;
  final String? artworkUrl;
  final DateTime publishedAt;
  final int? durationSeconds;

  /// Whether this track can be saved to /user/saved (SC and YT only).
  bool get isSaveable => platform == 'soundcloud' || platform == 'youtube';

  String get durationLabel {
    if (durationSeconds == null) return '';
    final m = durationSeconds! ~/ 60;
    final s = durationSeconds! % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get platformLabel {
    switch (platform.toLowerCase()) {
      case 'soundcloud':
        return 'SoundCloud';
      case 'youtube':
        return 'YouTube';
      case 'bandcamp':
        return 'Bandcamp';
      case 'beatport':
        return 'Beatport';
      default:
        return platform;
    }
  }

  factory DailyInboxTrack.fromJson(Map<String, dynamic> j) => DailyInboxTrack(
    title: j['title'] as String? ?? 'Untitled',
    artistName: j['artist_name'] as String? ?? '',
    platform: j['platform'] as String? ?? 'soundcloud',
    contentType: j['content_type'] as String? ?? 'track',
    externalUrl: j['external_url'] as String,
    artworkUrl: j['artwork_url'] as String?,
    publishedAt: DateTime.parse(j['published_at'] as String),
    durationSeconds: (j['duration_seconds'] as num?)?.toInt(),
  );
}
