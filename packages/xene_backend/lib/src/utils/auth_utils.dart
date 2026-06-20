import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';

final _logger = Logger('auth_utils');

/// Carries the anonymous-session flag for the authenticated request.
/// Injected by [_jwtMiddleware] alongside the userId [String].
class IsAnonymous {
  const IsAnonymous(this.value);
  final bool value;
}

/// Returns a 403 [Response] if the current user is anonymous; null otherwise.
/// Call at the top of any route handler that requires a real (non-anonymous) account.
///
/// Usage:
///   final guard = requireRealUser(context);
///   if (guard != null) return guard;
Response? requireRealUser(RequestContext context) {
  if (context.read<IsAnonymous>().value) {
    return Response.json(
      statusCode: 403,
      body: {'error': 'This action requires a real account'},
    );
  }
  return null;
}

/// Returns a 403 [Response] unless the current user has `profiles.role ==
/// 'admin'`; null otherwise. Use to gate routes that mutate GLOBAL/shared
/// content (presets, sources, artists) — without this, any signed-in account
/// could edit content everyone sees.
///
/// Async because it reads the role from the database. **Fails closed:** an
/// anonymous user, a missing profile row, a non-'admin' role, OR any lookup
/// error all yield a 403 — admin is never granted on uncertainty.
///
/// This consolidates the role check that was previously duplicated inline in
/// `monitor.dart`, `presets/.../sources/[sourceId]/index.dart`,
/// `press_scout/run.dart`, and `artists/[id]/index.dart`.
///
/// Usage:
///   final guard = await requireAdminUser(context);
///   if (guard != null) return guard;
Future<Response?> requireAdminUser(RequestContext context) async {
  // Admin implies a real (non-anonymous) account. Check that first — it also
  // avoids a needless DB round-trip for anonymous callers.
  final realGuard = requireRealUser(context);
  if (realGuard != null) return realGuard;

  final userId = context.read<String>();
  final db = context.read<DatabaseService>();

  String? role;
  try {
    final profileRes = await db.client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();
    role = profileRes?['role'] as String?;
  } catch (e) {
    // Never grant admin on an error path — fail closed.
    _logger.severe('[auth] admin role lookup failed userId=$userId: $e');
    return Response.json(
      statusCode: 403,
      body: {'error': 'Admin access required'},
    );
  }

  if (role != 'admin') {
    _logger.warning('[auth] non-admin access attempt userId=$userId');
    return Response.json(
      statusCode: 403,
      body: {'error': 'Admin access required'},
    );
  }
  return null;
}

/// Decodes the JWT payload segment to read the is_anonymous claim.
/// The JWT signature must already have been validated by middleware before
/// calling this — this is claim inspection only, not re-validation.
/// Fails closed: any decode error is treated as anonymous.
bool decodeIsAnonymous(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return true;
    final padded = base64Url.normalize(parts[1]);
    final payload = utf8.decode(base64Url.decode(padded));
    final claims = jsonDecode(payload) as Map<String, dynamic>;
    return claims['is_anonymous'] == true;
  } catch (_) {
    return true;
  }
}
