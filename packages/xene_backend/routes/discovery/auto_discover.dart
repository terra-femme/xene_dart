import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/discovery_service.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';

final _logger = Logger('discovery.auto_discover');

/// GET /discovery/auto-discover
/// Runs the LLM Relational Identity Walk for an artist.
/// Does NOT write to the database — returns candidate profile only.
///
/// Query params:
///   name (required): artist name to discover
///   sc_profile_url (optional): known SoundCloud profile URL to seed the walk
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final rateLimited = checkRateLimit(discoveryRateLimiter, userId);
  if (rateLimited != null) return rateLimited;

  final params = context.request.uri.queryParameters;
  final name = params['name']?.trim() ?? '';

  if (name.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Query param "name" is required'},
    );
  }

  final scProfileUrl = params['sc_profile_url'];
  final discovery = context.read<DiscoveryService>();
  final soundcloud = context.read<SoundCloudService>();

  _logger.info(
    '[auto_discover] ▶ REQUEST RECEIVED name="$name" scProfileUrl="$scProfileUrl"',
  );
  _logger.info('[auto_discover] all query params: ${params}');

  // If SC profile URL provided, resolve it to get the bio
  String? scBio;
  String? scUsername;
  if (scProfileUrl != null && scProfileUrl.isNotEmpty) {
    // Validate host before making any upstream request.
    final parsedScUrl = Uri.tryParse(scProfileUrl);
    final scHost = parsedScUrl?.host.toLowerCase() ?? '';
    if (parsedScUrl == null ||
        parsedScUrl.scheme != 'https' ||
        (scHost != 'soundcloud.com' && scHost != 'www.soundcloud.com')) {
      _logger.warning(
        '[auto_discover] Rejected sc_profile_url with invalid host: $scProfileUrl',
      );
      return Response.json(
        statusCode: 400,
        body: {'error': 'sc_profile_url must be an https://soundcloud.com URL'},
      );
    }
    _logger.info('[auto_discover] → resolving SC profile URL: $scProfileUrl');
    try {
      final profile = await soundcloud.resolveProfileUrl(scProfileUrl);
      if (profile == null) {
        _logger.warning(
          '[auto_discover] ⚠ SC resolve returned null for $scProfileUrl — continuing without bio',
        );
      } else {
        scBio = profile['description'] as String?;
        scUsername = profile['permalink'] as String?;
        _logger.info(
          '[auto_discover] SC resolve OK: id=${profile['id']} permalink=$scUsername followers=${profile['followers_count']}',
        );
        final bioPreview = scBio?.substring(0, scBio.length.clamp(0, 120));
        _logger.info(
          '[auto_discover] bio length=${scBio?.length ?? 0} bio preview="$bioPreview"',
        );
      }
    } catch (e) {
      _logger.warning('[auto_discover] ⚠ SC resolve threw (non-fatal): $e');
    }
  } else {
    _logger.info('[auto_discover] no scProfileUrl — skipping SC resolve');
  }

  _logger.info(
    '[auto_discover] → calling DiscoveryService.autoDiscover name="$name" scUsername="$scUsername"',
  );

  try {
    final result = await discovery.autoDiscover(
      name,
      scBio: scBio,
      scProfileUrl: scProfileUrl,
      scUsername: scUsername,
      skipLlm: true,
    );

    _logger.info(
      '[auto_discover] ← DiscoveryService returned ${result.length} fields',
    );
    _logger.info('[auto_discover] result keys: ${result.keys.toList()}');
    _logger.info(
      '[auto_discover] name=${result['name']} soundcloud_url=${result['soundcloud_url']} soundcloud_username=${result['soundcloud_username']}',
    );
    _logger.info(
      '[auto_discover] identity_confidence=${result['identity_confidence']} coverage_level=${result['coverage_level']} confidence=${result['confidence']}',
    );
    _logger.info(
      '[auto_discover] has analysis: ${result.containsKey('analysis')} has youtube: ${result.containsKey('youtube_url')} has spotify: ${result.containsKey('spotify_id')}',
    );

    if (result.isEmpty) {
      _logger.warning(
        '[auto_discover] ⚠ result is EMPTY MAP — discovery returned nothing',
      );
    }

    return Response.json(body: result);
  } catch (e, st) {
    _logger.severe('[auto_discover] ✗ UNEXPECTED ERROR: $e');
    _logger.severe('[auto_discover] stacktrace: $st');
    return Response.json(statusCode: 500, body: {'error': 'Discovery failed'});
  }
}
