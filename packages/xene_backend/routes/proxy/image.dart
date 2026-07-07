import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:xene_backend/src/utils/rate_limiter.dart';

final _logger = Logger('proxy.image');

// Shared client: reuses pooled keep-alive connections to the CDNs instead of
// paying a fresh TCP+TLS handshake per image request.
final _dio = Dio();

// In-process byte cache. Only the web build hits this route (native loads
// CDNs directly), so a small in-memory cache absorbs repeat views without an
// external cache service. Bounded by entry count AND total bytes so it cannot
// grow past its budget on a small (0.5 GiB) container.
const _cacheMaxEntries = 300;
const _cacheMaxBytes = 40 * 1024 * 1024; // 40 MiB
const _cacheTtl = Duration(hours: 24);

class _CachedImage {
  _CachedImage(this.bytes, this.contentType) : fetchedAt = DateTime.now();
  final List<int> bytes;
  final String contentType;
  final DateTime fetchedAt;
  bool get isExpired => DateTime.now().difference(fetchedAt) > _cacheTtl;
}

// LinkedHashMap insertion order gives us cheap LRU: re-insert on hit,
// evict from the front when over budget.
final _imageCache = <String, _CachedImage>{};
int _imageCacheBytes = 0;

_CachedImage? _cacheGet(String url) {
  final entry = _imageCache.remove(url);
  if (entry == null) return null;
  if (entry.isExpired) {
    _imageCacheBytes -= entry.bytes.length;
    return null;
  }
  _imageCache[url] = entry; // move to most-recently-used position
  return entry;
}

void _cachePut(String url, _CachedImage entry) {
  final existing = _imageCache.remove(url);
  if (existing != null) _imageCacheBytes -= existing.bytes.length;
  _imageCache[url] = entry;
  _imageCacheBytes += entry.bytes.length;
  while (_imageCache.length > _cacheMaxEntries ||
      _imageCacheBytes > _cacheMaxBytes) {
    final oldestKey = _imageCache.keys.first;
    final evicted = _imageCache.remove(oldestKey)!;
    _imageCacheBytes -= evicted.bytes.length;
    _logger.fine('[proxy.image] Evicted $oldestKey from byte cache');
  }
}

/// GET /proxy/image?url=<encoded-url>
/// Proxies image requests through the backend to bypass CORS restrictions.
/// Accepts a URL-encoded image URL and returns the image with CORS headers.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final clientIp = extractClientIp(context);
  final rateLimited = checkRateLimit(imageProxyRateLimiter, clientIp);
  if (rateLimited != null) return rateLimited;

  final params = context.request.uri.queryParameters;
  final encodedUrl = params['url'];

  if (encodedUrl == null || encodedUrl.isEmpty) {
    _logger.warning('[proxy.image] Missing or empty url parameter');
    return Response(statusCode: 400, body: 'Missing url parameter');
  }

  try {
    Uri.parse(encodedUrl); // Validate it's a valid URL
  } catch (e) {
    _logger.warning('[proxy.image] Invalid URL format: $encodedUrl');
    return Response(statusCode: 400, body: 'Invalid URL format');
  }

  // Whitelist allowed domains to prevent abuse (e.g., forcing the server to fetch from arbitrary URLs)
  const allowedDomains = [
    'f4.bcbits.com',
    'f3.bcbits.com',
    'f2.bcbits.com',
    'f1.bcbits.com',
    'a.bcbits.com',
    'i1.sndcdn.com',
    'i2.sndcdn.com',
    'i3.sndcdn.com',
    'i4.sndcdn.com',
    'i5.sndcdn.com',
    'i6.sndcdn.com',
    'i7.sndcdn.com',
    'yt3.ggpht.com',
    'yt4.ggpht.com',
    'i.ytimg.com',
    'img.youtube.com',
  ];

  final uri = Uri.parse(encodedUrl);

  // SSRF guard 1: only https. Blocks file://, http://, gopher://, etc.
  if (uri.scheme != 'https') {
    _logger.warning('[proxy.image] Non-https scheme rejected: ${uri.scheme}');
    return Response(statusCode: 403, body: 'Only https URLs are allowed');
  }

  // SSRF guard 2: host must be on the CDN allowlist. Because the allowlist holds
  // only known public CDN hostnames (never raw IPs), this also rejects attempts
  // to target an IP literal like 169.254.169.254 (cloud metadata) or 127.0.0.1.
  if (!allowedDomains.contains(uri.host)) {
    _logger.warning('[proxy.image] Domain not whitelisted: ${uri.host}');
    return Response(statusCode: 403, body: 'Domain not allowed');
  }

  // SSRF guard 3 (defense in depth): if the host is somehow an IP literal, block
  // any private / loopback / link-local target outright.
  if (_isBlockedIpHost(uri.host)) {
    _logger.warning(
      '[proxy.image] Private/loopback IP host rejected: ${uri.host}',
    );
    return Response(statusCode: 403, body: 'Domain not allowed');
  }

  final cached = _cacheGet(encodedUrl);
  if (cached != null) {
    _logger.fine(
      '[proxy.image] Cache HIT — ${cached.bytes.length} bytes for $encodedUrl',
    );
    return Response.bytes(
      statusCode: 200,
      body: cached.bytes,
      headers: {
        'Content-Type': cached.contentType,
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Cache-Control': 'public, max-age=86400',
        'X-Proxy-Cache': 'HIT',
      },
    );
  }

  try {
    _logger.info('[proxy.image] Fetching from $encodedUrl');
    final response = await _dio
        .get<List<int>>(
          encodedUrl,
          options: Options(
            responseType: ResponseType.bytes,
            // SSRF guard 4: never follow redirects. The allowlist only checks the
            // initial host; a 302 from an allowed CDN to an internal address
            // (e.g. the cloud metadata endpoint) would otherwise bypass it.
            // Treat any non-2xx (including 3xx) as a failure to handle below.
            followRedirects: false,
            maxRedirects: 0,
            validateStatus: (status) => status != null && status < 400,
          ),
        )
        .timeout(const Duration(seconds: 10));

    // A redirect (3xx) reaches here because we disabled following. Refuse it
    // rather than handing the client a Location to an unvalidated host.
    final code = response.statusCode ?? 500;
    if (code >= 300 && code < 400) {
      _logger.warning('[proxy.image] Refusing upstream redirect ($code)');
      return Response(statusCode: 403, body: 'Upstream redirect not allowed');
    }

    if (response.statusCode != 200) {
      _logger.warning('[proxy.image] Upstream returned ${response.statusCode}');
      return Response(statusCode: response.statusCode ?? 500);
    }

    final bytes = response.data ?? <int>[];
    _logger.info('[proxy.image] Success — ${bytes.length} bytes');

    // Return image with CORS headers + cache headers for frontend caching
    final contentType = response.headers.value('content-type') ?? 'image/jpeg';
    if (bytes.isNotEmpty) {
      _cachePut(encodedUrl, _CachedImage(bytes, contentType));
    }
    return Response.bytes(
      statusCode: 200,
      body: bytes,
      headers: {
        'Content-Type': contentType,
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Cache-Control': 'public, max-age=86400',
      },
    );
  } catch (e) {
    _logger.severe('[proxy.image] Exception: $e');
    return Response(statusCode: 500, body: 'Proxy fetch failed');
  }
}

/// True if [host] is an IP literal in a private, loopback, or link-local range
/// that should never be reachable through the proxy. Non-IP hostnames return
/// false (they're handled by the allowlist). Covers the IPv4 ranges plus the
/// cloud metadata address (169.254.169.254) and IPv6 loopback.
bool _isBlockedIpHost(String host) {
  final h = host.toLowerCase();
  // IPv6 loopback / unspecified.
  if (h == '::1' || h == '::') return true;
  final addr = InternetAddress.tryParse(h);
  if (addr == null) return false; // not an IP literal — allowlist governs it
  if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) return true;
  if (addr.type == InternetAddressType.IPv4) {
    final p = h.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((o) => o == null))
      return true; // malformed → block
    final a = p[0]!, b = p[1]!;
    if (a == 10) return true; // 10.0.0.0/8
    if (a == 127) return true; // 127.0.0.0/8 loopback
    if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
    if (a == 192 && b == 168) return true; // 192.168.0.0/16
    if (a == 169 && b == 254)
      return true; // 169.254.0.0/16 link-local + metadata
    if (a == 0) return true; // 0.0.0.0/8
  }
  return false;
}
