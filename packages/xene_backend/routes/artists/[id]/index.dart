import 'dart:async';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';

final _logger = Logger('artists.[id]');

/// PATCH /artists/:id  — partial field update
/// DELETE /artists/:id — remove artist from follow list
Future<Response> onRequest(RequestContext context, String id) async {
  final userId = context.read<String>();

  final db = context.read<DatabaseService>();

  switch (context.request.method) {
    case HttpMethod.patch:
      return _patchArtist(context, db, id, userId);
    case HttpMethod.delete:
      return _deleteArtist(context, db, id, userId);
    default:
      return Response(statusCode: 405);
  }
}

const _kReadOnlyFields = {
  'id',
  'user_id',
  'created_at',
  'is_label',
  'confidence',
  'identity_confidence',
  'coverage_level',
};

const _kValidEntityTypes = {
  'artist',
  'band',
  'label',
  'organization',
  'venue',
  'brand',
};

Future<Response> _patchArtist(
  RequestContext context,
  DatabaseService db,
  String id,
  String userId,
) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  // Strip read-only and computed fields
  for (final key in _kReadOnlyFields) {
    body.remove(key);
  }

  // Normalize entity_type if present
  if (body.containsKey('entity_type')) {
    final et = (body['entity_type'] as String? ?? 'artist').toLowerCase();
    body['entity_type'] = _kValidEntityTypes.contains(et) ? et : 'artist';
  }

  if (body.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'No updatable fields provided'},
    );
  }

  // Ownership check: only the user who created the artist (or an admin) can PATCH.
  final artist = await db.getArtistById(id);
  if (artist == null) {
    return Response.json(statusCode: 404, body: {'error': 'Artist not found'});
  }
  final createdBy = artist['created_by'] as String?;
  if (createdBy != userId) {
    // Not the creator — check for admin role before rejecting.
    final profileRes = await db.client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();
    final role = profileRes?['role'] as String? ?? 'user';
    if (role != 'admin') {
      _logger.warning(
        '[artists.$id] PATCH rejected: user=$userId is not creator ($createdBy) or admin',
      );
      return Response.json(
        statusCode: 403,
        body: {'error': 'Only the artist creator can modify this artist'},
      );
    }
  }

  final updated = await db.updateArtist(id, userId, body);
  if (updated == null) {
    return Response.json(statusCode: 404, body: {'error': 'Artist not found'});
  }

  unawaited(
    db.logArtistAction(
      userId: userId,
      artistId: id,
      action: 'update',
      changedFields: body,
    ),
  );
  final et = updated['entity_type'] as String?;
  return Response.json(
    body: {...updated, 'is_label': et == 'label' || et == 'organization'},
  );
}

Future<Response> _deleteArtist(
  RequestContext context,
  DatabaseService db,
  String id,
  String userId,
) async {
  final guard = requireRealUser(context);
  if (guard != null) return guard;

  await db.deleteArtist(id, userId);
  unawaited(db.logArtistAction(userId: userId, artistId: id, action: 'delete'));
  return Response(statusCode: 204);
}
