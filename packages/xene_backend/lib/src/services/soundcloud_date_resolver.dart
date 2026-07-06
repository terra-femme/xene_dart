class SoundCloudDateResolution {
  const SoundCloudDateResolution({
    required this.legacyPublishedAt,
    required this.publishedAt,
    required this.sourceCreatedAt,
    required this.displayAt,
    required this.releaseAt,
    required this.sourceLastModifiedAt,
    required this.dateSource,
    required this.confidence,
    required this.isUpcoming,
    this.conflictReason,
  });

  final DateTime legacyPublishedAt;
  final DateTime publishedAt;
  final DateTime? sourceCreatedAt;
  final DateTime? displayAt;
  final DateTime? releaseAt;
  final DateTime? sourceLastModifiedAt;
  final String dateSource;
  final String confidence;
  final bool isUpcoming;
  final String? conflictReason;
}

/// Pure SoundCloud date policy shared by production, diagnostics, and tests.
///
/// [legacy] intentionally preserves Xene's historical "latest candidate wins"
/// behavior. [resolve] separates public display time from declared release time.
class SoundCloudDateResolver {
  const SoundCloudDateResolver();

  DateTime legacy(
    Map<String, dynamic> item, {
    DateTime? repostedAt,
    required DateTime now,
  }) {
    if (repostedAt != null) return repostedAt;
    final candidates = <DateTime>[
      if (_releaseYmd(item) case final value?) value,
      for (final field in ['release_date', 'display_date', 'created_at'])
        if (parseDate(item[field]) case final value?) value,
    ];
    if (candidates.isEmpty) return now.toUtc();
    return candidates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  SoundCloudDateResolution resolve(
    Map<String, dynamic> item, {
    DateTime? repostedAt,
    DateTime? verifiedDisplayAt,
    String? verifiedConflictReason,
    required DateTime now,
  }) {
    final utcNow = now.toUtc();
    final createdAt = parseDate(item['created_at']);
    final apiDisplayAt = parseDate(item['display_date']);
    final displayAt = verifiedDisplayAt ?? apiDisplayAt;
    final releaseAt = _releaseYmd(item) ?? parseDate(item['release_date']);
    final lastModifiedAt = parseDate(item['last_modified']);
    final legacyAt = legacy(item, repostedAt: repostedAt, now: utcNow);

    final publicAt = repostedAt ?? displayAt ?? createdAt ?? utcNow;
    final source = repostedAt != null
        ? 'reposted_at'
        : verifiedDisplayAt != null
        ? 'verified_display_date'
        : apiDisplayAt != null
        ? 'display_date'
        : createdAt != null
        ? 'created_at'
        : 'first_seen_at';

    final conflictReason = verifiedConflictReason;
    final isUpcoming =
        repostedAt == null &&
        releaseAt != null &&
        releaseAt.isAfter(utcNow) &&
        conflictReason == null;

    return SoundCloudDateResolution(
      legacyPublishedAt: legacyAt,
      publishedAt: publicAt,
      sourceCreatedAt: createdAt,
      displayAt: displayAt,
      releaseAt: releaseAt,
      sourceLastModifiedAt: lastModifiedAt,
      dateSource: source,
      confidence: conflictReason == null
          ? verifiedDisplayAt != null
                ? 'high'
                : 'medium'
          : 'conflicting',
      isUpcoming: isUpcoming,
      conflictReason: conflictReason,
    );
  }

  DateTime? parseDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(trimmed);
    if (dateOnly != null) {
      return dateOnlyUtc(
        int.parse(dateOnly.group(1)!),
        int.parse(dateOnly.group(2)!),
        int.parse(dateOnly.group(3)!),
      );
    }
    try {
      return DateTime.parse(trimmed.replaceAll('/', '-')).toUtc();
    } catch (_) {
      final match = RegExp(
        r'^(\d{4})/(\d{2})/(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s+([+-])(\d{2})(\d{2})$',
      ).firstMatch(trimmed);
      if (match == null) return null;
      final sign = match.group(7) == '-' ? -1 : 1;
      final offset = Duration(
        hours: sign * int.parse(match.group(8)!),
        minutes: sign * int.parse(match.group(9)!),
      );
      return DateTime.utc(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      ).subtract(offset);
    }
  }

  DateTime dateOnlyUtc(int year, int month, int day) =>
      DateTime.utc(year, month, day, 12);

  DateTime? _releaseYmd(Map<String, dynamic> item) {
    final year = item['release_year'];
    final month = item['release_month'];
    final day = item['release_day'];
    if (year is! int || month is! int || day is! int) return null;
    try {
      return dateOnlyUtc(year, month, day);
    } catch (_) {
      return null;
    }
  }
}
