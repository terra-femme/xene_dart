import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:dio/dio.dart' hide Response;

final _logger = Logger('proxy.image');

/// GET /proxy/image?url=<encoded-url>
/// Proxies image requests through the backend to bypass CORS restrictions.
/// Accepts a URL-encoded image URL and returns the image with CORS headers.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

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
  ];

  final uri = Uri.parse(encodedUrl);
  if (!allowedDomains.contains(uri.host)) {
    _logger.warning('[proxy.image] Domain not whitelisted: ${uri.host}');
    return Response(statusCode: 403, body: 'Domain not allowed');
  }

  try {
    _logger.info('[proxy.image] Fetching from $encodedUrl');
    final dio = Dio();
    final response = await dio
        .get<List<int>>(
          encodedUrl,
          options: Options(responseType: ResponseType.bytes),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      _logger.warning('[proxy.image] Upstream returned ${response.statusCode}');
      return Response(statusCode: response.statusCode ?? 500);
    }

    final bytes = response.data ?? <int>[];
    _logger.info('[proxy.image] Success — ${bytes.length} bytes');

    // Return image with CORS headers + cache headers for frontend caching
    final contentType = response.headers.value('content-type') ?? 'image/jpeg';
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
