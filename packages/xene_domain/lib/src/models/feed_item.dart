import 'package:freezed_annotation/freezed_annotation.dart';

part 'feed_item.freezed.dart';
part 'feed_item.g.dart';

@freezed
class FeedItem with _$FeedItem {
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
    int? playCount,
    int? likeCount,
    String? waveformUrl,
    int? durationSeconds,
    int? trackCount,
  }) = _FeedItem;

  factory FeedItem.fromJson(Map<String, dynamic> json) => _$FeedItemFromJson(json);
}
