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
              backgroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  artist.name,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background Image (Using placeholder or artist image)
                    Container(color: const Color(0xFFF5F5F5)),
                    // Gradient overlay to make text readable
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.white],
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
                        color: Colors.black54,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (artist.soundcloudUrl != null)
                          PlatformBadge(platform: 'soundcloud', url: artist.soundcloudUrl),
                        if (artist.youtubeUrl != null)
                          PlatformBadge(platform: 'youtube', url: artist.youtubeUrl),
                        if (artist.spotifyUrl != null)
                          PlatformBadge(platform: 'spotify', url: artist.spotifyUrl),
                        if (artist.bandcampUrl != null)
                          PlatformBadge(platform: 'bandcamp', url: artist.bandcampUrl),
                        if (artist.beatportUrl != null)
                          PlatformBadge(platform: 'beatport', url: artist.beatportUrl),
                        if (artist.instagramUrl != null)
                          PlatformBadge(platform: 'instagram', url: artist.instagramUrl),
                        if (artist.twitterUrl != null)
                          PlatformBadge(platform: 'twitter', url: artist.twitterUrl),
                        if (artist.twitchUrl != null)
                          PlatformBadge(platform: 'twitch', url: artist.twitchUrl),
                        if (artist.websiteUrl != null)
                          PlatformBadge(platform: 'website', url: artist.websiteUrl),
                        // Extra links stored in edges (tiktok, patreon, gumroad, etc.)
                        for (final edge in artist.edges.where(
                          (e) => e['type'] == 'SC_WEB_PROFILE',
                        ))
                          PlatformBadge(
                            platform: edge['targetName'] as String? ?? 'link',
                            url: edge['sourceUrl'] as String?,
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'RECENT RELEASES',
                      style: TextStyle(
                        color: Colors.black,
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
