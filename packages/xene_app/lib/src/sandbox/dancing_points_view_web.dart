import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Hosts the imported Dancing Points WebGL page (served from
/// `web/dancing_points/index.html`) inside the Flutter web app via an iframe.
///
/// This is the **upload mode** for now: the embedded page handles file upload,
/// live FFT, the sphere, and self-contained haptics (`navigator.vibrate`).
/// Modes 1 & 2 (xene history / SoundCloud search) will later feed this view a
/// stream source over postMessage — see docs/haptic_music_accessibility.md §15.
class DancingPointsView extends StatefulWidget {
  const DancingPointsView({super.key});

  @override
  State<DancingPointsView> createState() => _DancingPointsViewState();
}

class _DancingPointsViewState extends State<DancingPointsView> {
  static int _nextInstanceId = 0;
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'dancing-points-${_nextInstanceId++}';

    ui.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..id = _viewId
        ..src = 'dancing_points/index.html'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      // Autoplay + media so the embedded <audio> can start on the play tap.
      iframe.setAttribute('allow', 'autoplay; encrypted-media');
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: HtmlElementView(viewType: _viewId));
  }
}
