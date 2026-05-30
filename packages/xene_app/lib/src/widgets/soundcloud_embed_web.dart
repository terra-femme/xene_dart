import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class SoundCloudEmbed extends StatefulWidget {
  const SoundCloudEmbed({
    super.key,
    required this.trackId,
    this.isVisual = false,
  });

  final String trackId;
  final bool isVisual;

  @override
  State<SoundCloudEmbed> createState() => _SoundCloudEmbedState();
}

class _SoundCloudEmbedState extends State<SoundCloudEmbed> {
  // Static counter ensures every widget instance gets a unique view ID.
  // Using trackId as the view ID caused silent factory-registration collisions:
  // playing the same track a second time re-runs initState with the same ID,
  // registerViewFactory is a no-op the second time, and the iframe never renders.
  static int _nextInstanceId = 0;
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'sc-player-${_nextInstanceId++}';

    ui.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = _buildEmbedUrl(widget.trackId, widget.isVisual)
        // CSS dimensions fill the Flutter-controlled container.
        // HTML width/height attributes fight with flt-platform-view sizing
        // and produce the "height/width may not be set" console warnings.
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.borderRadius = '8px';

      iframe.setAttribute('scrolling', 'no');
      iframe.setAttribute('frameborder', '0');
      iframe.setAttribute('allow', 'autoplay; encrypted-media');

      return iframe;
    });
  }

  String _buildEmbedUrl(String trackId, bool isVisual) {
    // Full SoundCloud URLs are used for private playlist embeds because they
    // can include a secret_token query parameter.
    final String resourcePath;
    if (trackId.startsWith('http://') || trackId.startsWith('https://')) {
      resourcePath = Uri.encodeComponent(trackId);
    } else if (trackId.startsWith('playlist-')) {
      // Playlist IDs are stored as 'playlist-{id}' and need /playlists/.
      final playlistId = trackId.substring('playlist-'.length);
      resourcePath = 'https%3A//api.soundcloud.com/playlists/$playlistId';
    } else {
      resourcePath = 'https%3A//api.soundcloud.com/tracks/$trackId';
    }

    final visual = isVisual ? 'true' : 'false';
    return 'https://w.soundcloud.com/player/'
        '?url=$resourcePath'
        '&color=%23ff5500'
        '&auto_play=true'
        '&show_user=true'
        '&visual=$visual'
        '&show_comments=false'
        '&show_reposts=false'
        '&show_teaser=false';
  }

  @override
  Widget build(BuildContext context) {
    // SizedBox.expand() fills whatever space the parent allocates via Flutter layout.
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.expand(child: HtmlElementView(viewType: _viewId)),
    );
  }
}
