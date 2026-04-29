import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'src/screens/feed_screen.dart';
import 'src/screens/artists_screen.dart';
import 'src/screens/network_screen.dart';
import 'src/widgets/xene_header.dart';
import 'src/widgets/bottom_player.dart';

void main() {
  runApp(
    const ProviderScope(child: XeneApp()),
  );
}

/// ELI5: The "Page Wrapper." 
/// This matches Layout.jsx. Every page gets the same Header 
/// and the same Music Player at the bottom.
class PageLayout extends StatelessWidget {
  const PageLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const XeneHeader(),
      body: child,
      bottomNavigationBar: const BottomPlayer(),
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
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFFF5500),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A), // Exact Xene Dark
        textTheme: GoogleFonts.archivoTextTheme(
          ThemeData.dark().textTheme.copyWith(
            bodyLarge: const TextStyle(color: Color(0xFFE8E8E8)),
            bodyMedium: const TextStyle(color: Color(0xFFE8E8E8)),
          ),
        ),
      ),
      routerConfig: _router,
    );
  }
}

