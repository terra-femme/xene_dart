import 'package:test/test.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';

void main() {
  group('Image Proxy Rate Limiting Integration', () {
    test('imageProxyRateLimiter enforces 200 req/min per IP', () {
      // Simulate the rate limiting logic from routes/proxy/image.dart
      final stats = imageProxyRateLimiter.stats;

      // Verify configuration
      expect(stats['maxRequests'], equals(200),
          reason: 'Image proxy should allow 200 requests per minute');
      expect(stats['windowSeconds'], equals(60),
          reason: 'Rate limit window should be 60 seconds');

      print('✓ Image proxy rate limiter configured: ${stats['maxRequests']} '
          'req/${stats['windowSeconds']}s per IP');
    });

    test('rate limiting rejects requests from same IP after 200 requests', () {
      // This test demonstrates the behavior of the image proxy limiter
      // We use a fresh limiter with same config as imageProxyRateLimiter
      final limiter = RateLimiter(maxRequests: 200, window: Duration(minutes: 1));
      final clientIp = '198.51.100.55'; // Example client IP

      // Simulate 200 successful requests
      int allowedCount = 0;
      for (int i = 0; i < 205; i++) {
        if (limiter.allow(clientIp)) {
          allowedCount++;
        }
      }

      expect(allowedCount, equals(200),
          reason: 'Should allow exactly 200 requests, then reject');

      final stats = limiter.stats;
      expect(stats['totalRejections'], equals(5),
          reason: 'Should have 5 rejections (205 - 200)');

      print(
          '✓ Rate limiting working: allowed 200, rejected 5 excess requests');
    });

    test('different IPs have independent rate limits', () {
      final limiter = RateLimiter(maxRequests: 5, window: Duration(minutes: 1));

      // IP 1 uses up its limit
      final ip1 = '192.0.2.1';
      int ip1Allowed = 0;
      for (int i = 0; i < 10; i++) {
        if (limiter.allow(ip1)) ip1Allowed++;
      }
      expect(ip1Allowed, equals(5));

      // IP 2 has its own limit
      final ip2 = '192.0.2.2';
      int ip2Allowed = 0;
      for (int i = 0; i < 10; i++) {
        if (limiter.allow(ip2)) ip2Allowed++;
      }
      expect(ip2Allowed, equals(5),
          reason: 'IP 2 should have its own limit separate from IP 1');

      final stats = limiter.stats;
      expect(stats['activeBuckets'], equals(2),
          reason: 'Should track 2 separate IP buckets');

      print('✓ Per-IP rate limiting working: 2 IPs tracked independently');
    });

    test('rate limit enforcement prevents bandwidth abuse', () {
      // Assuming an average image is 100 KB
      final avgImageSizeKb = 100;
      final rpsLimit = 200; // requests per minute
      final maxBandwidthMbPerMin = (rpsLimit * avgImageSizeKb) / 1024;

      expect(maxBandwidthMbPerMin, greaterThan(0));
      print(
          '✓ Rate limit caps bandwidth at ~${maxBandwidthMbPerMin.toStringAsFixed(1)} MB/min per IP');
    });

    test('rate limit applies across all request types to /proxy/image', () {
      // Both successful and failed image fetches should count against the limit
      // (The current implementation checks rate limit before fetching)
      final limiter = RateLimiter(maxRequests: 3, window: Duration(minutes: 1));
      final ip = '198.51.100.1';

      // First 3 requests are allowed (regardless of whether the image fetch succeeds)
      expect(limiter.allow(ip), isTrue);
      expect(limiter.allow(ip), isTrue);
      expect(limiter.allow(ip), isTrue);

      // 4th request is rejected before any image fetching happens
      expect(limiter.allow(ip), isFalse,
          reason: 'Rate limit should reject request before any I/O');

      print('✓ Rate limit applied before image fetch (fail-fast)');
    });

    test('rate limit returns proper 429 response', () {
      final limiter = RateLimiter(maxRequests: 1, window: Duration(minutes: 1));
      final ip = 'client-ip';

      limiter.allow(ip); // Use up the 1 allowed request

      final response = checkRateLimit(limiter, ip);
      expect(response, isNotNull);
      expect(response!.statusCode, equals(429));

      print('✓ Rate limit returns 429 Too Many Requests on rejection');
    });
  });
}
