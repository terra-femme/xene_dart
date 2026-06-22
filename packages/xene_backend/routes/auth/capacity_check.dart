import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/capacity_service.dart';

final _logger = Logger('auth.capacity_check');

/// GET /auth/capacity-check
/// Public endpoint (no auth required) — returns whether new signups are allowed.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final capacity = context.read<CapacityService>();

  try {
    final status = await capacity.getStatus();
    final signupsAllowed = status.userCount < 2000;

    _logger.info(
      '[capacity_check] users=${status.userCount}/2000 signups=${signupsAllowed ? "OPEN" : "CLOSED"}',
    );

    return Response.json(
      body: {
        'signups_allowed': signupsAllowed,
        'user_count': status.userCount,
        'user_cap': 2000,
        'user_cap_percent': status.userCapPercent,
        'message': signupsAllowed
            ? 'Signups are open'
            : 'Signups temporarily disabled — user capacity reached',
      },
    );
  } catch (e) {
    _logger.severe('[capacity_check] Error checking capacity: $e');
    return Response.json(
      statusCode: 500,
      body: {
        'error': 'Could not check signup capacity',
        'signups_allowed': true,
      },
    );
  }
}
