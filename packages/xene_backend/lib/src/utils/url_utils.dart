/// Allowed outbound host sets — used to validate user-supplied URLs before
/// the backend makes any HTTP request to them. Guards against SSRF.
const allowedBandcampHosts = {'bandcamp.com'};
const allowedYoutubeHosts = {'youtube.com', 'youtu.be', 'googleapis.com'};
const allowedSpotifyHosts = {'spotify.com', 'open.spotify.com'};
const allowedWebsiteHosts =
    <String>{}; // empty = any host allowed for generic website_url

/// Returns true if [url] parses to a host that is [allowedHosts] or a subdomain of one.
/// Returns false on null, empty, or unparseable input.
/// Empty [allowedHosts] set means the check is skipped (any host allowed).
bool isAllowedOutboundUrl(String? url, Set<String> allowedHosts) {
  if (url == null || url.isEmpty) return false;
  if (allowedHosts.isEmpty) return true;
  try {
    final normalized = url.startsWith('http') ? url : 'https://$url';
    final host = Uri.parse(normalized).host.toLowerCase();
    if (host.isEmpty) return false;
    return allowedHosts.any((h) => host == h || host.endsWith('.$h'));
  } catch (_) {
    return false;
  }
}

/// Validates a map of platform URL fields and returns any that fail the
/// domain allowlist check. Keys with null/empty values are skipped.
Map<String, String> invalidPlatformUrls(Map<String, dynamic> fields) {
  final violations = <String, String>{};

  void check(String key, Set<String> allowed) {
    final val = fields[key] as String?;
    if (val != null && val.isNotEmpty && !isAllowedOutboundUrl(val, allowed)) {
      violations[key] = val;
    }
  }

  check('bandcamp_url', allowedBandcampHosts);
  check('youtube_url', allowedYoutubeHosts);
  return violations;
}
