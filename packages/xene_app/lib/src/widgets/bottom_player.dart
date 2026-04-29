import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';

/// ELI5: The "Music Remote Control." 
/// This bar stays at the bottom of the screen so you can always 
/// pause or skip, no matter what page you are on.
class BottomPlayer extends ConsumerWidget {
  const BottomPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final currentTrack = playerState.currentTrack;

    if (currentTrack == null) return const SizedBox.shrink();

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // 1. Artwork Thumbnail
          if (currentTrack.artworkUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: currentTrack.artworkUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
          
          const SizedBox(width: 12),

          // 2. Track Info
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentTrack.title ?? 'Untitled',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  currentTrack.artistName,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // 3. Play/Pause Button
          IconButton(
            icon: Icon(
              playerState.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              size: 40,
              color: const Color(0xFFFF5500),
            ),
            onPressed: () => ref.read(playerProvider.notifier).togglePlayPause(),
          ),
        ],
      ),
    );
  }
}
