import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/api_analytics_service.dart';
import 'package:xene_backend/src/services/gemini_key_rotator.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';

final _logger = Logger('monitor');

/// GET /monitor
/// Returns live in-memory stats — LLM usage, API call history, rate-limiter state.
/// Requires admin role (profiles.role = 'admin').
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final db = context.read<DatabaseService>();

  final profileRes = await db.client
      .from('profiles')
      .select('role')
      .eq('id', userId)
      .maybeSingle();
  final role = profileRes?['role'] as String? ?? 'user';
  if (role != 'admin') {
    _logger.warning('[monitor] Non-admin access attempt userId=$userId');
    return Response.json(
      statusCode: 403,
      body: {'error': 'Admin access required'},
    );
  }

  final rotator = context.read<GeminiKeyRotator>();
  final apiAnalytics = context.read<ApiAnalyticsService>();

  return Response.json(
    body: {
      ...rotator.stats,
      'api': apiAnalytics.stats,
      'rateLimits': {
        'feedMerged': feedMergedRateLimiter.stats,
        'forceRefresh': forceRefreshRateLimiter.stats,
        'discovery': discoveryRateLimiter.stats,
        'pressScout': pressScoutRateLimiter.stats,
      },
    },
  );
}
