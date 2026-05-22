// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'artist.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Artist _$ArtistFromJson(Map<String, dynamic> json) => _Artist(
  id: json['id'] as String,
  name: json['name'] as String,
  entityType: json['entityType'] as String? ?? 'artist',
  soundcloudUsername: json['soundcloudUsername'] as String?,
  soundcloudUrl: json['soundcloudUrl'] as String?,
  soundcloudAuthority: json['soundcloudAuthority'] as String? ?? 'LOW',
  bandcampUrl: json['bandcampUrl'] as String?,
  bandcampAuthority: json['bandcampAuthority'] as String? ?? 'LOW',
  youtubeChannelId: json['youtubeChannelId'] as String?,
  youtubeUrl: json['youtubeUrl'] as String?,
  youtubeAuthority: json['youtubeAuthority'] as String? ?? 'LOW',
  twitchLogin: json['twitchLogin'] as String?,
  twitchUrl: json['twitchUrl'] as String?,
  twitchAuthority: json['twitchAuthority'] as String? ?? 'LOW',
  beatportArtistName: json['beatportArtistName'] as String?,
  beatportArtistId: json['beatportArtistId'] as String?,
  beatportUrl: json['beatportUrl'] as String?,
  beatportAuthority: json['beatportAuthority'] as String? ?? 'LOW',
  spotifyId: json['spotifyId'] as String?,
  spotifyUrl: json['spotifyUrl'] as String?,
  spotifyAuthority: json['spotifyAuthority'] as String? ?? 'LOW',
  websiteUrl: json['websiteUrl'] as String?,
  twitterUsername: json['twitterUsername'] as String?,
  twitterUrl: json['twitterUrl'] as String?,
  twitterAuthority: json['twitterAuthority'] as String? ?? 'LOW',
  instagramUsername: json['instagramUsername'] as String?,
  instagramUrl: json['instagramUrl'] as String?,
  instagramAuthority: json['instagramAuthority'] as String? ?? 'LOW',
  appleMusiciId: json['appleMusiciId'] as String?,
  deezerId: json['deezerId'] as String?,
  tidalId: json['tidalId'] as String?,
  analysis: json['analysis'] as String?,
  edges:
      (json['edges'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList() ??
      const [],
  soundcloudRepostLabels: (json['soundcloudRepostLabels'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  manuallyVerified: json['manuallyVerified'] as bool? ?? false,
  createdAt: DateTime.parse(json['createdAt'] as String),
  confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
  identityConfidence: json['identityConfidence'] as String? ?? 'LOW',
  coverageLevel: json['coverageLevel'] as String? ?? 'FRAGMENTED',
  conflictState: json['conflictState'] as bool? ?? false,
  lastDiscoveredAt: json['lastDiscoveredAt'] == null
      ? null
      : DateTime.parse(json['lastDiscoveredAt'] as String),
);

Map<String, dynamic> _$ArtistToJson(_Artist instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'entityType': instance.entityType,
  'soundcloudUsername': instance.soundcloudUsername,
  'soundcloudUrl': instance.soundcloudUrl,
  'soundcloudAuthority': instance.soundcloudAuthority,
  'bandcampUrl': instance.bandcampUrl,
  'bandcampAuthority': instance.bandcampAuthority,
  'youtubeChannelId': instance.youtubeChannelId,
  'youtubeUrl': instance.youtubeUrl,
  'youtubeAuthority': instance.youtubeAuthority,
  'twitchLogin': instance.twitchLogin,
  'twitchUrl': instance.twitchUrl,
  'twitchAuthority': instance.twitchAuthority,
  'beatportArtistName': instance.beatportArtistName,
  'beatportArtistId': instance.beatportArtistId,
  'beatportUrl': instance.beatportUrl,
  'beatportAuthority': instance.beatportAuthority,
  'spotifyId': instance.spotifyId,
  'spotifyUrl': instance.spotifyUrl,
  'spotifyAuthority': instance.spotifyAuthority,
  'websiteUrl': instance.websiteUrl,
  'twitterUsername': instance.twitterUsername,
  'twitterUrl': instance.twitterUrl,
  'twitterAuthority': instance.twitterAuthority,
  'instagramUsername': instance.instagramUsername,
  'instagramUrl': instance.instagramUrl,
  'instagramAuthority': instance.instagramAuthority,
  'appleMusiciId': instance.appleMusiciId,
  'deezerId': instance.deezerId,
  'tidalId': instance.tidalId,
  'analysis': instance.analysis,
  'edges': instance.edges,
  'soundcloudRepostLabels': instance.soundcloudRepostLabels,
  'manuallyVerified': instance.manuallyVerified,
  'createdAt': instance.createdAt.toIso8601String(),
  'confidence': instance.confidence,
  'identityConfidence': instance.identityConfidence,
  'coverageLevel': instance.coverageLevel,
  'conflictState': instance.conflictState,
  'lastDiscoveredAt': instance.lastDiscoveredAt?.toIso8601String(),
};
