// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'feed_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FeedItem {

 String get id; String get platform; String get artistName; String get contentType; String? get title; String? get body; String? get mediaUrl; String? get artworkUrl; String get externalUrl; DateTime get publishedAt; int? get playCount; int? get likeCount; String? get waveformUrl; int? get durationSeconds; int? get trackCount; bool get isNew;
/// Create a copy of FeedItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeedItemCopyWith<FeedItem> get copyWith => _$FeedItemCopyWithImpl<FeedItem>(this as FeedItem, _$identity);

  /// Serializes this FeedItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeedItem&&(identical(other.id, id) || other.id == id)&&(identical(other.platform, platform) || other.platform == platform)&&(identical(other.artistName, artistName) || other.artistName == artistName)&&(identical(other.contentType, contentType) || other.contentType == contentType)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.mediaUrl, mediaUrl) || other.mediaUrl == mediaUrl)&&(identical(other.artworkUrl, artworkUrl) || other.artworkUrl == artworkUrl)&&(identical(other.externalUrl, externalUrl) || other.externalUrl == externalUrl)&&(identical(other.publishedAt, publishedAt) || other.publishedAt == publishedAt)&&(identical(other.playCount, playCount) || other.playCount == playCount)&&(identical(other.likeCount, likeCount) || other.likeCount == likeCount)&&(identical(other.waveformUrl, waveformUrl) || other.waveformUrl == waveformUrl)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&(identical(other.trackCount, trackCount) || other.trackCount == trackCount)&&(identical(other.isNew, isNew) || other.isNew == isNew));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,platform,artistName,contentType,title,body,mediaUrl,artworkUrl,externalUrl,publishedAt,playCount,likeCount,waveformUrl,durationSeconds,trackCount,isNew);

@override
String toString() {
  return 'FeedItem(id: $id, platform: $platform, artistName: $artistName, contentType: $contentType, title: $title, body: $body, mediaUrl: $mediaUrl, artworkUrl: $artworkUrl, externalUrl: $externalUrl, publishedAt: $publishedAt, playCount: $playCount, likeCount: $likeCount, waveformUrl: $waveformUrl, durationSeconds: $durationSeconds, trackCount: $trackCount, isNew: $isNew)';
}


}

/// @nodoc
abstract mixin class $FeedItemCopyWith<$Res>  {
  factory $FeedItemCopyWith(FeedItem value, $Res Function(FeedItem) _then) = _$FeedItemCopyWithImpl;
@useResult
$Res call({
 String id, String platform, String artistName, String contentType, String? title, String? body, String? mediaUrl, String? artworkUrl, String externalUrl, DateTime publishedAt, int? playCount, int? likeCount, String? waveformUrl, int? durationSeconds, int? trackCount, bool isNew
});




}
/// @nodoc
class _$FeedItemCopyWithImpl<$Res>
    implements $FeedItemCopyWith<$Res> {
  _$FeedItemCopyWithImpl(this._self, this._then);

  final FeedItem _self;
  final $Res Function(FeedItem) _then;

/// Create a copy of FeedItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? platform = null,Object? artistName = null,Object? contentType = null,Object? title = freezed,Object? body = freezed,Object? mediaUrl = freezed,Object? artworkUrl = freezed,Object? externalUrl = null,Object? publishedAt = null,Object? playCount = freezed,Object? likeCount = freezed,Object? waveformUrl = freezed,Object? durationSeconds = freezed,Object? trackCount = freezed,Object? isNew = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,platform: null == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String,artistName: null == artistName ? _self.artistName : artistName // ignore: cast_nullable_to_non_nullable
as String,contentType: null == contentType ? _self.contentType : contentType // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,body: freezed == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String?,mediaUrl: freezed == mediaUrl ? _self.mediaUrl : mediaUrl // ignore: cast_nullable_to_non_nullable
as String?,artworkUrl: freezed == artworkUrl ? _self.artworkUrl : artworkUrl // ignore: cast_nullable_to_non_nullable
as String?,externalUrl: null == externalUrl ? _self.externalUrl : externalUrl // ignore: cast_nullable_to_non_nullable
as String,publishedAt: null == publishedAt ? _self.publishedAt : publishedAt // ignore: cast_nullable_to_non_nullable
as DateTime,playCount: freezed == playCount ? _self.playCount : playCount // ignore: cast_nullable_to_non_nullable
as int?,likeCount: freezed == likeCount ? _self.likeCount : likeCount // ignore: cast_nullable_to_non_nullable
as int?,waveformUrl: freezed == waveformUrl ? _self.waveformUrl : waveformUrl // ignore: cast_nullable_to_non_nullable
as String?,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,trackCount: freezed == trackCount ? _self.trackCount : trackCount // ignore: cast_nullable_to_non_nullable
as int?,isNew: null == isNew ? _self.isNew : isNew // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [FeedItem].
extension FeedItemPatterns on FeedItem {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FeedItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FeedItem() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FeedItem value)  $default,){
final _that = this;
switch (_that) {
case _FeedItem():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FeedItem value)?  $default,){
final _that = this;
switch (_that) {
case _FeedItem() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String platform,  String artistName,  String contentType,  String? title,  String? body,  String? mediaUrl,  String? artworkUrl,  String externalUrl,  DateTime publishedAt,  int? playCount,  int? likeCount,  String? waveformUrl,  int? durationSeconds,  int? trackCount,  bool isNew)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FeedItem() when $default != null:
return $default(_that.id,_that.platform,_that.artistName,_that.contentType,_that.title,_that.body,_that.mediaUrl,_that.artworkUrl,_that.externalUrl,_that.publishedAt,_that.playCount,_that.likeCount,_that.waveformUrl,_that.durationSeconds,_that.trackCount,_that.isNew);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String platform,  String artistName,  String contentType,  String? title,  String? body,  String? mediaUrl,  String? artworkUrl,  String externalUrl,  DateTime publishedAt,  int? playCount,  int? likeCount,  String? waveformUrl,  int? durationSeconds,  int? trackCount,  bool isNew)  $default,) {final _that = this;
switch (_that) {
case _FeedItem():
return $default(_that.id,_that.platform,_that.artistName,_that.contentType,_that.title,_that.body,_that.mediaUrl,_that.artworkUrl,_that.externalUrl,_that.publishedAt,_that.playCount,_that.likeCount,_that.waveformUrl,_that.durationSeconds,_that.trackCount,_that.isNew);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String platform,  String artistName,  String contentType,  String? title,  String? body,  String? mediaUrl,  String? artworkUrl,  String externalUrl,  DateTime publishedAt,  int? playCount,  int? likeCount,  String? waveformUrl,  int? durationSeconds,  int? trackCount,  bool isNew)?  $default,) {final _that = this;
switch (_that) {
case _FeedItem() when $default != null:
return $default(_that.id,_that.platform,_that.artistName,_that.contentType,_that.title,_that.body,_that.mediaUrl,_that.artworkUrl,_that.externalUrl,_that.publishedAt,_that.playCount,_that.likeCount,_that.waveformUrl,_that.durationSeconds,_that.trackCount,_that.isNew);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FeedItem implements FeedItem {
  const _FeedItem({required this.id, required this.platform, required this.artistName, required this.contentType, this.title, this.body, this.mediaUrl, this.artworkUrl, required this.externalUrl, required this.publishedAt, this.playCount, this.likeCount, this.waveformUrl, this.durationSeconds, this.trackCount, this.isNew = false});
  factory _FeedItem.fromJson(Map<String, dynamic> json) => _$FeedItemFromJson(json);

@override final  String id;
@override final  String platform;
@override final  String artistName;
@override final  String contentType;
@override final  String? title;
@override final  String? body;
@override final  String? mediaUrl;
@override final  String? artworkUrl;
@override final  String externalUrl;
@override final  DateTime publishedAt;
@override final  int? playCount;
@override final  int? likeCount;
@override final  String? waveformUrl;
@override final  int? durationSeconds;
@override final  int? trackCount;
@override@JsonKey() final  bool isNew;

/// Create a copy of FeedItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FeedItemCopyWith<_FeedItem> get copyWith => __$FeedItemCopyWithImpl<_FeedItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FeedItemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FeedItem&&(identical(other.id, id) || other.id == id)&&(identical(other.platform, platform) || other.platform == platform)&&(identical(other.artistName, artistName) || other.artistName == artistName)&&(identical(other.contentType, contentType) || other.contentType == contentType)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.mediaUrl, mediaUrl) || other.mediaUrl == mediaUrl)&&(identical(other.artworkUrl, artworkUrl) || other.artworkUrl == artworkUrl)&&(identical(other.externalUrl, externalUrl) || other.externalUrl == externalUrl)&&(identical(other.publishedAt, publishedAt) || other.publishedAt == publishedAt)&&(identical(other.playCount, playCount) || other.playCount == playCount)&&(identical(other.likeCount, likeCount) || other.likeCount == likeCount)&&(identical(other.waveformUrl, waveformUrl) || other.waveformUrl == waveformUrl)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&(identical(other.trackCount, trackCount) || other.trackCount == trackCount)&&(identical(other.isNew, isNew) || other.isNew == isNew));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,platform,artistName,contentType,title,body,mediaUrl,artworkUrl,externalUrl,publishedAt,playCount,likeCount,waveformUrl,durationSeconds,trackCount,isNew);

@override
String toString() {
  return 'FeedItem(id: $id, platform: $platform, artistName: $artistName, contentType: $contentType, title: $title, body: $body, mediaUrl: $mediaUrl, artworkUrl: $artworkUrl, externalUrl: $externalUrl, publishedAt: $publishedAt, playCount: $playCount, likeCount: $likeCount, waveformUrl: $waveformUrl, durationSeconds: $durationSeconds, trackCount: $trackCount, isNew: $isNew)';
}


}

/// @nodoc
abstract mixin class _$FeedItemCopyWith<$Res> implements $FeedItemCopyWith<$Res> {
  factory _$FeedItemCopyWith(_FeedItem value, $Res Function(_FeedItem) _then) = __$FeedItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String platform, String artistName, String contentType, String? title, String? body, String? mediaUrl, String? artworkUrl, String externalUrl, DateTime publishedAt, int? playCount, int? likeCount, String? waveformUrl, int? durationSeconds, int? trackCount, bool isNew
});




}
/// @nodoc
class __$FeedItemCopyWithImpl<$Res>
    implements _$FeedItemCopyWith<$Res> {
  __$FeedItemCopyWithImpl(this._self, this._then);

  final _FeedItem _self;
  final $Res Function(_FeedItem) _then;

/// Create a copy of FeedItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? platform = null,Object? artistName = null,Object? contentType = null,Object? title = freezed,Object? body = freezed,Object? mediaUrl = freezed,Object? artworkUrl = freezed,Object? externalUrl = null,Object? publishedAt = null,Object? playCount = freezed,Object? likeCount = freezed,Object? waveformUrl = freezed,Object? durationSeconds = freezed,Object? trackCount = freezed,Object? isNew = null,}) {
  return _then(_FeedItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,platform: null == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String,artistName: null == artistName ? _self.artistName : artistName // ignore: cast_nullable_to_non_nullable
as String,contentType: null == contentType ? _self.contentType : contentType // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,body: freezed == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String?,mediaUrl: freezed == mediaUrl ? _self.mediaUrl : mediaUrl // ignore: cast_nullable_to_non_nullable
as String?,artworkUrl: freezed == artworkUrl ? _self.artworkUrl : artworkUrl // ignore: cast_nullable_to_non_nullable
as String?,externalUrl: null == externalUrl ? _self.externalUrl : externalUrl // ignore: cast_nullable_to_non_nullable
as String,publishedAt: null == publishedAt ? _self.publishedAt : publishedAt // ignore: cast_nullable_to_non_nullable
as DateTime,playCount: freezed == playCount ? _self.playCount : playCount // ignore: cast_nullable_to_non_nullable
as int?,likeCount: freezed == likeCount ? _self.likeCount : likeCount // ignore: cast_nullable_to_non_nullable
as int?,waveformUrl: freezed == waveformUrl ? _self.waveformUrl : waveformUrl // ignore: cast_nullable_to_non_nullable
as String?,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,trackCount: freezed == trackCount ? _self.trackCount : trackCount // ignore: cast_nullable_to_non_nullable
as int?,isNew: null == isNew ? _self.isNew : isNew // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
