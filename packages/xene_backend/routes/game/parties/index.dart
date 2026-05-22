import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('game.parties');

/// GET  /game/parties  — list user's parties
/// POST /game/parties  — create a new party
Future<Response> onRequest(RequestContext context) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  switch (context.request.method) {
    case HttpMethod.get:
      return _listParties(context);
    case HttpMethod.post:
      return _createParty(context);
    default:
      return Response(statusCode: 405);
  }
}

Future<Response> _listParties(RequestContext context) async {
  final userId = context.read<String>();
  final game = context.read<GameService>();
  final parties = await game.getUserParties(userId);
  return Response.json(body: parties);
}

Future<Response> _createParty(RequestContext context) async {
  final userId = context.read<String>();
  final game = context.read<GameService>();

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON'});
  }

  final name = (body['name'] as String?)?.trim() ?? '';
  if (name.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'name is required'});
  }

  try {
    final party = await game.createParty(userId, name);
    _logger.info('[parties] created partyId=${party['id']} for $userId');
    return Response.json(statusCode: 201, body: party);
  } on ArgumentError catch (e) {
    return Response.json(statusCode: 400, body: {'error': e.message});
  } on StateError catch (e) {
    return Response.json(statusCode: 422, body: {'error': e.message});
  }
}
