import 'package:flutter/material.dart';

class SoundCloudEmbed extends StatelessWidget {
  const SoundCloudEmbed({
    super.key,
    required this.trackId,
    this.isVisual = false,
  });

  final String trackId;
  final bool isVisual;

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
