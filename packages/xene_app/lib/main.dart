import 'dart:convert';
import 'dart:developer' as dev;

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

import 'package:xene_app/src/layout/xene_layout_metrics.dart';
import 'package:xene_app/src/layout/xene_responsive_debug.dart';
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
import 'package:xene_app/src/widgets/xene_header.dart';
import 'package:xene_app/src/widgets/xene_sidebar.dart';
import 'package:xene_app/src/widgets/xene_draggable_sheet.dart';
import 'package:xene_app/src/widgets/logo_pip_player.dart';
import 'package:xene_app/src/sandbox/sandbox_preview.dart';
import 'package:xene_app/src/widgets/admin_guard.dart';
import 'package:xene_app/src/widgets/loading_overlay.dart';
import 'package:xene_app/src/providers/nav_swipe_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    await Supabase.instance.client.auth.signInAnonymously();
  }

  // Await font loading so the first frame always renders in the correct fonts.
  if (kIsWeb) {
    await GoogleFonts.pendingFonts([GoogleFonts.archivo(), GoogleFonts.teko()]);
  }

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
      enabled: !kReleaseMode,
      builder: (context) => const ProviderScope(child: XeneApp()),
    ),
  );
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
  });

  final String title;
  final Widget child;
  final bool showFullNav;

  @override
  Widget build(BuildContext context) {
    if (showFullNav) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const XeneHeader(),
            const Divider(color: Color(0xFFE0E0E0), height: 1),
            Expanded(child: _SwipeNavWrapper(child: child)),
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
                      const SizedBox(width: 72),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFE0E0E0), height: 1),
          Expanded(child: _SwipeNavWrapper(child: child)),
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
                            child: _SwipeNavWrapper(
                              child: Container(
                                color: Colors.white,
                                child: child,
                              ),
                            ),
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

// ---------------------------------------------------------------------------
// Swipe-based page turn
// ---------------------------------------------------------------------------

/// Builds a [CustomTransitionPage] with a horizontal slide whose direction
/// is captured from [navGoingForward] at the moment the page is built.
/// When [skipNextTransition] is true (swipe-commit path), the transition
/// duration is zero — the slide-out animation already handled the visual.
CustomTransitionPage<void> _slidePage({
  required LocalKey key,
  required Widget child,
}) {
  final forward = navGoingForward;
  final skip = skipNextTransition;
  skipNextTransition = false;

  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: skip
        ? Duration.zero
        : const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: skip
        ? (_, __, ___, child) => child
        : (context, animation, secondaryAnimation, child) {
            final begin = forward
                ? const Offset(1.0, 0.0)
                : const Offset(-1.0, 0.0);
            return SlideTransition(
              position: animation.drive(
                Tween(
                  begin: begin,
                  end: Offset.zero,
                ).chain(CurveTween(curve: Curves.easeOutCubic)),
              ),
              child: child,
            );
          },
  );
}

/// Detects horizontal swipe gestures on the content area and navigates between
/// pages in [kSwipeNavRoutes] order. Works as a hidden easter egg — magazine-
/// style page turn without any visible hint until discovered.
class _SwipeNavWrapper extends ConsumerStatefulWidget {
  const _SwipeNavWrapper({required this.child});
  final Widget child;

  @override
  ConsumerState<_SwipeNavWrapper> createState() => _SwipeNavWrapperState();
}

class _SwipeNavWrapperState extends ConsumerState<_SwipeNavWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _offset = 0;
  double _animStart = 0;
  double _animEnd = 0;
  bool _dragging = false;

  // Raw (un-damped) horizontal distance since drag started. Used as a
  // distance-based commit fallback for web/desktop where mouse drags
  // produce much lower velocity than mobile finger flicks.
  double _rawDrag = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
    );
    _ctrl.addListener(() {
      setState(() {
        _offset = _animStart + (_animEnd - _animStart) * _ctrl.value;
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _snapBack() {
    _ctrl.stop();
    _animStart = _offset;
    _animEnd = 0;
    _ctrl.duration = const Duration(milliseconds: 210);
    _ctrl.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _offset = 0);
    });
  }

  void _commitNavigate(bool goBack, int targetIdx) {
    final sw = MediaQuery.of(context).size.width;
    _ctrl.stop();
    _animStart = _offset;
    _animEnd = goBack ? sw : -sw;
    _ctrl.duration = const Duration(milliseconds: 130);
    _ctrl.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      navGoingForward = !goBack;
      skipNextTransition = true;
      ref.read(navIndexProvider.notifier).state = targetIdx;
      context.go(kSwipeNavRoutes[targetIdx]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _ctrl.stop();
        _dragging = true;
        _rawDrag = 0;
      },
      onHorizontalDragUpdate: (details) {
        if (!_dragging) return;
        _rawDrag += details.delta.dx;
        setState(() => _offset += details.delta.dx * 0.35);
      },
      onHorizontalDragEnd: (details) {
        if (!_dragging) return;
        _dragging = false;

        final v = details.primaryVelocity ?? 0;
        final sw = MediaQuery.of(context).size.width;

        // Commit if: fast flick (mobile) OR dragged far enough (web/desktop mouse).
        final commitByVelocity = v.abs() >= 300;
        final commitByDistance = _rawDrag.abs() / sw >= 0.28;

        if (!commitByVelocity && !commitByDistance) {
          _snapBack();
          return;
        }

        // Prefer velocity sign for direction; fall back to raw drag direction
        // when velocity is near zero (slow deliberate web drag).
        final goBack = v.abs() >= 50 ? v > 0 : _rawDrag > 0;

        final currentIdx = ref.read(navIndexProvider);
        final targetIdx = goBack ? currentIdx - 1 : currentIdx + 1;
        if (targetIdx < 0 || targetIdx >= kSwipeNavRoutes.length) {
          _snapBack();
          return;
        }
        _commitNavigate(goBack, targetIdx);
      },
      child: Transform.translate(
        offset: Offset(_offset, 0),
        child: widget.child,
      ),
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
      pageBuilder: (context, state, child) => _slidePage(
        key: state.pageKey,
        child: PageLayout(child: child),
      ),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const FeedScreen()),
      ],
    ),
    GoRoute(
      path: '/articles',
      pageBuilder: (context, state) => _slidePage(
        key: state.pageKey,
        child: const _InnerPageLayout(
          title: 'ARTICLES',
          showFullNav: true,
          child: ArticlesScreen(),
        ),
      ),
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
      path: '/following',
      pageBuilder: (context, state) => _slidePage(
        key: state.pageKey,
        child: const _InnerPageLayout(
          title: 'FOLLOWING',
          showFullNav: true,
          child: FollowingScreen(),
        ),
      ),
    ),
    GoRoute(
      path: '/game',
      pageBuilder: (context, state) => _slidePage(
        key: state.pageKey,
        child: const _InnerPageLayout(
          title: 'GAME',
          showFullNav: true,
          child: GameScreen(),
        ),
      ),
    ),
    GoRoute(
      path: '/channels',
      pageBuilder: (context, state) => _slidePage(
        key: state.pageKey,
        child: const _InnerPageLayout(
          title: 'CHANNELS',
          showFullNav: true,
          child: ChannelsScreen(),
        ),
      ),
    ),
    GoRoute(
      path: '/game/party/:partyId',
      builder: (context, state) => _InnerPageLayout(
        title: 'PARTY',
        child: PartyScreen(partyId: state.pathParameters['partyId']!),
      ),
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) => _slidePage(
        key: state.pageKey,
        child: const _InnerPageLayout(
          title: 'PROFILE',
          showFullNav: true,
          child: ProfileScreen(),
        ),
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
      path: '/about',
      pageBuilder: (context, state) => _slidePage(
        key: state.pageKey,
        child: const _InnerPageLayout(
          title: 'ABOUT',
          showFullNav: true,
          child: AboutScreen(),
        ),
      ),
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
