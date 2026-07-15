import 'package:flutter/foundation.dart' show debugPrint;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';
import 'config_provider.dart';

// Fallback backend URL for utilities that can't use providers (e.g. artwork_proxy.dart).
// The main Dio instance uses appConfigProvider for dynamic configuration.
const kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: kProductionBackendUrl,
);

// Refresh proactively when the access token is within this window of expiry, so
// a request doesn't go out carrying a token that lapses mid-flight.
const _kProactiveRefreshWindow = Duration(seconds: 60);

// requestOptions.extra flag marking a request that has already been retried
// after a 401, so a still-401 retry can't loop forever.
const _kAuthRetriedFlag = '__authRetried';

/// Shared authenticated Dio provider.
///
/// Attaches `Authorization: Bearer <access_token>` to every request and keeps
/// that token healthy across the Supabase session's ~1h access-token lifetime:
///
/// 1. **Proactive** — before each request, if the current access token is
///    expired (or within [_kProactiveRefreshWindow] of expiring) it refreshes
///    first, so the request carries a fresh token.
/// 2. **Reactive** — if the backend still returns 401 (e.g. the token was
///    revoked or expired between check and arrival), it refreshes once and
///    retries the original request a single time.
///
/// Refreshes are single-flighted via [refreshAccessToken] so a burst of
/// concurrent requests triggers exactly one `refreshSession()` call (rotating
/// the refresh token once) rather than racing each other.
///
/// The provider rebuilds whenever auth state changes (login, logout, refresh).
///
/// Usage:
///   AsyncNotifier.build(): _dio = ref.watch(authenticatedDioProvider);
///   StateNotifier method:  final dio = ref.read(authenticatedDioProvider);
///   FutureProvider:        final dio = ref.watch(authenticatedDioProvider);
final authenticatedDioProvider = Provider<Dio>((ref) {
  ref.watch(authStateProvider); // rebuild when session changes

  // Watch config to rebuild if it changes; use 'when' to handle async state.
  final configAsync = ref.watch(appConfigProvider);

  // Get timeout values from config or use fallbacks.
  final connectTimeoutSeconds =
      configAsync
          .whenData((config) => config.dioTimeoutConnectSeconds)
          .asData
          ?.value ??
      30;
  final receiveTimeoutSeconds =
      configAsync
          .whenData((config) => config.dioTimeoutReceiveSeconds)
          .asData
          ?.value ??
      30;
  final baseUrl =
      configAsync.whenData((config) => config.backendUrl).asData?.value ??
      kProductionBackendUrl;

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: Duration(seconds: receiveTimeoutSeconds),
      headers: {'Accept': 'application/json'},
    ),
  );

  final auth = Supabase.instance.client.auth;

  // Single-flight refresh: concurrent callers share one in-flight refresh
  // instead of each rotating the refresh token. Scoped to this provider
  // instance; a new instance (auth change) starts fresh.
  Future<String?>? refreshInFlight;
  Future<String?> refreshAccessToken() {
    return refreshInFlight ??= () async {
      try {
        final res = await auth.refreshSession();
        return res.session?.accessToken ?? auth.currentSession?.accessToken;
      } finally {
        refreshInFlight = null;
      }
    }();
  }

  bool tokenNeedsRefresh(Session session) {
    if (session.isExpired) return true;
    final expiresAt = session.expiresAt; // seconds since epoch, nullable
    if (expiresAt == null) return false;
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    return expiry.difference(DateTime.now()) <= _kProactiveRefreshWindow;
  }

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final session = auth.currentSession;
        if (session != null) {
          var token = session.accessToken;
          if (tokenNeedsRefresh(session)) {
            debugPrint(
              '[dio] access token expired/near-expiry — refreshing before ${options.path}',
            );
            // Fall back to the existing token if refresh fails (offline, etc.);
            // a 401 would then trigger the reactive path below.
            token = await refreshAccessToken() ?? token;
          }
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final is401 = error.response?.statusCode == 401;
        final alreadyRetried =
            error.requestOptions.extra[_kAuthRetriedFlag] == true;
        if (!is401 || alreadyRetried || auth.currentSession == null) {
          handler.next(error);
          return;
        }

        debugPrint(
          '[dio] 401 on ${error.requestOptions.path} — refreshing session and retrying once',
        );
        try {
          final token = await refreshAccessToken();
          if (token == null) {
            debugPrint(
              '[dio] refresh produced no token — surfacing original 401 on ${error.requestOptions.path}',
            );
            handler.next(error);
            return;
          }
          final opts = error.requestOptions
            ..extra[_kAuthRetriedFlag] = true
            ..headers['Authorization'] = 'Bearer $token';
          final response = await dio.fetch<dynamic>(opts);
          debugPrint(
            '[dio] retry after refresh SUCCEEDED on ${opts.path} (${response.statusCode})',
          );
          handler.resolve(response);
        } catch (e) {
          debugPrint(
            '[dio] refresh-and-retry FAILED on ${error.requestOptions.path}: $e',
          );
          handler.next(error);
        }
      },
    ),
  );

  return dio;
});
