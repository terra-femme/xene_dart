import 'package:freezed_annotation/freezed_annotation.dart';

part 'artist.freezed.dart';
part 'artist.g.dart';

@freezed
class Artist with _$Artist {
  const Artist._(); // Needed for custom methods

  const factory Artist({
    required String id,
    required String name,
    @Default('artist') String entityType,
    String? soundcloudUsername,
    String? soundcloudUrl,
    @Default('LOW') String soundcloudAuthority,
    String? instagramUsername,
    String? instagramUrl,
    @Default('LOW') String instagramAuthority,
    String? bandcampUrl,
    @Default('LOW') String bandcampAuthority,
    String? youtubeChannelId,
    String? youtubeUrl,
    @Default('LOW') String youtubeAuthority,
    String? twitchLogin,
    String? twitchUrl,
    @Default('LOW') String twitchAuthority,
    String? beatportArtistName,
    String? beatportArtistId,
    String? beatportUrl,
    @Default('LOW') String beatportAuthority,
    String? spotifyId,
    String? spotifyUrl,
    @Default('LOW') String spotifyAuthority,
    String? websiteUrl,
    String? twitterUsername,
    String? twitterUrl,
    @Default('LOW') String twitterAuthority,
    String? analysis,
    List<String>? soundcloudRepostLabels,
    @Default(false) bool manuallyVerified,
    required DateTime createdAt,
    @Default(0.0) double confidence,
    @Default('LOW') String identityConfidence,
    @Default('FRAGMENTED') String coverageLevel,
    @Default(false) bool conflictState,
    DateTime? lastDiscoveredAt,
  }) = _Artist;

  factory Artist.fromJson(Map<String, dynamic> json) => _$ArtistFromJson(json);

  bool get isLabel => entityType == 'label' || entityType == 'organization';
}
