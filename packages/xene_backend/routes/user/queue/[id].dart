import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('user.queue.id');

/// DELETE /user/queue/:id — remove an item from the queue
Future<Response> onRequest(RequestContext context, String id) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final userId = context.read<String>();
  final db = context.read<DatabaseService>();
  _logger.info('[queue] DELETE id=$id userId=$userId');

  try {
    final deleted = await db.client
        .from('user_queue')
        .delete()
        .eq('id', id)
        .eq('user_id', userId)
        .select()
        .maybeSingle();

    if (deleted == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Queue item not found'},
      );
    }
    return Response.json(body: {'deleted': id});
  } catch (e) {
    _logger.severe('[queue] DELETE failed id=$id: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to remove queue item'},
    );
  }
}
