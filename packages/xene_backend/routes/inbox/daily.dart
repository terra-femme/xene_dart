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
      // Must be bodyless — do NOT use Response.json here. A 204 must not carry
      // a body (RFC 9110 §15.3.5), but Response.json encodes one anyway and it
      // really does go out on the wire: `content-length: 52` followed by 52
      // bytes of JSON. Browsers reject that and fail the request at the network
      // layer, which reaches Dio as a connectionError carrying no status code —
      // so the client's `statusCode == 204` branch never runs and a quiet feed
      // day is indistinguishable from an outage. curl hides this (it stops
      // reading the body on a 204); only a raw socket or a browser shows it.
      // Guarded by test/inbox_daily_204_framing_test.dart.
      return Response(statusCode: HttpStatus.noContent);
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
