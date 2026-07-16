import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xene_domain/xene_domain.dart';

import '../models/user_media_item.dart';

class NowPlayingMetadata {
  const NowPlayingMetadata({
    required this.title,
    required this.artist,
    required this.platform,
    this.artworkUrl,
    this.durationSeconds,
    this.elapsedSeconds,
    this.isPlaying = true,
  });

  final String title;
  final String artist;
  final String platform;
  final String? artworkUrl;
  final int? durationSeconds;
  final int? elapsedSeconds;
  final bool isPlaying;

  Map<String, Object?> toJson() => {
    'title': title,
    'artist': artist,
    'platform': platform,
    'artworkUrl': artworkUrl,
    'durationSeconds': durationSeconds,
    'elapsedSeconds': elapsedSeconds,
    'isPlaying': isPlaying,
  };
}

class NowPlayingMetadataBridge {
  static const MethodChannel _channel = MethodChannel(
    'xene/now_playing_metadata',
  );

  static Future<void> update(NowPlayingMetadata metadata) async {
    if (!_isIos) return;
    try {
      await _channel.invokeMethod<void>('update', metadata.toJson());
    } on MissingPluginException {
      // Native metadata is best-effort; unsupported builds should keep playing.
    } on PlatformException catch (error) {
      debugPrint('[nowPlaying] update failed: ${error.message}');
    }
  }

  static Future<void> clear() async {
    if (!_isIos) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      // Native metadata is best-effort; unsupported builds should keep playing.
    } on PlatformException catch (error) {
      debugPrint('[nowPlaying] clear failed: ${error.message}');
    }
  }

  static bool get _isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}

extension FeedItemNowPlaying on FeedItem {
  NowPlayingMetadata toNowPlayingMetadata({bool isPlaying = true}) {
    return NowPlayingMetadata(
      title: _fallbackText(title, 'Unknown Track'),
      artist: _fallbackText(artistName, 'Xene'),
      platform: platform,
      artworkUrl: artworkUrl,
      durationSeconds: durationSeconds,
      isPlaying: isPlaying,
    );
  }
}

extension QueueItemNowPlaying on QueueItem {
  NowPlayingMetadata toNowPlayingMetadata({bool isPlaying = true}) {
    return NowPlayingMetadata(
      title: _fallbackText(title, 'Unknown Track'),
      artist: _fallbackText(artistName, 'Xene'),
      platform: platform,
      artworkUrl: artworkUrl,
      durationSeconds: durationSeconds,
      isPlaying: isPlaying,
    );
  }
}

String _fallbackText(String? value, String fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}
