import 'package:freezed_annotation/freezed_annotation.dart';

part 'feed_item.freezed.dart';
part 'feed_item.g.dart';

@freezed
abstract class FeedItem with _$FeedItem {
  const factory FeedItem({
    required String id,
    required String platform,
    required String artistName,
    required String contentType,
    String? title,
    String? body,
    String? mediaUrl,
    String? artworkUrl,
    required String externalUrl,
    required DateTime publishedAt,
    DateTime? sourceCreatedAt,
    DateTime? displayAt,
    DateTime? releaseAt,
    DateTime? sourceLastModifiedAt,
    String? dateSource,
    String? dateConfidence,
    String? dateConflictReason,
    @Default(false) bool isUpcoming,
    int? playCount,
    int? likeCount,
    String? waveformUrl,
    int? durationSeconds,
    int? trackCount,
    @Default(false) bool isNew,
  }) = _FeedItem;

  factory FeedItem.fromJson(Map<String, dynamic> json) =>
      _$FeedItemFromJson(json);
}

extension FeedItemTimeline on FeedItem {
  DateTime get timelineAt =>
      isUpcoming && releaseAt != null ? releaseAt! : publishedAt;
}
