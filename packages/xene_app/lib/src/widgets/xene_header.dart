import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

/// ELI5: The "Top Header." 
/// This is the direct mirror of Header.jsx. It's a row of buttons 
/// at the top that lets you move between pages.
class XeneHeader extends StatelessWidget implements PreferredSizeWidget {
  const XeneHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();

    Widget navButton(String label, String path) {
      final isActive = location == path;
      return TextButton(
        onPressed: () => context.go(path),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(
          label,
          style: GoogleFonts.teko(
            color: isActive ? Colors.white : const Color(0xFFA3A3A3), // matching text-neutral-400
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.7, // 0.05em
          ),
        ),
      );
    }

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.95),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            navButton('HOME', '/'),
            navButton('ARTISTS', '/artists'),
            navButton('NETWORK', '/network'),
            // "CONNECT" button (mirroring the Share2 icon logic)
            IconButton(
              icon: const Icon(Icons.share, size: 16, color: Colors.white24),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}
