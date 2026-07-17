import 'dart:async';

import 'package:flutter/material.dart';

// Non-web stub — SC Widget API is web-only; stream never emits.
Stream<int> get scPlayPositionStream => Stream<int>.empty();

class SoundCloudEmbed extends StatelessWidget {
  const SoundCloudEmbed({
    super.key,
    required this.trackId,
    this.isVisual = false,
    this.artworkUrl,
    this.title,
    this.artistName,
    this.durationSeconds,
  });

  final String trackId;
  final bool isVisual;

  // Accepted for facade-signature parity with the native embed.
  final String? artworkUrl;
  final String? title;
  final String? artistName;
  final int? durationSeconds;

  @override
  Widget build(BuildContext context) {
    return const _NativeEmbedPlaceholder(label: 'SOUNDCLOUD');
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
