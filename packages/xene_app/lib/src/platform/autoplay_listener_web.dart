import 'dart:js_interop';

import 'package:web/web.dart' as web;

// Listens for track-end postMessage events from SC and YT iframes.
// SC Widget fires: {"soundcloudWidget":{"method":"finish",...}}
// YT IFrame API can report ended as onStateChange info=0 or infoDelivery
// playerState=0, depending on which API path produced the message.
void setupAutoplayListener(void Function() onTrackEnded) {
  web.window.addEventListener(
    'message',
    ((JSObject obj) {
      final e = obj as web.MessageEvent;
      final raw = e.data.dartify()?.toString() ?? '';
      if (raw.isEmpty) return;

      final compact = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      final isScFinish =
          compact.contains('soundcloudwidget') &&
          compact.contains('method') &&
          compact.contains('finish');
      final isYtEnded =
          compact.contains('onstatechange') && compact.contains('info:0') ||
          compact.contains('"onstatechange"') && compact.contains('"info":0') ||
          compact.contains('playerstate:0') ||
          compact.contains('"playerstate":0');

      if (isScFinish || isYtEnded) {
        onTrackEnded();
      }
    }).toJS,
  );
}
