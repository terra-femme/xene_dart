import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Non-web stub. The Dancing Points visualizer is WebGL + Web Audio, so it only
/// runs in the web build. (A native port would be a degraded CPU approximation —
/// see docs/haptic_music_accessibility.md §15.11.)
class DancingPointsView extends StatelessWidget {
  const DancingPointsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          'The Dancing Points visualizer is web-only.\n'
          'Run the web build (Chrome) to use it.',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmMono(fontSize: 12, height: 1.7),
        ),
      ),
    );
  }
}
