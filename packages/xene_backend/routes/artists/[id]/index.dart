import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/database.dart';

/// PATCH /artists/:id  — partial field update
/// DELETE /artists/:id — remove artist from follow list
Future<Response> onRequest(RequestContext context, String id) async {
  final userId = context.request.headers['x-user-id'];
  if (userId == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'X-User-Id header required'},
    );
  }

  final db = context.read<DatabaseService>();

  switch (context.request.method) {
    case HttpMethod.patch:
      return _patchArtist(context, db, id, userId);
    case HttpMethod.delete:
      return _deleteArtist(db, id, userId);
    default:
      return Response(statusCode: 405);
  }
}

const _kReadOnlyFields = {
  'id', 'user_id', 'created_at', 'is_label',
  'confidence', 'identity_confidence', 'coverage_level',
};

const _kValidEntityTypes = {
  'artist', 'band', 'label', 'organization', 'venue', 'brand',
};

Future<Response> _patchArtist(
  RequestContext context,
  DatabaseService db,
  String id,
  String userId,
) async {
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

  final updated = await db.updateArtist(id, userId, body);
  if (updated == null) {
    return Response.json(statusCode: 404, body: {'error': 'Artist not found'});
  }

  final et = updated['entity_type'] as String?;
  return Response.json(body: {
    ...updated,
    'is_label': et == 'label' || et == 'organization',
  });
}

Future<Response> _deleteArtist(
  DatabaseService db,
  String id,
  String userId,
) async {
  await db.deleteArtist(id, userId);
  return Response(statusCode: 204);
}
