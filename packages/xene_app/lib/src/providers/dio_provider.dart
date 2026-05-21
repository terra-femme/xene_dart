import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';

const kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8080',
);

/// Shared authenticated Dio provider.
///
/// Attaches a JWT interceptor so every request automatically carries
/// `Authorization: Bearer <access_token>`. Rebuilt whenever the auth
/// state changes (session refresh, magic link callback, logout), which
/// means the token is always fresh — no manual header management in
/// individual providers.
///
/// Usage:
///   AsyncNotifier.build(): _dio = ref.watch(authenticatedDioProvider);
///   StateNotifier method:  final dio = ref.read(authenticatedDioProvider);
///   FutureProvider:        final dio = ref.watch(authenticatedDioProvider);
final authenticatedDioProvider = Provider<Dio>((ref) {
  ref.watch(authStateProvider); // rebuild when session changes

  final dio = Dio(
    BaseOptions(
      baseUrl: kBackendUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          options.headers['Authorization'] = 'Bearer ${session.accessToken}';
        }
        handler.next(options);
      },
    ),
  );

  return dio;
});
