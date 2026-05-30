import 'package:dart_frog/dart_frog.dart';

/// In-memory sliding-window rate limiter — one bucket per client IP.
/// Not distributed: limits are per-process. Suitable for single-instance deploy.
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

// Feed: 60/min per user — 3 requests per preset view × 20 preset views/min.
// Keyed by userId (not IP) so shared NAT / localhost dev doesn't collapse into one bucket.
final feedMergedRateLimiter = RateLimiter(
  maxRequests: 60,
  window: Duration(minutes: 1),
);

// force_refresh=true triggers a full live scrape — much tighter limit.
final forceRefreshRateLimiter = RateLimiter(
  maxRequests: 3,
  window: Duration(minutes: 5),
);

// Discovery endpoints run upstream API calls per request.
final discoveryRateLimiter = RateLimiter(
  maxRequests: 10,
  window: Duration(minutes: 1),
);

// Press scout is the most expensive operation (~seconds per artist, multiple artists).
final pressScoutRateLimiter = RateLimiter(
  maxRequests: 2,
  window: Duration(minutes: 5),
);

/// Extract the originating IP from the request, respecting proxy headers.
String extractClientIp(RequestContext context) {
  final forwarded = context.request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.isNotEmpty) {
    return forwarded.split(',').first.trim();
  }
  return context.request.headers['x-real-ip'] ?? 'unknown';
}

/// Returns a 429 response if the key is over the limit, otherwise null.
Response? checkRateLimit(RateLimiter limiter, String key) {
  if (!limiter.allow(key)) {
    return Response.json(
      statusCode: 429,
      body: {'error': 'Rate limit exceeded — please slow down'},
    );
  }
  return null;
}
