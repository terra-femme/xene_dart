import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import 'embed_fallback.dart';

/// Native (Android/iOS) YouTube embed for the pop-out player.
///
/// The web build renders a real `<iframe>` (see youtube_embed_web.dart); native
/// can't host an iframe, so we reuse the SAME package the article sheet already
/// uses natively (`youtube_player_flutter`) — proven working in
/// xene_article_sheet.dart. Same public surface as the web/stub widget so the
/// facade (youtube_embed.dart) swaps it in transparently.
class YouTubeEmbed extends StatefulWidget {
  const YouTubeEmbed({
    super.key,
    required this.videoId,
    required this.externalUrl,
    this.artworkUrl,
  });

  final String videoId;
  final String externalUrl;

  /// Track artwork, used as the fallback backdrop when no id resolves.
  final String? artworkUrl;

  @override
  State<YouTubeEmbed> createState() => _YouTubeEmbedState();
}

class _YouTubeEmbedState extends State<YouTubeEmbed> {
  YoutubePlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final id = _resolveVideoId();
    if (id != null && id.isNotEmpty) {
      debugPrint('[YouTubeEmbed:native] loading inline id=$id');
      _controller = YoutubePlayerController.fromVideoId(
        videoId: id,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          mute: false,
        ),
      );
    } else {
      debugPrint(
        '[YouTubeEmbed:native] could not resolve a video id '
        '(videoId="${widget.videoId}", externalUrl="${widget.externalUrl}")',
      );
    }
  }

  /// Prefer a bare id; otherwise let the package parse watch?v=, youtu.be, and
  /// embed/ URLs, then fall back to manual shorts/ parsing (which the package
  /// does not handle) out of [externalUrl].
  String? _resolveVideoId() {
    final v = widget.videoId;
    // Already a bare id.
    if (v.isNotEmpty && !v.contains('/') && !v.contains('?')) return v;
    // watch?v=, youtu.be/, embed/ — the package handles these.
    final fromPackage = YoutubePlayerController.convertUrlToId(
      widget.externalUrl,
    );
    if (fromPackage != null) return fromPackage;
    // Shorts (youtube.com/shorts/<id>): convertUrlToId returns null for these,
    // so parse the path segment ourselves — same fallback the web embed and
    // xene_article_sheet.dart already use.
    final uri = Uri.tryParse(widget.externalUrl);
    if (uri != null) {
      final segments = uri.pathSegments;
      final shortsIndex = segments.indexOf('shorts');
      if (shortsIndex >= 0 && shortsIndex + 1 < segments.length) {
        return segments[shortsIndex + 1];
      }
    }
    return v.isNotEmpty ? v : null;
  }

  void _retry() {
    setState(() {
      _controller?.close();
      _controller = null;
      _init();
    });
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return EmbedFallback(
        logoAsset: 'assets/yt_icon_red_digital.png',
        accentColor: const Color(0xFFFF4444),
        artworkUrl: widget.artworkUrl,
        onRetry: _retry,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: YoutubePlayer(controller: controller, aspectRatio: 16 / 9),
    );
  }
}
