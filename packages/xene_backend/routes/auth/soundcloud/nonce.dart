import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:xene_backend/src/utils/sc_nonce_store.dart';

final _logger = Logger('auth.soundcloud.nonce');

/// POST /auth/soundcloud/nonce
///
/// Authenticated endpoint (non-anonymous JWT required via _middleware.dart).
/// Generates a PKCE code_verifier + challenge, stores them under a random
/// nonce, and returns the full SoundCloud authorization URL for the client
/// to open in the system browser.
///
/// The nonce replaces the old ?user_id= query param approach, which allowed
/// any caller to initiate OAuth on behalf of an arbitrary user ID.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  // JWT is validated by middleware; userId and IsAnonymous are injected into context.
  final userId = context.read<String>();

  // Reject anonymous sessions — SC OAuth requires a real account.
  final guard = requireRealUser(context);
  if (guard != null) {
    _logger.warning('[sc/nonce] Rejected anonymous user=$userId');
    return Response.json(
      statusCode: 403,
      body: {'error': 'SoundCloud connection requires a real account'},
    );
  }

  final clientId = Platform.environment['SC_CLIENT_ID'];
  final redirectUri = Platform.environment['SC_REDIRECT_URI'];
  if (clientId == null || redirectUri == null) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'SC_CLIENT_ID and SC_REDIRECT_URI must be set'},
    );
  }

  final codeVerifier = _generateCodeVerifier();
  final codeChallenge = _generateCodeChallenge(codeVerifier);
  final nonce = _generateNonce();

  storeScNonce(nonce, userId, codeVerifier);
  _logger.info('[sc/nonce] Stored nonce for user=$userId');

  final authUrl = Uri(
    scheme: 'https',
    host: 'secure.soundcloud.com',
    path: '/authorize',
    queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'non-expiring offline_access',
      'state': nonce,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    },
  ).toString();

  return Response.json(body: {'auth_url': authUrl});
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

String _generateNonce() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}
