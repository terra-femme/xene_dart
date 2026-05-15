import 'package:dart_frog/dart_frog.dart';

/// GET /auth/soundcloud/done
/// Shown in the browser popup after a successful OAuth flow.
/// The Flutter app is polling /connections/status separately.
Future<Response> onRequest(RequestContext context) async {
  return Response(
    headers: {'content-type': 'text/html; charset=utf-8'},
    body: '''<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Xene — Connected</title></head>
<body style="background:#050505;color:white;display:flex;align-items:center;justify-content:center;height:100vh;font-family:sans-serif;margin:0">
  <div style="text-align:center">
    <div style="font-size:56px;margin-bottom:16px">&#10003;</div>
    <h2 style="margin:0 0 8px;font-size:22px;letter-spacing:2px">SOUNDCLOUD CONNECTED</h2>
    <p style="color:#666;margin:0;font-size:14px">You can close this tab and return to Xene.</p>
  </div>
</body>
</html>''',
  );
}
