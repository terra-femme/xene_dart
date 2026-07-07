import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Aesthetic fallback shown inside the pop-out player when a SoundCloud/YouTube
/// embed can't render (unresolved id, unsupported platform, or a load/network
/// error in the WebView/player).
///
/// Stays on-brand with the player: the track's own [artworkUrl] becomes a dimmed
/// backdrop, the platform [logoAsset] sits centered with a short [message], and
/// an in-app [onRetry] re-attempts the load. No external links — playback never
/// leaves the app.
class EmbedFallback extends StatelessWidget {
  const EmbedFallback({
    super.key,
    required this.logoAsset,
    required this.accentColor,
    this.artworkUrl,
    this.message = 'Player unavailable',
    this.onRetry,
  });

  /// Platform logo asset (e.g. assets/soundcloud_logo.png).
  final String logoAsset;

  /// Platform accent (SC orange / YT red) — used for the Retry affordance.
  final Color accentColor;

  /// Track artwork used as a dimmed backdrop; falls back to flat dark if null
  /// or it fails to load.
  final String? artworkUrl;

  final String message;

  /// In-app retry. When null, no Retry button is shown (e.g. unsupported
  /// platform, where retrying can't change the outcome).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop: dimmed artwork, or flat dark if none/failed.
          if (artworkUrl != null && artworkUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: artworkUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  const ColoredBox(color: Color(0xFF111111)),
              errorWidget: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF111111)),
            )
          else
            const ColoredBox(color: Color(0xFF111111)),

          // Scrim so the logo + text stay legible over any artwork.
          const ColoredBox(color: Color(0xCC000000)),

          // Foreground content.
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  logoAsset,
                  height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: Colors.white70,
                    letterSpacing: 0.5,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 12),
                  _RetryButton(accentColor: accentColor, onTap: onRetry!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.accentColor, required this.onTap});

  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Retry loading player',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: accentColor, width: 1.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 13, color: accentColor),
              const SizedBox(width: 6),
              Text(
                'RETRY',
                style: GoogleFonts.dmMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
