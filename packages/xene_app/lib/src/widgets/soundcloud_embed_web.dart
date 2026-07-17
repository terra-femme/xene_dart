import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Broadcast stream of SC playback positions in milliseconds.
/// Emits as the active SC iframe progresses; empty on non-web platforms (see stub).
Stream<int> get scPlayPositionStream => _ScBridge.positionStream;

// ─── SC Widget API bridge ─────────────────────────────────────────────────────
// The SC Widget API communicates via postMessage. This bridge:
//   1. Loads api.js (once per page, guarded by window.__xeneScApiLoading)
//   2. Calls SC.Widget(iframe).bind(PLAY_PROGRESS) after the API is ready
//   3. Forwards currentPosition as a Dart broadcast stream
class _ScBridge {
  _ScBridge._();

  static final _controller = StreamController<int>.broadcast();
  static Stream<int> get positionStream => _controller.stream;
  static bool _listenerReady = false;

  static void _ensureListener() {
    if (_listenerReady) return;
    _listenerReady = true;
    web.window.addEventListener(
      'message',
      (JSAny? rawEvent) {
        final event = rawEvent as web.MessageEvent;
        final raw = event.data?.dartify();
        if (raw is! String) return;
        try {
          final msg = jsonDecode(raw) as Map<String, dynamic>;
          if (msg['type'] != 'xene_sc_progress') return;
          final pos = (msg['position'] as num?)?.toInt();
          if (pos != null) _controller.add(pos);
        } catch (_) {}
      }.toJS,
    );
  }

  /// Injects an inline script that loads the SC Widget API once, then binds
  /// PLAY_PROGRESS for [iframeId] and posts progress events to the parent window.
  static void bind(String iframeId) {
    _ensureListener();
    final js =
        """
(function(iframeId) {
  function doBind() {
    var el = document.getElementById(iframeId);
    if (!el || !window.SC) return;
    SC.Widget(el).bind(SC.Widget.Events.PLAY_PROGRESS, function(e) {
      window.postMessage(
        JSON.stringify({ type: 'xene_sc_progress', position: Math.round(e.currentPosition || 0) }),
        '*'
      );
    });
  }
  if (window.__xeneScApiReady) { doBind(); return; }
  window.__xeneScPending = window.__xeneScPending || [];
  window.__xeneScPending.push(doBind);
  if (!window.__xeneScApiLoading) {
    window.__xeneScApiLoading = true;
    var s = document.createElement('script');
    s.src = 'https://w.soundcloud.com/player/api.js';
    s.onload = function() {
      window.__xeneScApiReady = true;
      (window.__xeneScPending || []).forEach(function(fn) { fn(); });
      window.__xeneScPending = [];
    };
    document.head.appendChild(s);
  }
})('$iframeId');
""";
    final script = web.HTMLScriptElement()..text = js;
    web.document.body!.appendChild(script);
  }
}

// ─── Widget ───────────────────────────────────────────────────────────────────
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

  // Accepted for facade-signature parity with the native embed (which uses it
  // for the artwork fallback). Unused on web, where the iframe renders directly.
  final String? artworkUrl;
  final String? title;
  final String? artistName;
  final int? durationSeconds;

  @override
  State<SoundCloudEmbed> createState() => _SoundCloudEmbedState();
}

class _SoundCloudEmbedState extends State<SoundCloudEmbed> {
  static int _nextInstanceId = 0;
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'sc-player-${_nextInstanceId++}';

    ui.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..id = _viewId
        ..src = _buildEmbedUrl(widget.trackId, widget.isVisual)
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.borderRadius = '8px';

      iframe.setAttribute('scrolling', 'no');
      iframe.setAttribute('frameborder', '0');
      iframe.setAttribute('allow', 'autoplay; encrypted-media');

      return iframe;
    });

    // Bind the SC Widget API after the first frame — by then Flutter has
    // inserted the iframe into the DOM and SC.Widget() can find it by id.
    // The Widget API polls internally until the SC player inside the iframe
    // responds, so calling bind() before the player fully loads is safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ScBridge.bind(_viewId);
    });
  }

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

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.expand(child: HtmlElementView(viewType: _viewId)),
    );
  }
}
