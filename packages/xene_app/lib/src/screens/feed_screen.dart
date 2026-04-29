import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/feed_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/xene_feed_card.dart';
import '../widgets/magazine_hero.dart';
import '../widgets/bottom_player.dart';
import '../widgets/xene_content_modal.dart';

/// ELI5: The "Main Stage." 
/// This screen puts everything together. It has the big Billboard at the top 
/// and the list of tracks below it. We use "Slivers" so it all scrolls 
/// as one big long piece of paper.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(feedProvider.future),
      child: CustomScrollView(
        slivers: [
          // 1. The Billboard (Top)
          const SliverToBoxAdapter(
            child: MagazineHero(),
          ),

          // 2. The List (Bottom)
          feedAsync.when(
            data: (items) => SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = items[index];
                  return XeneFeedCard(
                    item: item,
                    onTap: () {
                      ref.read(playerProvider.notifier).playTrack(item);
                      showXeneContent(context, item);
                    },
                  );
                },
                childCount: items.length,
              ),
            ),
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, stack) => SliverFillRemaining(
              child: Center(child: Text('Failed to load feed: $err')),
            ),
          ),
        ],
      ),
    );
  }
}
