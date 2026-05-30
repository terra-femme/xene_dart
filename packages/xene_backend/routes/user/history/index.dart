import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('user.history');

const _maxHistoryRows = 500;
const _historyTtl = Duration(days: 7);

/// GET  /user/history — list recent plays (not yet expired)
/// POST /user/history — log a play event; enforces 500-row cap per user
Future<Response> onRequest(RequestContext context) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  switch (context.request.method) {
    case HttpMethod.get:
      return _getHistory(context);
    case HttpMethod.post:
      return _logHistory(context);
    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

Future<Response> _getHistory(RequestContext context) async {
  final userId = context.read<String>();
  final db = context.read<DatabaseService>();
  _logger.info('[history] GET userId=$userId');

  try {
    await _deleteExpiredHistory(db, userId);

    final rows = await db.client
        .from('listening_history')
        .select()
        .eq('user_id', userId)
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('played_at', ascending: false)
        .limit(100);

    return Response.json(body: rows);
  } catch (e) {
    _logger.severe('[history] GET failed userId=$userId: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to load history'},
    );
  }
}

Future<Response> _logHistory(RequestContext context) async {
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

  _logger.info('[history] POST userId=$userId platform=$platform');

  try {
    await _deleteExpiredHistory(db, userId);

    // Enforce 500-row cap: delete oldest rows when at or over the limit
    final allRows = await db.client
        .from('listening_history')
        .select('id')
        .eq('user_id', userId)
        .order('played_at', ascending: true);

    final count = allRows.length;
    if (count >= _maxHistoryRows) {
      final excess = count - (_maxHistoryRows - 1);
      final toDeleteIds = allRows
          .take(excess)
          .map((r) => r['id'] as String)
          .toList();
      await db.client
          .from('listening_history')
          .delete()
          .inFilter('id', toDeleteIds);
      _logger.info(
        '[history] pruned $excess rows for userId=$userId (was $count)',
      );
    }

    final expiresAt = DateTime.now().toUtc().add(_historyTtl);
    final row = await db.client
        .from('listening_history')
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
  } catch (e) {
    _logger.severe('[history] POST insert failed userId=$userId: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to log history'},
    );
  }
}

Future<void> _deleteExpiredHistory(DatabaseService db, String userId) async {
  await db.client
      .from('listening_history')
      .delete()
      .eq('user_id', userId)
      .lte('expires_at', DateTime.now().toUtc().toIso8601String());
}
