import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'src/screens/feed_screen.dart';
import 'src/screens/artists_screen.dart';
import 'src/screens/network_screen.dart';
import 'src/widgets/xene_header.dart';
import 'src/widgets/xene_sidebar.dart';
import 'src/widgets/bottom_player.dart';

void main() {
  runApp(
    const ProviderScope(child: XeneApp()),
  );
}

/// ELI5: The "Page Wrapper."
/// Updated to match the 30/70 split layout with a fixed header.
class PageLayout extends StatelessWidget {
  const PageLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. Main Content Area (Sidebar + Feed)
          Column(
            children: [
              const SizedBox(height: 56), // Header offset
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const XeneSidebar(),
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                        ),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // 2. Fixed Top Navigation (Absolute Position)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: XeneHeader(),
          ),

          // 3. Bottom Player (Optional/Overlay)
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: BottomPlayer(),
          ),
        ],
      ),
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => PageLayout(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const FeedScreen(),
        ),
        GoRoute(
          path: '/artists',
          builder: (context, state) => const ArtistsScreen(),
        ),
        GoRoute(
          path: '/network',
          builder: (context, state) => const NetworkScreen(),
        ),
      ],
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
      theme: ThemeData(
        useMaterial3: false, // Mandate: Disable Material3 for exact control
        brightness: Brightness.light,
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

