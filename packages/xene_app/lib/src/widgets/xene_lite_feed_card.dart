import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_domain/xene_domain.dart';

import '../providers/player_provider.dart';

/// A deliberately shallow feed card for low-end devices (see
/// [FeedRenderMode.lite]).
///
/// WHY IT EXISTS: profiling on a weak Android tablet showed the bottleneck is
/// the **build thread** (constructing the rich card's deep widget tree), not
/// raster (images composite cheaply at ~8ms). So this card keeps the artwork
/// thumbnail but collapses the rich card's nested Columns/Rows/ClipRRects/
/// gradients/badges into a single flat Row + Column — far fewer widgets to
/// build per card, which is what actually costs on slow CPUs.
class XeneLiteFeedCard extends StatelessWidget {
  const XeneLiteFeedCard({super.key, required this.item, this.onTap});

  final FeedItem item;
  final VoidCallback? onTap;

  // Logical thumbnail size; decoded at ~2x for crispness without overdraw.
  static const double _thumb = 56;

  // Cached once (see the font-caching rationale in xene_feed_card.dart).
  static final TextStyle _titleStyle = GoogleFonts.archivo(
    fontSize: 13,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );
  static final TextStyle _artistStyle = GoogleFonts.archivo(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: Colors.black54,
  );
  static final TextStyle _platformStyle = GoogleFonts.dmMono(
    fontSize: 8,
    fontWeight: FontWeight.w500,
    color: Colors.black38,
  );

  @override
  Widget build(BuildContext context) {
    final url = item.artworkUrl ?? '';
    final platform = item.platform.toLowerCase();
    final directPlay = platform == 'soundcloud' || platform == 'youtube';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: _thumb,
                height: _thumb,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    url.isEmpty
                        ? Container(
                            color: const Color(0xFFEDEDED),
                            child: const Icon(
                              Icons.music_note,
                              size: 22,
                              color: Colors.black26,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            memCacheWidth: 120,
                            placeholder: (_, __) =>
                                Container(color: const Color(0xFFEDEDED)),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFFEDEDED),
                              child: const Icon(
                                Icons.broken_image,
                                size: 20,
                                color: Colors.black26,
                              ),
                            ),
                          ),
                    if (directPlay) _LiteThumbnailPlayButton(item: item),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title ?? 'Untitled',
                    style: _titleStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.artistName,
                    style: _artistStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.platform.toUpperCase(),
                    style: _platformStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiteThumbnailPlayButton extends ConsumerWidget {
  const _LiteThumbnailPlayButton({required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(playerProvider.notifier).playTrack(item),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.26),
                  width: 0.8,
                ),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white.withValues(alpha: 0.88),
                size: 19,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
