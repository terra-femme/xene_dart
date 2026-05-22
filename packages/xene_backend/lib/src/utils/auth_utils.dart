import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';

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
