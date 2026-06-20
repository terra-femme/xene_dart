import 'package:flutter/foundation.dart';

import '../providers/dio_provider.dart' show kBackendUrl;

/// Hosts that serve artwork without permissive CORS headers, so a Flutter-web
/// `CachedNetworkImage`/canvas decode of them fails (the "broken image" / red-X
/// glyph). Requests to these are rewritten to the backend `/proxy/image`
/// endpoint, which refetches server-side and re-emits the bytes with
/// `Access-Control-Allow-Origin: *`.
///
/// Keep this in sync with the backend allowlist in
/// `routes/proxy/image.dart` — the proxy 403s any host not on its own list.
const _corsRestrictedHosts = <String>{
  // Bandcamp
  'f4.bcbits.com',
  'f3.bcbits.com',
  'f2.bcbits.com',
  'f1.bcbits.com',
  'a.bcbits.com',
  // SoundCloud
  'i1.sndcdn.com',
  'i2.sndcdn.com',
  'i3.sndcdn.com',
  'i4.sndcdn.com',
  'i5.sndcdn.com',
  'i6.sndcdn.com',
  'i7.sndcdn.com',
  // YouTube avatars
  'yt3.ggpht.com',
  'yt4.ggpht.com',
  // YouTube video thumbnails
  'i.ytimg.com',
  'img.youtube.com',
};

/// Rewrites a CORS-restricted artwork [url] to route through the backend image
/// proxy. Returns the URL unchanged when it is null/empty, unparseable, already
/// pointed at the backend proxy, or served from a CORS-friendly host — so it is
/// safe (idempotent) to call at render time even on already-proxied URLs.
String? proxyArtworkUrl(String? url) {
  if (url == null || url.isEmpty) return url;
  try {
    final uri = Uri.parse(url);
    if (_corsRestrictedHosts.contains(uri.host)) {
      return '$kBackendUrl/proxy/image?url=${Uri.encodeComponent(url)}';
    }
  } catch (_) {
    debugPrint('[proxyArtworkUrl] failed to parse url: $url');
  }
  return url;
}
