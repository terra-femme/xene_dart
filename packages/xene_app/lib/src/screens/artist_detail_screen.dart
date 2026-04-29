import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';
import '../providers/feed_provider.dart';
import '../widgets/xene_feed_card.dart';
import '../widgets/platform_badge.dart';

/// ELI5: The "Artist Profile." 
/// It shows a big picture of the artist, their links, 
/// and a list of just their songs.
class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({super.key, required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We can filter the existing feedProvider or create a new one.
    // For the scaffold, we'll just show how the UI looks.
    final feedAsync = ref.watch(feedProvider);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 250,
              pinned: true,
              backgroundColor: Colors.black,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  artist.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background Image (Using placeholder or artist image)
                    Container(color: const Color(0xFF1A1A1A)),
                    // Gradient overlay to make text readable
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Platform Links
                    const Text(
                      'CONNECT',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (artist.soundcloudUsername != null)
                          const PlatformBadge(platform: 'soundcloud'),
                        if (artist.youtubeUrl != null)
                          const PlatformBadge(platform: 'youtube'),
                        if (artist.beatportArtistId != null)
                          const PlatformBadge(platform: 'beatport'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'RECENT RELEASES',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ];
        },
        body: feedAsync.when(
          data: (items) {
            // Filter items for this specific artist
            final artistItems = items.where((i) => i.artistName == artist.name).toList();
            return ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: artistItems.length,
              itemBuilder: (context, index) => XeneFeedCard(item: artistItems[index]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
        ),
      ),
    );
  }
}
