import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
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
  static const MethodChannel _nativeHaptics = MethodChannel(
    'xene/native_haptics',
  );

  WebViewController? _controller;
  bool _supported = true;
  int _hapticMessageCount = 0;

  @override
  void initState() {
    super.initState();
    // webview_flutter only targets Android + iOS. Degrade elsewhere.
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      _supported = false;
      return;
    }
    final controller = _buildController();
    _controller = controller;
    unawaited(_configureAudioSession());
    unawaited(_loadVisualizer(controller));
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
      // Surface everything the WKWebView normally swallows: JS console output
      // (three.js failures, WebGL context errors, playlist fetch logs), failed
      // subresource loads (three.min.js, remote playlist.json / stems, the
      // assets/ texture), and HTTP errors. Uses debugPrint (not dev.log) so the
      // lines actually print as `flutter:` in the Xcode Runner console —
      // dev.log goes to a channel Xcode's console does not show. dev-only.
      ..setOnConsoleMessage((JavaScriptConsoleMessage m) {
        debugPrint('[dpWeb][console.${m.level.name}] ${m.message}');
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) => debugPrint('[dpWeb] page finished: $url'),
          onWebResourceError: (WebResourceError e) {
            debugPrint(
              '[dpWeb][resourceError] code=${e.errorCode} '
              'mainFrame=${e.isForMainFrame} url=${e.url} — ${e.description}',
            );
          },
          onHttpError: (HttpResponseError e) {
            debugPrint(
              '[dpWeb][httpError] status=${e.response?.statusCode} '
              'url=${e.request?.uri}',
            );
          },
        ),
      )
      ..addJavaScriptChannel(
        'XeneDiagnostics',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('[dpWeb][js] ${message.message}');
        },
      )
      ..addJavaScriptChannel(
        'XeneHaptics',
        onMessageReceived: (JavaScriptMessage message) {
          // Two message shapes ride this channel:
          //  - legacy plain kind string ('light'/'medium'/'heavy')
          //  - drum-voice JSON {"kind":"kick"|"snare"|"hat","intensity":0..1}
          final raw = message.message;
          var kind = raw;
          double? intensity;
          if (raw.startsWith('{')) {
            try {
              final decoded = jsonDecode(raw) as Map<String, dynamic>;
              kind = decoded['kind'] as String? ?? 'medium';
              intensity = (decoded['intensity'] as num?)?.toDouble();
            } catch (error) {
              debugPrint('[dpWeb][haptic] bad payload "$raw": $error');
              return;
            }
          }
          _hapticMessageCount += 1;
          if (_hapticMessageCount <= 16) {
            debugPrint(
              '[dpWeb][haptic] received $kind '
              'intensity=$intensity #$_hapticMessageCount',
            );
          }
          // Beat intensity → native impact. iOS drives the Taptic Engine here.
          unawaited(_fireNativeHaptic(kind, intensity));
        },
      );

    // Android: let the page's audio autoplay without a user gesture.
    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    return controller;
  }

  Future<void> _fireNativeHaptic(String kind, double? intensity) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final ok = await _nativeHaptics.invokeMethod<bool>(
          'impact',
          <String, Object?>{'kind': kind, 'intensity': intensity},
        );
        if (_hapticMessageCount <= 16) {
          debugPrint('[dpWeb][haptic] native impact ok=$ok kind=$kind');
        }
        return;
      } catch (error) {
        debugPrint('[dpWeb][haptic] native impact failed: $error');
      }
    }

    switch (kind) {
      case 'kick':
      case 'heavy':
        await HapticFeedback.heavyImpact();
        break;
      case 'snare':
      case 'medium':
        await HapticFeedback.mediumImpact();
        break;
      case 'hat':
      case 'light':
      default:
        await HapticFeedback.lightImpact();
        break;
    }
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.music());
      await session.setActive(true);
      debugPrint('[dpWeb] audio session configured for playback');
    } catch (error, stackTrace) {
      debugPrint('[dpWeb] audio session configure failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _loadVisualizer(WebViewController controller) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final html = await _buildInlineVisualizerHtml();
        await controller.loadHtmlString(html, baseUrl: 'https://xene.local');
        debugPrint('[dpWeb] loaded inline iOS visualizer HTML');
      } else {
        await controller.loadFlutterAsset('web/dancing_points/index.html');
      }
    } catch (error, stackTrace) {
      debugPrint('[dpWeb] failed to load visualizer: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<String> _buildInlineVisualizerHtml() async {
    var html = await rootBundle.loadString('web/dancing_points/index.html');
    final brainBytes = await rootBundle.load(
      'web/dancing_points/assets/brain_wire_reference.png',
    );
    final brainPng = brainBytes.buffer.asUint8List(
      brainBytes.offsetInBytes,
      brainBytes.lengthInBytes,
    );
    final brainDataUrl = 'data:image/png;base64,${base64Encode(brainPng)}';
    html = html.replaceFirst(
      '</head>',
      '<script>window.XENE_NATIVE_HOST={platform:"ios"};'
          'window.XENE_ASSETS={'
          'brainWire:${jsonEncode(brainDataUrl)}'
          '};</script></head>',
    );

    const scripts = <String>[
      'three.min.js',
      'av-config.js',
      'shaders.js',
      'audio-engine.js',
      'brain-dots-data.js',
      'brain-other-data.js',
      'scene.js',
      'chart-gen.js',
      'track-export.js',
      'playlist.js',
      'app.js',
    ];
    for (final script in scripts) {
      final source = await rootBundle.loadString(
        'web/dancing_points/js/$script',
      );
      final escapedSource = source.replaceAll('</script>', '<\\/script>');
      html = html.replaceFirst(
        RegExp('<script src="js/$script(?:\\?[^"]*)?"></script>'),
        '<script>\n$escapedSource\n</script>',
      );
    }
    return html;
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
