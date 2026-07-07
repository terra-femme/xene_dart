import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Native (Android/iOS) host for the Dancing Points WebGL visualizer.
///
/// The web build renders the page in an <iframe> (dancing_points_view_web.dart).
/// Natively we run the SAME bundled page (web/dancing_points/index.html) inside a
/// [WebView], so the imported WebGL + live-FFT design appears on the actual
/// phone/tablet — no Chrome, no web build.
///
/// Haptics: the page calls navigator.vibrate (Android only). To fire on iOS too —
/// WKWebView ignores navigator.vibrate — the page also posts beat intensity to
/// the `XeneHaptics` JS channel, which we map to Flutter's [HapticFeedback]
/// (Taptic Engine on iOS, vibrator on Android). Same JS-channel bridge pattern as
/// the SoundCloud position stream.
class DancingPointsView extends StatefulWidget {
  const DancingPointsView({super.key});

  @override
  State<DancingPointsView> createState() => _DancingPointsViewState();
}

class _DancingPointsViewState extends State<DancingPointsView> {
  WebViewController? _controller;
  bool _supported = true;

  @override
  void initState() {
    super.initState();
    // webview_flutter only targets Android + iOS. Degrade elsewhere.
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      _supported = false;
      return;
    }
    _controller = _buildController();
  }

  WebViewController _buildController() {
    // iOS (WKWebView) needs inline playback + no user-gesture requirement so the
    // page's <audio> can start.
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
      ..setBackgroundColor(const Color(0xFF07070A))
      ..addJavaScriptChannel(
        'XeneHaptics',
        onMessageReceived: (JavaScriptMessage message) {
          // Beat intensity → native impact. iOS drives the Taptic Engine here.
          switch (message.message) {
            case 'heavy':
              HapticFeedback.heavyImpact();
              break;
            case 'medium':
              HapticFeedback.mediumImpact();
              break;
            case 'light':
            default:
              HapticFeedback.lightImpact();
              break;
          }
        },
      )
      ..loadFlutterAsset('web/dancing_points/index.html');

    // Android: let the page's audio autoplay without a user gesture.
    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_supported || controller == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Dancing Points runs on Android & iOS.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return WebViewWidget(controller: controller);
  }
}
