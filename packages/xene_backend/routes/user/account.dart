import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('user.account');

/// DELETE /user/account
/// Permanently deletes the authenticated user's Supabase auth entry.
/// Cascades to all user-owned data via foreign key constraints.
/// Blocked for anonymous sessions — requires a real account.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final guard = requireRealUser(context);
  if (guard != null) return guard;

  final userId = context.read<String>();
  final db = context.read<DatabaseService>();

  _logger.info('[account] DELETE request userId=$userId');

  try {
    await db.client.auth.admin.deleteUser(userId);
    _logger.info('[account] Deleted auth user userId=$userId');
    return Response.json(body: {'deleted': true});
  } catch (e) {
    _logger.severe('[account] Failed to delete userId=$userId: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to delete account'},
    );
  }
}
