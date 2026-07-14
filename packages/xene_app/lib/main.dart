import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:xene_app/src/platform/auth_url_cleanup_stub.dart'
    if (dart.library.html) 'package:xene_app/src/platform/auth_url_cleanup_web.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:device_preview_plus/device_preview_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:xene_app/src/screens/auth_screen.dart';

import 'package:xene_app/src/screens/feed_screen.dart';
import 'package:xene_app/src/screens/articles_screen.dart';
import 'package:xene_app/src/screens/artists_screen.dart';
import 'package:xene_app/src/screens/network_screen.dart';
import 'package:xene_app/src/screens/preset_playground_screen.dart';
import 'package:xene_app/src/screens/monitor_screen.dart';
import 'package:xene_app/src/screens/following_screen.dart';
import 'package:xene_app/src/screens/profile_screen.dart';
import 'package:xene_app/src/screens/about_screen.dart';
import 'package:xene_app/src/screens/channels_screen.dart';
import 'package:xene_app/src/screens/game_screen.dart';
import 'package:xene_app/src/screens/party_screen.dart';
import 'package:xene_app/src/screens/settings_screen.dart';
import 'package:xene_app/src/widgets/xene_header.dart';
import 'package:xene_app/src/layout/root_shell.dart';
import 'package:xene_app/src/sandbox/sandbox_preview.dart';
import 'package:xene_app/src/sandbox/av_sphere_sandbox.dart';
import 'package:xene_app/src/sandbox/av_stream_test.dart';
import 'package:xene_app/src/sandbox/dancing_points_view.dart';
import 'package:xene_app/src/widgets/admin_guard.dart';
import 'package:xene_app/src/widgets/perf_hud.dart';
import 'package:xene_app/src/providers/ui_config_provider.dart';
import 'package:xene_app/src/theme/xene_theme.dart';
import 'package:xene_app/src/providers/accessibility_provider.dart';

// Compile-time flag that bypasses AdminGuard in debug builds.
// NEVER pass --dart-define=XENE_FORCE_DEV_MENU=true to distribution builds.
const _forceDevMenu = bool.fromEnvironment('XENE_FORCE_DEV_MENU');

// Compile-time flag for the device_preview_plus simulated-device frame.
// Defaults OFF so normal builds (including debug on a real phone) run the app
// full-screen — the preview frame otherwise reparents the whole app and can
// swallow modal bottom sheets (e.g. the sign-in sheet). Re-enable on demand to
// preview how the UI generalizes across devices:
//   flutter run --dart-define=XENE_DEVICE_PREVIEW=true
// The DevicePreview.appBuilder / DevicePreview.locale calls below are null-safe
// when disabled, so no other wiring changes are needed to turn it back on.
const _devicePreview = bool.fromEnvironment('XENE_DEVICE_PREVIEW');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _forwardFlutterErrorsToConsole();

  // Warn loudly when a debug build ships with the admin bypass active.
  // This won't fire in release/profile builds (kDebugMode is false), but it
  // makes the flag visible in every debug session so it's never quietly enabled.
  if (kDebugMode && _forceDevMenu) {
    dev.log(
      '⚠️  XENE_FORCE_DEV_MENU=true — AdminGuard is BYPASSED. '
      'DO NOT distribute this build.',
      name: 'xene.security',
    );
  }

  // Switch to path-based URLs so the #access_token=... fragment from Supabase
  // magic links is treated as a true URL fragment, not a route path. Without
  // this, go_router (which defaults to hash routing) interprets the fragment
  // as the active route and crashes on an assertion in its matching logic.
  usePathUrlStrategy();

  // Implicit flow: magic links use #access_token=... in the URL fragment.
  // This avoids the PKCE code_verifier problem where the verifier is stored
  // in localStorage of the tab that requested the OTP, but the magic link
  // may open in a different browser or tab where that localStorage is absent.
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );

  // 1. Handle auth callbacks before anything else, so a real session is
  //    established before we decide whether to fall back to anonymous.
  if (kIsWeb) {
    // supabase_flutter's detectSessionInUri handles #access_token=... inside
    // initialize() above. This explicit call is a fallback for edge cases.
    final uri = Uri.base;
    final hasToken = uri.fragment.contains('access_token');
    if (hasToken) {
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
      } catch (e) {
        dev.log(
          '[auth] getSessionFromUrl fallback failed: $e',
          name: 'xene.auth',
        );
      }
      clearAuthCallbackFragment();
    }
  } else {
    // Mobile: handle the URI the app was launched with (cold start via magic link).
    final appLinks = AppLinks();
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null) {
      dev.log('[auth] cold-start deep-link: $initialUri', name: 'xene.auth');
      await Supabase.instance.client.auth.getSessionFromUrl(initialUri);
    }
    // Warm start: app already running when the link is tapped.
    appLinks.uriLinkStream.listen((uri) {
      dev.log('[auth] deep-link received: $uri', name: 'xene.auth');
      Supabase.instance.client.auth.getSessionFromUrl(uri);
    });
  }

  // 2. Only fall back to anonymous if no real session was established above
  //    or restored from device storage by initialize().
  if (Supabase.instance.client.auth.currentUser == null) {
    try {
      // Bounded so a slow/throttled anon sign-in can't block startup (it was
      // freezing the app for minutes before runApp). The underlying call keeps
      // running after a timeout; onAuthStateChange picks up the session if it
      // lands late, and authenticated calls retry once a session exists.
      await Supabase.instance.client.auth.signInAnonymously().timeout(
        const Duration(seconds: 8),
      );
      dev.log('[auth] anonymous session created', name: 'xene.auth');
    } catch (e) {
      // Includes TimeoutException. Without a session, authenticated calls (feed,
      // etc.) 401 until one lands — but the app shows immediately instead of
      // hanging. Surface the reason instead of failing silently.
      dev.log(
        '[auth] signInAnonymously failed/timed out: $e',
        name: 'xene.auth',
        error: e,
      );
    }
  }

  // Await font loading on all platforms so the first frame always renders in
  // the correct fonts. The LoadingOverlay (min 2500ms) covers this window —
  // by the time it fades out, all fonts are cached and no flash is possible.
  await GoogleFonts.pendingFonts([
    GoogleFonts.archivo(),
    GoogleFonts.teko(),
    GoogleFonts.dmMono(),
  ]);

  // Cross-tab session sync: when another browser window processes a magic link
  // it writes the real session to localStorage. The storage event fires in all
  // other windows; recoverSession() picks it up so Riverpod rebuilds.
  setupCrossTabSync();

  // Fallback: when the user switches back to this window after clicking a magic
  // link in another window, AppLifecycleState.resumed fires. If the storage
  // event didn't propagate (cross-process browsers), this catches it.
  if (kIsWeb) {
    WidgetsBinding.instance.addObserver(_SessionRecoveryObserver());
  }

  // Refresh router whenever auth state changes (login, logout, token refresh).
  Supabase.instance.client.auth.onAuthStateChange.listen((event) {
    final u = event.session?.user;
    dev.log(
      '[auth] event=${event.event.name} '
      'userId=${u?.id} '
      'isAnon=${u?.isAnonymous} '
      'email=${u?.email}',
      name: 'xene.auth',
    );

    // When this window processes a magic link it broadcasts the session JSON
    // to all other same-origin windows so they update without a reload.
    if (kIsWeb &&
        event.event == AuthChangeEvent.signedIn &&
        u != null &&
        !u.isAnonymous) {
      final session = event.session;
      if (session != null) {
        broadcastSession(jsonEncode(session.toJson()));
      }
    }

    _router.refresh();
  });

  runApp(
    DevicePreview(
      enabled: _devicePreview,
      builder: (context) => const ProviderScope(child: XeneApp()),
    ),
  );
}

void _forwardFlutterErrorsToConsole() {
  final defaultFlutterErrorHandler = FlutterError.onError;

  FlutterError.onError = (FlutterErrorDetails details) {
    defaultFlutterErrorHandler?.call(details);
    final errorDump = details.toString();
    debugPrint(errorDump);
    dev.log(
      errorDump,
      name: 'xene.flutter_error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    final errorDump = 'Uncaught platform error: $error\n$stack';
    debugPrint(errorDump);
    dev.log(
      errorDump,
      name: 'xene.platform_error',
      error: error,
      stackTrace: stack,
    );
    return false;
  };
}

class _SessionRecoveryObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      recoverSessionIfNeeded();
    }
  }
}

/// Layout for sub-pages.
///
/// [showFullNav] = true  → swipeable pages: shows the full [XeneHeader] so the
///   user can tap any nav button to break out of the swipe flow at any time.
/// [showFullNav] = false → non-swipeable sub-pages (artists, dev tools, parties):
///   shows the slim back-nav bar with a page title.
class _InnerPageLayout extends StatelessWidget {
  const _InnerPageLayout({
    required this.title,
    required this.child,
    this.showFullNav = false,
    this.trailing,
  });

  final String title;
  final Widget child;
  final bool showFullNav;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (showFullNav) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const XeneHeader(),
            const Divider(color: XeneTheme.border, height: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    // Slim back-nav layout for non-swipeable sub-pages.
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
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/');
                          }
                        },
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
                      SizedBox(
                        width: 72,
                        child: trailing != null
                            ? Align(
                                alignment: Alignment.centerRight,
                                child: trailing,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: XeneTheme.border, height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

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
    // /auth is a top-level route — intentionally outside the shell. RootShell
    // contains XeneSidebar/XeneHeader which watch authenticated providers;
    // nesting /auth would trigger them before any session exists.
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),

    // Persistent shell for the 7 primary swipe routes. RootShell stays mounted
    // across branch switches, so navigating between these pages never tears
    // down + reactivates the chrome — structurally eliminating the
    // _RenderLayoutBuilder crash. Branch order MUST match kSwipeNavRoutes so
    // header taps / swipe (which use that index) line up with goBranch().
    StatefulShellRoute(
      builder: (context, state, navigationShell) =>
          RootShell(navigationShell: navigationShell),
      navigatorContainerBuilder: (context, navigationShell, children) =>
          AnimatedBranchContainer(
            currentIndex: navigationShell.currentIndex,
            children: children,
          ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const FeedScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/articles',
              builder: (context, state) => const ArticlesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/following',
              builder: (context, state) => const FollowingScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/game',
              builder: (context, state) => const GameScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/channels',
              builder: (context, state) => const ChannelsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/about',
              builder: (context, state) => const AboutScreen(),
            ),
          ],
        ),
      ],
    ),

    // Secondary routes — pushed OVER the persistent shell, each carrying its
    // own chrome (_InnerPageLayout). Intentionally NOT branches: they keep the
    // shell mounted underneath (no teardown) while bringing their own back-nav.
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
      path: '/game/party/:partyId',
      builder: (context, state) => _InnerPageLayout(
        title: 'PARTY',
        trailing: const PartyMenuBtn(),
        child: PartyScreen(partyId: state.pathParameters['partyId']!),
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const _InnerPageLayout(
        title: 'SETTINGS',
        showFullNav: true,
        child: SettingsScreen(),
      ),
    ),
    GoRoute(
      path: '/dev/presets',
      builder: (context, state) => const AdminGuard(
        child: _InnerPageLayout(
          title: 'PRESET PLAYGROUND',
          child: PresetPlaygroundScreen(),
        ),
      ),
    ),
    GoRoute(
      path: '/dev/monitor',
      builder: (context, state) => const AdminGuard(
        child: _InnerPageLayout(title: 'MONITOR', child: MonitorScreen()),
      ),
    ),
    GoRoute(
      path: '/dev/av',
      builder: (context, state) => const AdminGuard(
        child: _InnerPageLayout(title: 'AV SANDBOX', child: AvSphereSandbox()),
      ),
    ),
    GoRoute(
      path: '/dev/av-stream-test',
      builder: (context, state) => const AdminGuard(
        child: _InnerPageLayout(title: 'AV STREAM TEST', child: AvStreamTest()),
      ),
    ),
    GoRoute(
      path: '/dev/av-visualizer',
      builder: (context, state) => const AdminGuard(
        child: _InnerPageLayout(
          title: 'AV VISUALIZER',
          child: DancingPointsView(),
        ),
      ),
    ),
    GoRoute(
      path: '/sandbox',
      builder: (context, state) => const SandboxPreview(),
    ),
  ],
);

/// Enables smooth scrolling on all platforms including web.
/// - Adds mouse + trackpad to dragDevices so web users can drag-scroll
///   (Flutter web blocks mouse drag by default).
/// - Uses BouncingScrollPhysics for momentum deceleration instead of the
///   hard-stop ClampingScrollPhysics default.
class XeneScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

const _showSemantics = bool.fromEnvironment('XENE_SHOW_SEMANTICS');

// On-screen frame-timing overlay for diagnosing jank on touch devices that
// can't open DevTools. Off by default; enable with
// --dart-define=XENE_PERF_HUD=true. See widgets/perf_hud.dart.
const _showPerfHud = bool.fromEnvironment('XENE_PERF_HUD');

class XeneApp extends ConsumerWidget {
  const XeneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(uiConfigProvider).valueOrNull;
    final primaryColor = config?.primaryColor ?? XeneTheme.orange;
    final a11y = ref.watch(accessibilityProvider);

    return MaterialApp.router(
      title: 'Xene',
      debugShowCheckedModeBanner: false,
      locale: DevicePreview.locale(context),
      builder: (context, child) {
        Widget content = MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(a11y.textScaleOverride)),
          child: child ?? const SizedBox.shrink(),
        );
        if (_showSemantics) content = SemanticsDebugger(child: content);
        if (_showPerfHud) {
          content = Stack(children: [content, const PerfHud()]);
        }
        return DevicePreview.appBuilder(context, content);
      },
      scrollBehavior: XeneScrollBehavior(),
      theme: a11y.highContrast
          ? ThemeData(
              useMaterial3: false,
              primaryColor: Colors.black,
              scaffoldBackgroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.black),
              dividerColor: Colors.black,
              textTheme: GoogleFonts.archivoTextTheme(
                ThemeData.light().textTheme.copyWith(
                  bodyLarge: const TextStyle(color: Colors.black),
                  bodyMedium: const TextStyle(color: Colors.black),
                ),
              ),
            )
          : ThemeData(
              useMaterial3: false,
              primaryColor: primaryColor,
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
