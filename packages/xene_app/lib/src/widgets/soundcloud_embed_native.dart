import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../platform/now_playing_metadata.dart';
import 'embed_fallback.dart';

/// Native (Android/iOS) SoundCloud embed for the pop-out player.
///
/// There is no native SoundCloud SDK, so we host the SAME SC Widget API HTML the
/// web build uses (see soundcloud_embed_web.dart) inside a native [WebView]. The
/// only difference from web is the transport for play-progress events: the web
/// build uses window.postMessage → a DOM listener; native uses a WebView
/// JavaScript channel (`XeneSc`) → the Dart [scPlayPositionStream]. The public
/// surface (the [scPlayPositionStream] getter + the [SoundCloudEmbed] widget) is
/// identical, so the facade (soundcloud_embed.dart) and the visualizer wiring in
/// winamp_player.dart work unchanged.

// ─── Position stream ────────────────────────────────────────────────────────
// App-global broadcast stream of SC playback positions in milliseconds, fed by
// the active WebView's JS channel. Mirrors the web bridge's single global
// controller (never closed; lives for the app session). Empty until a SC embed
// is mounted and the SC player starts emitting PLAY_PROGRESS.
final StreamController<int> _scPositionController =
    StreamController<int>.broadcast();

Stream<int> get scPlayPositionStream => _scPositionController.stream;

// ─── Widget ─────────────────────────────────────────────────────────────────
class SoundCloudEmbed extends StatefulWidget {
  const SoundCloudEmbed({
    super.key,
    required this.trackId,
    this.isVisual = false,
    this.artworkUrl,
    this.title,
    this.artistName,
    this.durationSeconds,
  });

  final String trackId;
  final bool isVisual;

  /// Track artwork, used as the fallback backdrop when the player can't load.
  final String? artworkUrl;
  final String? title;
  final String? artistName;
  final int? durationSeconds;

  @override
  State<SoundCloudEmbed> createState() => _SoundCloudEmbedState();
}

class _SoundCloudEmbedState extends State<SoundCloudEmbed> {
  WebViewController? _controller;
  bool _supported = true;
  bool _loadError = false;
  DateTime? _lastMetadataSyncAt;

  @override
  void initState() {
    super.initState();
    // webview_flutter only supports Android + iOS. Guard so a desktop build
    // (if ever produced) degrades to a placeholder instead of crashing.
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      _supported = false;
      debugPrint(
        '[SoundCloudEmbed:native] unsupported platform $platform — fallback',
      );
      return;
    }
    _controller = _buildController();
  }

  WebViewController _buildController() {
    // iOS (WKWebView) needs inline playback + no user-gesture requirement so
    // SoundCloud's auto_play=true actually starts.
    final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'XeneSc',
        onMessageReceived: (JavaScriptMessage message) {
          final pos = int.tryParse(message.message);
          if (pos != null && !_scPositionController.isClosed) {
            _scPositionController.add(pos);
            _syncNowPlayingMetadata(pos);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (WebResourceError error) {
            // Only a main-frame failure means the player itself didn't load;
            // sub-resource errors (ads/trackers inside the SC iframe) are noise.
            if (error.isForMainFrame ?? true) {
              debugPrint(
                '[SoundCloudEmbed:native] load error: ${error.description}',
              );
              if (mounted) setState(() => _loadError = true);
            }
          },
        ),
      )
      ..loadHtmlString(
        _buildHtml(widget.trackId, widget.isVisual),
        baseUrl: 'https://w.soundcloud.com',
      );

    // Android: allow media to autoplay without a user gesture.
    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    return controller;
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      unawaited(
        controller.runJavaScript('''
try {
  var frame = document.getElementById('sc');
  if (frame && window.SC && SC.Widget) {
    SC.Widget(frame).pause();
  }
  if (frame) {
    frame.src = 'about:blank';
    frame.remove();
  }
  document.body.innerHTML = '';
} catch (e) {}
'''),
      );
    }
    super.dispose();
  }

  void _retry() {
    setState(() {
      _loadError = false;
      _controller = _buildController();
    });
  }

  void _syncNowPlayingMetadata(int positionMs) {
    final title = widget.title?.trim();
    final artist = widget.artistName?.trim();
    if ((title == null || title.isEmpty) &&
        (artist == null || artist.isEmpty) &&
        widget.artworkUrl == null) {
      return;
    }

    final now = DateTime.now();
    final lastSync = _lastMetadataSyncAt;
    if (lastSync != null && now.difference(lastSync).inSeconds < 15) {
      return;
    }
    _lastMetadataSyncAt = now;

    unawaited(
      NowPlayingMetadataBridge.update(
        NowPlayingMetadata(
          title: title == null || title.isEmpty ? 'Unknown Track' : title,
          artist: artist == null || artist.isEmpty ? 'Xene' : artist,
          platform: 'soundcloud',
          artworkUrl: widget.artworkUrl,
          durationSeconds: widget.durationSeconds,
          elapsedSeconds: positionMs ~/ 1000,
        ),
      ),
    );
  }

  /// Mirrors soundcloud_embed_web.dart's URL builder exactly so native and web
  /// resolve the same track/playlist/url forms identically.
  String _buildEmbedUrl(String trackId, bool isVisual) {
    final String resourcePath;
    if (trackId.startsWith('http://') || trackId.startsWith('https://')) {
      resourcePath = Uri.encodeComponent(trackId);
    } else if (trackId.startsWith('playlist-')) {
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

  /// Wrapper page: the SC iframe + the SC Widget API, binding PLAY_PROGRESS and
  /// forwarding currentPosition to Dart via the `XeneSc` JS channel. Same script
  /// shape as the web bridge, minus the postMessage indirection.
  String _buildHtml(String trackId, bool isVisual) {
    final embedUrl = _buildEmbedUrl(trackId, isVisual);
    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html, body { margin: 0; padding: 0; height: 100%; background: #000; overflow: hidden; }
  #sc { border: 0; width: 100%; height: 100%; border-radius: 8px; }
</style>
</head>
<body>
<iframe id="sc" src="$embedUrl" allow="autoplay; encrypted-media" scrolling="no" frameborder="0"></iframe>
<script src="https://w.soundcloud.com/player/api.js"></script>
<script>
(function () {
  function post(p) {
    try { if (window.XeneSc) { XeneSc.postMessage(String(p)); } } catch (e) {}
  }
  function bind() {
    var el = document.getElementById('sc');
    if (!el || !window.SC || !SC.Widget) { setTimeout(bind, 200); return; }
    var widget = SC.Widget(el);
    widget.bind(SC.Widget.Events.PLAY_PROGRESS, function (e) {
      post(Math.round((e && e.currentPosition) || 0));
    });
  }
  bind();
})();
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_supported || controller == null || _loadError) {
      return EmbedFallback(
        logoAsset: 'assets/soundcloud_logo.png',
        accentColor: const Color(0xFFFF5500),
        artworkUrl: widget.artworkUrl,
        message: _supported
            ? 'Player unavailable'
            : 'Player not supported here',
        onRetry: _supported ? _retry : null,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: WebViewWidget(controller: controller),
    );
  }
}
