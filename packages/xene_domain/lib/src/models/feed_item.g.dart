// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'feed_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FeedItem _$FeedItemFromJson(Map<String, dynamic> json) => _FeedItem(
  id: json['id'] as String,
  platform: json['platform'] as String,
  artistName: json['artistName'] as String,
  contentType: json['contentType'] as String,
  title: json['title'] as String?,
  body: json['body'] as String?,
  mediaUrl: json['mediaUrl'] as String?,
  artworkUrl: json['artworkUrl'] as String?,
  externalUrl: json['externalUrl'] as String,
  publishedAt: DateTime.parse(json['publishedAt'] as String),
  sourceCreatedAt: json['sourceCreatedAt'] == null
      ? null
      : DateTime.parse(json['sourceCreatedAt'] as String),
  displayAt: json['displayAt'] == null
      ? null
      : DateTime.parse(json['displayAt'] as String),
  releaseAt: json['releaseAt'] == null
      ? null
      : DateTime.parse(json['releaseAt'] as String),
  sourceLastModifiedAt: json['sourceLastModifiedAt'] == null
      ? null
      : DateTime.parse(json['sourceLastModifiedAt'] as String),
  dateSource: json['dateSource'] as String?,
  dateConfidence: json['dateConfidence'] as String?,
  dateConflictReason: json['dateConflictReason'] as String?,
  isUpcoming: json['isUpcoming'] as bool? ?? false,
  playCount: (json['playCount'] as num?)?.toInt(),
  likeCount: (json['likeCount'] as num?)?.toInt(),
  waveformUrl: json['waveformUrl'] as String?,
  durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
  trackCount: (json['trackCount'] as num?)?.toInt(),
  isNew: json['isNew'] as bool? ?? false,
);

Map<String, dynamic> _$FeedItemToJson(_FeedItem instance) => <String, dynamic>{
  'id': instance.id,
  'platform': instance.platform,
  'artistName': instance.artistName,
  'contentType': instance.contentType,
  'title': instance.title,
  'body': instance.body,
  'mediaUrl': instance.mediaUrl,
  'artworkUrl': instance.artworkUrl,
  'externalUrl': instance.externalUrl,
  'publishedAt': instance.publishedAt.toIso8601String(),
  'sourceCreatedAt': instance.sourceCreatedAt?.toIso8601String(),
  'displayAt': instance.displayAt?.toIso8601String(),
  'releaseAt': instance.releaseAt?.toIso8601String(),
  'sourceLastModifiedAt': instance.sourceLastModifiedAt?.toIso8601String(),
  'dateSource': instance.dateSource,
  'dateConfidence': instance.dateConfidence,
  'dateConflictReason': instance.dateConflictReason,
  'isUpcoming': instance.isUpcoming,
  'playCount': instance.playCount,
  'likeCount': instance.likeCount,
  'waveformUrl': instance.waveformUrl,
  'durationSeconds': instance.durationSeconds,
  'trackCount': instance.trackCount,
  'isNew': instance.isNew,
};
