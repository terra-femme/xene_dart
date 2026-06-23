import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/dragonfly_cache_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('monitor_cache');

/// GET /monitor/cache
/// Returns cache metrics — hit/miss ratio, latency, memory usage.
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
    _logger.warning('[monitor_cache] Non-admin access attempt userId=$userId');
    return Response.json(
      statusCode: 403,
      body: {'error': 'Admin access required'},
    );
  }

  try {
    final cache = DragonflyCache();
    final metrics = await cache.getMetrics();

    _logger.info('[monitor_cache] Metrics retrieved for admin userId=$userId');

    return Response.json(body: metrics);
  } catch (e) {
    _logger.severe('[monitor_cache] Failed to get metrics: $e');
    return Response.json(
      statusCode: 500,
      body: {
        'error': 'Failed to retrieve cache metrics',
        'details': e.toString(),
      },
    );
  }
}
