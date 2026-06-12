import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/rate_limiter.dart';

final _logger = Logger('bug_report');

const _minMessageLength = 10;
const _maxMessageLength = 1000;
const _maxPlatformLength = 32;
const _allowedPlatforms = {'flutter', 'web', 'ios', 'android', 'windows'};

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final userId = context.read<String>();
  final isAnon = context.read<IsAnonymous>().value;
  final db = context.read<DatabaseService>();
  final clientIp = extractClientIp(context);

  final cooldownLimited = checkRateLimit(
    bugReportCooldownRateLimiter,
    userId,
  );
  if (cooldownLimited != null) return cooldownLimited;

  final userLimited = checkRateLimit(bugReportUserRateLimiter, userId);
  if (userLimited != null) return userLimited;

  final ipLimited = checkRateLimit(bugReportIpRateLimiter, clientIp);
  if (ipLimited != null) return ipLimited;

  try {
    final decoded = await context.request.json();
    if (decoded is! Map<String, dynamic>) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'JSON object body is required'},
      );
    }

    final rawMessage = decoded['message'];
    if (rawMessage is! String) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'message is required'},
      );
    }

    final message = rawMessage.trim();
    if (message.length < _minMessageLength) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {
          'error': 'message must be at least $_minMessageLength characters',
        },
      );
    }
    if (message.length > _maxMessageLength) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {
          'error': 'message must be $_maxMessageLength characters or less',
        },
      );
    }

    final rawPlatform = decoded['platform'];
    final platform = rawPlatform is String ? rawPlatform.trim() : null;
    if (platform != null && platform.length > _maxPlatformLength) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'platform is too long'},
      );
    }
    if (platform != null &&
        platform.isNotEmpty &&
        !_allowedPlatforms.contains(platform.toLowerCase())) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'unsupported platform'},
      );
    }

    await db.client.from('bug_reports').insert({
      'user_id': userId,
      'is_anonymous': isAnon,
      'message': message,
      if (platform != null && platform.isNotEmpty)
        'platform': platform.toLowerCase(),
    });

    _logger.info(
      '[bug_report] submitted user=$userId isAnon=$isAnon ip=$clientIp platform=$platform '
      'length=${message.length}',
    );

    return Response.json(statusCode: HttpStatus.created, body: {'ok': true});
  } catch (e, stack) {
    _logger.severe('[bug_report] failed', e, stack);
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to submit bug report'},
    );
  }
}
