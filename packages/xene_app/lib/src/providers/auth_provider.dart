import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Streams every auth state change (sign-in, sign-out, token refresh).
/// Widgets that need to react to auth transitions watch this directly.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

/// The currently authenticated user, or null if no session exists.
/// Watches authStateProvider so Riverpod rebuilds on every auth transition —
/// without this watch, the provider returns a one-time snapshot and misses
/// the session that arrives after a magic link callback.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return Supabase.instance.client.auth.currentUser;
});

/// The authenticated user's UUID as a plain string.
///
/// Fail-closed: assert fires in debug builds if accessed without a session.
/// user!.id on the return line throws a null-dereference in release builds
/// if the route guard has a hole — so this remains fail-closed in production.
///
/// The route guard in main.dart redirects unauthenticated users to /auth
/// before any provider that calls this can run. If this fires without a user,
/// the guard has a hole — surface it immediately rather than silently
/// falling back to a shared 'local_user' key.
final currentUserIdProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  assert(
    user != null,
    'currentUserIdProvider accessed without an authenticated session',
  );
  return user!.id;
});

/// The user's role from the profiles table ('user' or 'admin').
/// Returns 'user' as a safe default if the profile row does not exist yet
/// (e.g. accounts created before the signup trigger was added).
/// Uses maybeSingle() — single() throws on a missing row.
final userRoleProvider = FutureProvider<String>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final res = await Supabase.instance.client
      .from('profiles')
      .select('role')
      .eq('id', userId)
      .maybeSingle();
  return (res?['role'] as String?) ?? 'user';
});

/// Convenience bool: true if the current user has role = 'admin'.
/// Defaults to false while loading or on error — never shows admin UI
/// to a user whose role has not been confirmed.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final role = await ref.watch(userRoleProvider.future);
  return role == 'admin';
});
