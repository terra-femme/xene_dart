import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:device_preview_plus/device_preview_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:xene_app/src/screens/auth_screen.dart';

import 'package:xene_app/src/layout/xene_layout_metrics.dart';
import 'package:xene_app/src/layout/xene_responsive_debug.dart';
import 'package:xene_app/src/screens/feed_screen.dart';
import 'package:xene_app/src/screens/artists_screen.dart';
import 'package:xene_app/src/screens/network_screen.dart';
import 'package:xene_app/src/screens/preset_playground_screen.dart';
import 'package:xene_app/src/screens/monitor_screen.dart';
import 'package:xene_app/src/widgets/xene_header.dart';
import 'package:xene_app/src/widgets/xene_sidebar.dart';
import 'package:xene_app/src/widgets/xene_draggable_sheet.dart';
import 'package:xene_app/src/widgets/logo_pip_player.dart';
import 'package:xene_app/src/sandbox/sandbox_preview.dart';
import 'package:xene_app/src/widgets/loading_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  // Auto sign-in anonymously so there is always a valid JWT from first launch.
  // Features that require a real account (custom preset, following, SC connect)
  // check isAnonymousProvider and show a sign-up gate rather than blocking all access.
  if (Supabase.instance.client.auth.currentUser == null) {
    await Supabase.instance.client.auth.signInAnonymously();
  }

  // app_links is mobile-only — web handles the magic link redirect automatically
  // via Supabase's built-in URL fragment detection, no listener needed.
  if (!kIsWeb) {
    final appLinks = AppLinks();
    appLinks.uriLinkStream.listen((uri) {
      Supabase.instance.client.auth.getSessionFromUrl(uri);
    });
  }

  // Await font loading so the first frame always renders in the correct fonts.
  if (kIsWeb) {
    await GoogleFonts.pendingFonts([GoogleFonts.archivo(), GoogleFonts.teko()]);
  }

  // Refresh router whenever auth state changes (login, logout, token refresh).
  Supabase.instance.client.auth.onAuthStateChange.listen((_) {
    _router.refresh();
  });

  runApp(
    DevicePreview(
      enabled: !kReleaseMode,
      builder: (context) => const ProviderScope(child: XeneApp()),
    ),
  );
}

// Full-page layout for ARTISTS and NETWORK — no sidebar, slim top bar with back nav.
class _InnerPageLayout extends StatelessWidget {
  const _InnerPageLayout({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: topPadding + 48,
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: topPadding),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.chevron_left,
                                size: 20,
                                color: Color(0xFF888888),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'FEED',
                                style: GoogleFonts.teko(
                                  fontSize: 14,
                                  color: const Color(0xFF888888),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.teko(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 72), // balance the back button
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFE0E0E0), height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class PageLayout extends StatelessWidget {
  const PageLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final metrics = XeneLayoutMetrics.fromConstraints(
          constraints: constraints,
          safePadding: mediaQuery.padding,
          viewInsets: mediaQuery.viewInsets,
          textScaleFactor: mediaQuery.textScaler.scale(1),
        );
        final double topOffset = metrics.headerHeight;

        XeneResponsiveDebug.mediaQuery('PageLayout', mediaQuery);
        XeneResponsiveDebug.constraints('PageLayout', constraints);
        XeneResponsiveDebug.values('PageLayout.metrics', metrics.toDebugMap());

        return XeneLayoutScope(
          metrics: metrics,
          child: Scaffold(
            backgroundColor: Colors.white,
            body: Stack(
              children: [
                // 1. Sidebar & Content Area — always at full opacity.
                // The LoadingOverlay covers everything until reveal is complete.
                Column(
                  children: [
                    SizedBox(height: topOffset),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const XeneSidebar(),
                          Expanded(
                            child: Container(color: Colors.white, child: child),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // 2. Fixed Header
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: XeneHeader(),
                ),

                // 3. Draggable Sheet
                const XeneDraggableSheet(),

                // 4. Logo PiP Player
                const LogoPipPlayer(),

                // 5. Loading Overlay (topmost — covers everything on first load)
                const LoadingOverlay(),
              ],
            ),
          ),
        );
      },
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isOnAuth = state.matchedLocation == '/auth';
    // Only redirect away from /auth for real (non-anonymous) accounts.
    // Anonymous users reach /auth via feature gates and should not be bounced.
    if (session != null && !(session.user.isAnonymous) && isOnAuth) return '/';
    return null;
  },
  routes: [
    // /auth is a top-level route — intentionally outside ShellRoute/PageLayout.
    // PageLayout contains XeneSidebar and XeneHeader which watch authenticated
    // providers. Nesting /auth inside the shell would trigger those providers
    // before any session exists.
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
    ShellRoute(
      builder: (context, state, child) => PageLayout(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const FeedScreen()),
      ],
    ),
    GoRoute(
      path: '/artists',
      builder: (context, state) =>
          const _InnerPageLayout(title: 'ARTISTS', child: ArtistsScreen()),
    ),
    GoRoute(
      path: '/network',
      builder: (context, state) =>
          const _InnerPageLayout(title: 'NETWORK', child: NetworkScreen()),
    ),
    GoRoute(
      path: '/dev/presets',
      builder: (context, state) => const _InnerPageLayout(
        title: 'PRESET PLAYGROUND',
        child: PresetPlaygroundScreen(),
      ),
    ),
    GoRoute(
      path: '/dev/monitor',
      builder: (context, state) =>
          const _InnerPageLayout(title: 'MONITOR', child: MonitorScreen()),
    ),
    GoRoute(
      path: '/sandbox',
      builder: (context, state) => const SandboxPreview(),
    ),
  ],
);

class XeneApp extends StatelessWidget {
  const XeneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Xene',
      debugShowCheckedModeBanner: false,
      locale: DevicePreview.locale(context),
      builder: DevicePreview.appBuilder,
      theme: ThemeData(
        useMaterial3: false,
        primaryColor: const Color(0xFFFF5500),
        scaffoldBackgroundColor: Colors.white,
        textTheme: GoogleFonts.archivoTextTheme(
          ThemeData.light().textTheme.copyWith(
            bodyLarge: const TextStyle(color: Colors.black),
            bodyMedium: const TextStyle(color: Colors.black),
          ),
        ),
      ),
      routerConfig: _router,
    );
  }
}
