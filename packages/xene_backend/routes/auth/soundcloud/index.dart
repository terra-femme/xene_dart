import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /auth/soundcloud
/// Generates a PKCE code_verifier + challenge, packs them into state,
/// and redirects the user to SoundCloud's OAuth 2.1 authorization screen.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final clientId = Platform.environment['SC_CLIENT_ID'];
  final redirectUri = Platform.environment['SC_REDIRECT_URI'];

  if (clientId == null || redirectUri == null) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'SC_CLIENT_ID and SC_REDIRECT_URI must be set'},
    );
  }

  // Allow passing user_id via query param, default to 'local_user'
  final params = context.request.uri.queryParameters;
  final userId = params['user_id'] ?? 'local_user';

  final codeVerifier = _generateCodeVerifier();
  final codeChallenge = _generateCodeChallenge(codeVerifier);

  // Pack user_id + verifier into state so the callback can retrieve both
  final state = '$userId:$codeVerifier';

  final authParams = Uri(queryParameters: {
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'scope': 'non-expiring offline_access',
    'state': state,
    'code_challenge': codeChallenge,
    'code_challenge_method': 'S256',
  }).query;

  return Response(
    statusCode: 302,
    headers: {'Location': 'https://secure.soundcloud.com/authorize?$authParams'},
  );
}

String _generateCodeVerifier() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _generateCodeChallenge(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier));
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}
