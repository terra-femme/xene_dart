import 'package:flutter/material.dart';

class YouTubeEmbed extends StatelessWidget {
  const YouTubeEmbed({
    super.key,
    required this.videoId,
    required this.externalUrl,
    this.artworkUrl,
  });

  final String videoId;
  final String externalUrl;

  // Accepted for facade-signature parity with the native embed.
  final String? artworkUrl;

  @override
  Widget build(BuildContext context) {
    return const _NativeEmbedPlaceholder(label: 'YOUTUBE');
  }
}

class _NativeEmbedPlaceholder extends StatelessWidget {
  const _NativeEmbedPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
