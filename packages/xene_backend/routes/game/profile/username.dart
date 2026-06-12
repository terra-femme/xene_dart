import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/audit_logger.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('game.profile.username');

/// GET /game/profile/username       — get current user's username
/// PUT /game/profile/username       — set or update username
Future<Response> onRequest(RequestContext context) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  switch (context.request.method) {
    case HttpMethod.get:
      return _getUsername(context);
    case HttpMethod.put:
      return _setUsername(context);
    default:
      return Response(statusCode: 405);
  }
}

Future<Response> _getUsername(RequestContext context) async {
  final userId = context.read<String>();
  final game = context.read<GameService>();
  final username = await game.getUsername(userId);
  return Response.json(body: {'username': username});
}

Future<Response> _setUsername(RequestContext context) async {
  final userId = context.read<String>();
  final game = context.read<GameService>();

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON'});
  }

  final username = (body['username'] as String?)?.trim() ?? '';
  if (username.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'username is required'},
    );
  }

  final error = await game.setUsername(userId, username);
  if (error != null) {
    return Response.json(statusCode: 422, body: {'error': error});
  }

  _logger.info('[username] set userId=$userId username=$username');
  final db = context.read<DatabaseService>();
  await logSecurityEvent(
    db.client,
    action: 'username_set',
    userId: userId,
    metadata: {'username': username},
  );
  return Response.json(body: {'username': username});
}
