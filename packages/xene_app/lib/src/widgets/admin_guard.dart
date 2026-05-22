import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xene_app/src/providers/auth_provider.dart';

// Mirrors the same flag used in xene_header.dart — must stay in sync.
// When true in a debug build, bypasses the DB role check so the dev
// workflow (XENE_FORCE_DEV_MENU=true) can reach /dev/* routes without
// a real admin account in Supabase.
const _forceDevAccess = bool.fromEnvironment('XENE_FORCE_DEV_MENU');

/// Wraps a route that requires admin role (profiles.role = 'admin').
///
/// Debug bypass: if XENE_FORCE_DEV_MENU=true is passed as a --dart-define
/// AND the build is a debug build, the guard is skipped. This matches the
/// same condition used by xene_header.dart to show the DEV menu button —
/// if the menu is visible, the routes it exposes must be reachable.
///
/// Production: only profiles.role = 'admin' grants access. All other
/// sessions (including anonymous) are redirected to '/'.
///
/// Usage in go_router:
///   GoRoute(
///     path: '/dev/monitor',
///     builder: (context, state) => const AdminGuard(child: MonitorScreen()),
///   )
class AdminGuard extends ConsumerWidget {
  const AdminGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bypass in local dev when XENE_FORCE_DEV_MENU=true — same condition
    // as the header's showDevMenu flag.
    if (kDebugMode && _forceDevAccess) return child;

    final isAdminAsync = ref.watch(isAdminProvider);

    return isAdminAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
      ),
      error: (_, __) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/');
        });
        return const Scaffold(
          backgroundColor: Colors.white,
          body: SizedBox.shrink(),
        );
      },
      data: (isAdmin) {
        if (!isAdmin) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/');
          });
          return const Scaffold(
            backgroundColor: Colors.white,
            body: SizedBox.shrink(),
          );
        }
        return child;
      },
    );
  }
}
