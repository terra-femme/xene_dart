import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/analysis_service.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('user.queue');

/// GET  /user/queue — list the authenticated user's queue ordered by position
/// POST /user/queue — add a feed item to the end of the queue
Future<Response> onRequest(RequestContext context) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  switch (context.request.method) {
    case HttpMethod.get:
      return _getQueue(context);
    case HttpMethod.post:
      return _addToQueue(context);
    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

Future<Response> _getQueue(RequestContext context) async {
  final userId = context.read<String>();
  final db = context.read<DatabaseService>();
  _logger.info('[queue] GET userId=$userId');

  try {
    final rows = await db.client
        .from('user_queue')
        .select()
        .eq('user_id', userId)
        .order('position', ascending: true);

    return Response.json(body: rows);
  } catch (e) {
    _logger.severe('[queue] GET failed userId=$userId: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to load queue'},
    );
  }
}

Future<Response> _addToQueue(RequestContext context) async {
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

  _logger.info('[queue] POST userId=$userId platform=$platform');

  try {
    // Determine next position (max + 1)
    final existing = await db.client
        .from('user_queue')
        .select('position')
        .eq('user_id', userId)
        .order('position', ascending: false)
        .limit(1);

    final maxPos = existing.isEmpty
        ? -1
        : (existing.first['position'] as int? ?? -1);

    final row = await db.client
        .from('user_queue')
        .insert({
          'user_id': userId,
          'platform': platform,
          'external_url': externalUrl,
          'track_id': body['track_id'],
          'title': body['title'],
          'artist_name': body['artist_name'],
          'artwork_url': body['artwork_url'],
          'duration_seconds': body['duration_seconds'],
          'position': maxPos + 1,
        })
        .select()
        .single();

    // Fire-and-forget track analysis — does not block the queue response
    final trackId = body['track_id'] as String?;
    if (trackId != null) {
      final analysisService = context.read<AnalysisService>();
      unawaited(
        analysisService.analyzeTrack(platform, trackId).catchError((Object e) {
          _logger.warning('[queue] analyzeTrack failed trackId=$trackId: $e');
        }),
      );
    }

    return Response.json(statusCode: HttpStatus.created, body: row);
  } on Exception catch (e) {
    final msg = e.toString();
    // Unique constraint: same URL already in queue
    if (msg.contains('23505') || msg.contains('unique')) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Track already in queue'},
      );
    }
    _logger.severe('[queue] POST insert failed userId=$userId: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to add to queue'},
    );
  }
}
