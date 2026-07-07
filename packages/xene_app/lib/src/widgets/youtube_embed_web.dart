import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class YouTubeEmbed extends StatefulWidget {
  const YouTubeEmbed({
    super.key,
    required this.videoId,
    required this.externalUrl,
    this.artworkUrl,
  });

  final String videoId;
  final String externalUrl;

  // Accepted for facade-signature parity with the native embed (which uses it
  // for the artwork fallback). Unused on web, where the iframe renders directly.
  final String? artworkUrl;

  @override
  State<YouTubeEmbed> createState() => _YouTubeEmbedState();
}

class _YouTubeEmbedState extends State<YouTubeEmbed> {
  static int _nextInstanceId = 0;
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'yt-player-${_nextInstanceId++}';

    ui.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = _buildEmbedUrl()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.borderRadius = '8px';

      iframe.setAttribute('allowfullscreen', 'true');
      iframe.setAttribute('frameborder', '0');
      iframe.setAttribute(
        'allow',
        'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share',
      );

      return iframe;
    });
  }

  String _buildEmbedUrl() {
    final id = _resolveVideoId(widget.videoId, widget.externalUrl);
    if (id == null || id.isEmpty) return widget.externalUrl;
    return 'https://www.youtube.com/embed/$id?autoplay=1&playsinline=1&rel=0&enablejsapi=1';
  }

  String? _resolveVideoId(String id, String url) {
    if (id.isNotEmpty && !id.contains('/') && !id.contains('?')) return id;
    final uri = Uri.tryParse(url);
    if (uri == null) return id;
    final host = uri.host.toLowerCase();
    if (host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    final v = uri.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    final segments = uri.pathSegments;
    final shortsIndex = segments.indexOf('shorts');
    if (shortsIndex >= 0 && shortsIndex + 1 < segments.length) {
      return segments[shortsIndex + 1];
    }
    final embedIndex = segments.indexOf('embed');
    if (embedIndex >= 0 && embedIndex + 1 < segments.length) {
      return segments[embedIndex + 1];
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.expand(child: HtmlElementView(viewType: _viewId)),
    );
  }
}
