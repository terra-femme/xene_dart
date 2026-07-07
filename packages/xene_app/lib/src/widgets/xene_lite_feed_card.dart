import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_domain/xene_domain.dart';

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
              child: url.isEmpty
                  ? Container(
                      width: _thumb,
                      height: _thumb,
                      color: const Color(0xFFEDEDED),
                      child: const Icon(
                        Icons.music_note,
                        size: 22,
                        color: Colors.black26,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
                      width: _thumb,
                      height: _thumb,
                      fit: BoxFit.cover,
                      memCacheWidth: 120,
                      placeholder: (_, __) => Container(
                        width: _thumb,
                        height: _thumb,
                        color: const Color(0xFFEDEDED),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: _thumb,
                        height: _thumb,
                        color: const Color(0xFFEDEDED),
                        child: const Icon(
                          Icons.broken_image,
                          size: 20,
                          color: Colors.black26,
                        ),
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
