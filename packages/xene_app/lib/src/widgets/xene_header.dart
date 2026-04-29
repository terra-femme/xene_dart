import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

/// ELI5: The "Top Header."
/// Refactored to match the light theme, glass effect, and industrial typography.
class XeneHeader extends StatelessWidget {
  const XeneHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();

    Widget navButton(String label, String path) {
      final isActive = location == path;
      return GestureDetector(
        onTap: () => context.go(path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: GoogleFonts.teko(
              color: isActive ? Colors.black : const Color(0xFFA3A3A3),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.7, // 0.05em
            ),
          ),
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Navigation Links
              Row(
                children: [
                  navButton('HOME', '/'),
                  navButton('FOLLOWING', '/following'),
                  navButton('PROFILE', '/profile'),
                  navButton('SETTINGS', '/settings'),
                ],
              ),
              
              // Action Button
              Row(
                children: [
                  Text(
                    'CONNECT SOUNDCLOUD',
                    style: GoogleFonts.teko(
                      color: const Color(0xFFA3A3A3),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.share, // Mirroring Share2 icon logic
                    size: 14,
                    color: Color(0xFFA3A3A3),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
