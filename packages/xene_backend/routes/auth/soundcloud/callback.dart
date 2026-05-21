import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/token_store.dart';

const _kScTokenUrl = 'https://secure.soundcloud.com/oauth/token';

/// GET /auth/soundcloud/callback
/// SoundCloud redirects here with ?code=...&state=...
/// state encodes "userId:codeVerifier" set during initiation.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final queryParams = context.request.uri.queryParameters;
  final code = queryParams['code'];
  final state = queryParams['state'];

  if (code == null || state == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'code and state query parameters required'},
    );
  }

  // Unpack state: format is "userId:codeVerifier"
  final colonIndex = state.indexOf(':');
  if (colonIndex == -1) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Invalid state format — expected userId:codeVerifier'},
    );
  }
  final userId = state.substring(0, colonIndex);
  final codeVerifier = state.substring(colonIndex + 1);

  final clientId = Platform.environment['SC_CLIENT_ID'];
  final clientSecret = Platform.environment['SC_CLIENT_SECRET'];
  final redirectUri = Platform.environment['SC_REDIRECT_URI'];
  final backendUrl =
      Platform.environment['BACKEND_URL'] ?? 'http://localhost:8080';

  if (clientId == null || clientSecret == null || redirectUri == null) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'SoundCloud environment variables not configured'},
    );
  }

  try {
    final dio = Dio();
    final resp = await dio.post<Map<String, dynamic>>(
      _kScTokenUrl,
      data: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
        'code': code,
        'code_verifier': codeVerifier,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'accept': 'application/json; charset=utf-8'},
      ),
    );

    final accessToken = resp.data!['access_token'] as String;
    final refreshToken = resp.data!['refresh_token'] as String?;
    final expiresIn = resp.data!['expires_in'];
    String? expiresAt;
    if (expiresIn != null) {
      final seconds = (expiresIn as num).toInt();
      expiresAt = DateTime.now()
          .toUtc()
          .add(Duration(seconds: seconds))
          .toIso8601String();
    }

    final tokenStore = context.read<TokenStore>();
    final encrypted = tokenStore.encryptToken(accessToken);

    final db = context.read<DatabaseService>();
    await db.savePlatformConnection({
      'user_id': userId,
      'platform': 'soundcloud',
      'encrypted_token': encrypted,
      if (refreshToken != null) 'refresh_token': refreshToken,
      if (expiresAt != null) 'expires_at': expiresAt,
    });

    return Response(
      statusCode: 302,
      headers: {'Location': '$backendUrl/auth/soundcloud/done'},
    );
  } on DioException catch (e) {
    return Response.json(
      statusCode: 400,
      body: {
        'error': 'SoundCloud token exchange failed',
        'detail': e.response?.data?.toString() ?? e.message,
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Internal error during token storage: $e'},
    );
  }
}
