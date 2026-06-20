import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// In-memory sliding-window rate limiter, one bucket per key.
///
/// Not distributed: limits are per process. Suitable for single-instance deploy.
class RateLimiter {
  RateLimiter({required this.maxRequests, required this.window});

  final int maxRequests;
  final Duration window;

  final Map<String, List<DateTime>> _buckets = {};
  int _rejections = 0;

  bool allow(String key) {
    final now = DateTime.now();
    final cutoff = now.subtract(window);
    final hits = _buckets.putIfAbsent(key, () => []);
    hits.removeWhere((t) => t.isBefore(cutoff));
    if (hits.length >= maxRequests) {
      _rejections++;
      return false;
    }
    hits.add(now);
    return true;
  }

  Map<String, dynamic> get stats => {
    'maxRequests': maxRequests,
    'windowSeconds': window.inSeconds,
    'activeBuckets': _buckets.length,
    'totalRejections': _rejections,
  };
}

// Feed: 60/min per user. Keyed by userId so shared NAT does not collapse.
final feedMergedRateLimiter = RateLimiter(
  maxRequests: 60,
  window: Duration(minutes: 1),
);

// force_refresh=true triggers a full live scrape, so it gets a tighter limit.
final forceRefreshRateLimiter = RateLimiter(
  maxRequests: 3,
  window: Duration(minutes: 5),
);

// Discovery endpoints run upstream API calls per request.
final discoveryRateLimiter = RateLimiter(
  maxRequests: 10,
  window: Duration(minutes: 1),
);

// Press scout is expensive: seconds per artist across multiple artists.
final pressScoutRateLimiter = RateLimiter(
  maxRequests: 2,
  window: Duration(minutes: 5),
);

// Bug reports are cheap, but public-ish intake endpoints attract spam.
// Layer limits by user and IP so one account cannot flood reports, while a
// shared network still has enough room for legitimate beta feedback.
final bugReportUserRateLimiter = RateLimiter(
  maxRequests: 5,
  window: Duration(minutes: 10),
);

final bugReportIpRateLimiter = RateLimiter(
  maxRequests: 20,
  window: Duration(minutes: 10),
);

final bugReportCooldownRateLimiter = RateLimiter(
  maxRequests: 1,
  window: Duration(seconds: 15),
);

// Admin poll is keyed globally to cap brute-force attempts on X-Admin-Secret.
final adminPollRateLimiter = RateLimiter(
  maxRequests: 5,
  window: Duration(minutes: 1),
);

// Game join is keyed by userId to prevent invite code enumeration.
final gameJoinRateLimiter = RateLimiter(
  maxRequests: 10,
  window: Duration(minutes: 1),
);

// SoundCloud stream proxy is keyed by userId to prevent credential abuse.
final streamRateLimiter = RateLimiter(
  maxRequests: 120,
  window: Duration(hours: 1),
);

// Image proxy is JWT-exempt so it's keyed by IP instead of userId.
// 200/min is generous for legitimate feed browsing; blocks bulk scraping.
final imageProxyRateLimiter = RateLimiter(
  maxRequests: 200,
  window: Duration(minutes: 1),
);

/// Number of trusted reverse-proxy hops sitting in front of this server, read
/// once from the TRUSTED_PROXY_HOPS env var. This is **provider-specific** —
/// Azure App Service, GCP Cloud Run / load balancer, Cloudflare, and bare metal
/// each prepend a different number of hops — so it is configuration, never
/// hardcoded. Switching hosting providers is then a config change, not a code
/// change.
///
/// Default 0 = do NOT trust X-Forwarded-For at all (correct for local dev and
/// any deploy with no proxy in front). Typical values: Azure App Service ≈ 1,
/// GCP HTTPS LB ≈ 1, Cloudflare → an extra hop on top of your origin proxy.
/// Verify against your real deployment before trusting it (see logged value).
final int trustedProxyHops =
    int.tryParse(Platform.environment['TRUSTED_PROXY_HOPS'] ?? '') ?? 0;

/// Extract the originating client IP, honoring exactly [trustedProxyHops] of
/// proxy-appended `X-Forwarded-For` entries.
///
/// `X-Forwarded-For` is built left→right: each proxy APPENDS the address it
/// received the connection from. So the rightmost entries are the ones our own
/// infrastructure added (trustworthy); anything a client prepends sits to the
/// LEFT and is attacker-controlled. We therefore count [trustedProxyHops] in
/// from the right to find the real client and ignore any spoofed prefix.
///
/// With 0 trusted hops we never read X-Forwarded-For (it would be fully
/// spoofable), falling back to `x-real-ip` then `'unknown'`.
String extractClientIp(RequestContext context) {
  if (trustedProxyHops > 0) {
    final forwarded = context.request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.trim().isNotEmpty) {
      final parts = forwarded
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) {
        // Real client = the entry [trustedProxyHops] in from the right.
        final idx = parts.length - trustedProxyHops;
        if (idx >= 0 && idx < parts.length) return parts[idx];
        // Chain is shorter than configured (malformed / unexpected routing):
        // fall back to the rightmost entry — the one our closest proxy added,
        // which is the least attacker-controllable value available.
        return parts.last;
      }
    }
  }
  return context.request.headers['x-real-ip'] ?? 'unknown';
}

/// Returns a 429 response if the key is over the limit, otherwise null.
Response? checkRateLimit(RateLimiter limiter, String key) {
  if (!limiter.allow(key)) {
    return Response.json(
      statusCode: 429,
      body: {'error': 'Rate limit exceeded - please slow down'},
    );
  }
  return null;
}
