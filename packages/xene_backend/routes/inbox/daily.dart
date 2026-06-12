import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/daily_inbox_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('inbox.daily');

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final service = context.read<DailyInboxService>();
  final userId = context.read<String>();
  final isAnon = context.read<IsAnonymous>().value;

  _logger.info('[inbox.daily] GET userId=$userId isAnon=$isAnon');

  try {
    final digest = await service.getOrGenerate(userId: userId, isAnon: isAnon);
    if (digest == null) {
      return Response.json(
        statusCode: HttpStatus.noContent,
        body: {'message': 'No tracks dropped in the last 24 hours'},
      );
    }
    return Response.json(body: digest);
  } catch (e, stack) {
    _logger.severe('[inbox.daily] failed', e, stack);
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to load daily inbox'},
    );
  }
}
