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
    // Playlist IDs are stored as 'playlist-{id}' — they need /playlists/ not /tracks/.
    // Passing 'playlist-12345' to /tracks/ returns an invalid resource and SoundCloud
    // falls back to the "Open in SoundCloud" stub instead of rendering the player.
    final String resourcePath;
    if (trackId.startsWith('playlist-')) {
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
    // The PiP well gives ~219px — enough for the SoundCloud visual player (min ~166px).
    // The old fixed height of 150px was below that threshold, causing artwork to be hidden.
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.expand(
        child: HtmlElementView(viewType: _viewId),
      ),
    );
  }
}
