import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../providers/sheet_provider.dart';
import 'soundcloud_embed.dart';
import 'youtube_embed.dart';

class FloatingPlayerAnchor extends ConsumerWidget {
  const FloatingPlayerAnchor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final sheetController = ref.watch(sheetProvider);
    final screenHeight = MediaQuery.of(context).size.height;

    if (!playerState.isVisible || playerState.currentTrack == null) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: sheetController,
      builder: (context, _) {
        double currentSize = 0.0;
        if (sheetController.isAttached) {
          currentSize = sheetController.size;
        }

        // Positioned at the bottom, offset by the current height of the sheet + 5px gap
        final bottomOffset = (currentSize * screenHeight) + 5;

        return Positioned(
          left: 0,
          right: 0,
          bottom: bottomOffset,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Floating Player Container
                Container(
                  height: 40, // Increased height for spacing/hitbox
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1. The actual player (centered)
                      if (playerState.activePlatform ==
                          ActivePlatform.soundcloud)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: SoundCloudEmbed(
                            trackId: playerState.currentTrack!.id,
                          ),
                        ),

                      if (playerState.activePlatform == ActivePlatform.youtube)
                        YouTubeEmbed(
                          videoId: playerState.currentTrack!.id,
                          externalUrl: playerState.currentTrack!.externalUrl,
                        ),

                      // 2. Close button (top-right)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () =>
                              ref.read(playerProvider.notifier).stopAndHide(),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black26,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white70,
                              size: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
