import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('user.saved');

/// GET  /user/saved — list saved items that have not yet expired
/// POST /user/saved — bookmark an item (from the Winamp player queue)
Future<Response> onRequest(RequestContext context) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  switch (context.request.method) {
    case HttpMethod.get:
      return _getSaved(context);
    case HttpMethod.post:
      return _addSaved(context);
    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

Future<Response> _getSaved(RequestContext context) async {
  final userId = context.read<String>();
  final db = context.read<DatabaseService>();
  _logger.info('[saved] GET userId=$userId');

  try {
    final rows = await db.client
        .from('saved_items')
        .select()
        .eq('user_id', userId)
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('saved_at', ascending: false);

    return Response.json(body: rows);
  } catch (e) {
    _logger.severe('[saved] GET failed userId=$userId: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to load saved items'},
    );
  }
}

Future<Response> _addSaved(RequestContext context) async {
  final userId = context.read<String>();
  final db = context.read<DatabaseService>();

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Invalid JSON body'},
    );
  }

  final platform = body['platform'] as String?;
  final externalUrl = body['external_url'] as String?;
  if (platform == null || externalUrl == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'platform and external_url are required'},
    );
  }

  _logger.info('[saved] POST userId=$userId platform=$platform');

  try {
    final expiresAt = DateTime.now().toUtc().add(const Duration(days: 31));
    final row = await db.client
        .from('saved_items')
        .insert({
          'user_id': userId,
          'platform': platform,
          'external_url': externalUrl,
          'track_id': body['track_id'],
          'title': body['title'],
          'artist_name': body['artist_name'],
          'artwork_url': body['artwork_url'],
          'duration_seconds': body['duration_seconds'],
          'expires_at': expiresAt.toIso8601String(),
        })
        .select()
        .single();

    return Response.json(statusCode: HttpStatus.created, body: row);
  } on Exception catch (e) {
    final msg = e.toString();
    if (msg.contains('23505') || msg.contains('unique')) {
      final existing = await db.client
          .from('saved_items')
          .select()
          .eq('user_id', userId)
          .eq('external_url', externalUrl)
          .maybeSingle();
      if (existing != null) {
        return Response.json(body: existing);
      }
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Item already saved'},
      );
    }
    _logger.severe('[saved] POST insert failed userId=$userId: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to save item'},
    );
  }
}
