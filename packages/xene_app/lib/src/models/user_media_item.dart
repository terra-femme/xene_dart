/// Shared data shape for queue items, saved items, and history items.
/// Each maps directly to its Supabase table row.

class QueueItem {
  const QueueItem({
    required this.id,
    required this.platform,
    required this.externalUrl,
    required this.position,
    this.trackId,
    this.title,
    this.artistName,
    this.artworkUrl,
    this.durationSeconds,
  });

  final String id;
  final String platform; // 'soundcloud' | 'youtube'
  final String externalUrl;
  final String? trackId;
  final String? title;
  final String? artistName;
  final String? artworkUrl;
  final int? durationSeconds;
  final int position;

  factory QueueItem.fromJson(Map<String, dynamic> j) => QueueItem(
    id: j['id'] as String,
    platform: j['platform'] as String,
    externalUrl: j['external_url'] as String,
    trackId: j['track_id'] as String?,
    title: j['title'] as String?,
    artistName: j['artist_name'] as String?,
    artworkUrl: j['artwork_url'] as String?,
    durationSeconds: j['duration_seconds'] as int?,
    position: j['position'] as int,
  );

  Map<String, dynamic> toPostBody() => {
    'platform': platform,
    'external_url': externalUrl,
    if (trackId != null) 'track_id': trackId,
    if (title != null) 'title': title,
    if (artistName != null) 'artist_name': artistName,
    if (artworkUrl != null) 'artwork_url': artworkUrl,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
  };
}

class SavedItem {
  const SavedItem({
    required this.id,
    required this.platform,
    required this.externalUrl,
    required this.savedAt,
    required this.expiresAt,
    this.trackId,
    this.title,
    this.artistName,
    this.artworkUrl,
    this.durationSeconds,
  });

  final String id;
  final String platform;
  final String externalUrl;
  final String? trackId;
  final String? title;
  final String? artistName;
  final String? artworkUrl;
  final int? durationSeconds;
  final DateTime savedAt;
  final DateTime expiresAt;

  int get daysRemaining =>
      expiresAt.difference(DateTime.now()).inDays.clamp(0, 31);

  factory SavedItem.fromJson(Map<String, dynamic> j) => SavedItem(
    id: j['id'] as String,
    platform: j['platform'] as String,
    externalUrl: j['external_url'] as String,
    trackId: j['track_id'] as String?,
    title: j['title'] as String?,
    artistName: j['artist_name'] as String?,
    artworkUrl: j['artwork_url'] as String?,
    durationSeconds: j['duration_seconds'] as int?,
    savedAt: DateTime.parse(j['saved_at'] as String),
    expiresAt: DateTime.parse(j['expires_at'] as String),
  );

  Map<String, dynamic> toPostBody() => {
    'platform': platform,
    'external_url': externalUrl,
    if (trackId != null) 'track_id': trackId,
    if (title != null) 'title': title,
    if (artistName != null) 'artist_name': artistName,
    if (artworkUrl != null) 'artwork_url': artworkUrl,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
  };
}

class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.platform,
    required this.externalUrl,
    required this.playedAt,
    this.trackId,
    this.title,
    this.artistName,
    this.artworkUrl,
    this.durationSeconds,
  });

  final String id;
  final String platform;
  final String externalUrl;
  final String? trackId;
  final String? title;
  final String? artistName;
  final String? artworkUrl;
  final int? durationSeconds;
  final DateTime playedAt;

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
    id: j['id'] as String,
    platform: j['platform'] as String,
    externalUrl: j['external_url'] as String,
    trackId: j['track_id'] as String?,
    title: j['title'] as String?,
    artistName: j['artist_name'] as String?,
    artworkUrl: j['artwork_url'] as String?,
    durationSeconds: j['duration_seconds'] as int?,
    playedAt: DateTime.parse(j['played_at'] as String),
  );

  Map<String, dynamic> toPostBody() => {
    'platform': platform,
    'external_url': externalUrl,
    if (trackId != null) 'track_id': trackId,
    if (title != null) 'title': title,
    if (artistName != null) 'artist_name': artistName,
    if (artworkUrl != null) 'artwork_url': artworkUrl,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
  };
}
