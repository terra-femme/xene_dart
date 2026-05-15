import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_domain/xene_domain.dart';

class XeneFeedCard extends StatelessWidget {
  const XeneFeedCard({
    super.key,
    required this.item,
    this.onTap,
    this.dark = false,
  });

  final FeedItem item;
  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final cardColor = dark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white;
    final borderColor = dark
        ? Colors.white.withValues(alpha: 0.15)
        : const Color(0xFFE0E0E0);
    final placeholderColor = dark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFF5F5F5);
    final titleColor = dark ? Colors.white : Colors.black;
    final snippetColor = dark ? Colors.white54 : const Color(0xFF888888);
    final errorIconColor = dark ? Colors.white54 : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 90),
        margin: const EdgeInsets.fromLTRB(6, 0, 6, 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1),
        ),
        foregroundDecoration: item.isNew
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: const Border(
                  left: BorderSide(color: Color(0xFF00C5A5), width: 2.5),
                ),
                color: const Color(0x1100C5A5),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Thumbnail (Left)
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: CachedNetworkImage(
                imageUrl: item.artworkUrl ?? '',
                width: 39,
                height: 39,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: placeholderColor),
                errorWidget: (context, url, error) =>
                    Icon(Icons.music_note, size: 20, color: errorIconColor),
              ),
            ),

            const SizedBox(width: 7),

            // 2. Content Frame (Right)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Pills & Badges
                  Row(
                    children: [
                      _TypePill(type: item.contentType),
                      const SizedBox(width: 4),
                      _PlatformBadge(platform: item.platform),
                      if (item.publishedAt.isAfter(DateTime.now())) ...[
                        const SizedBox(width: 4),
                        const _PreOrderStar(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Title
                  Text(
                    item.title ?? 'Untitled',
                    style: GoogleFonts.archivo(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    softWrap: true,
                  ),

                  // Artist name
                  Text(
                    item.artistName,
                    style: GoogleFonts.archivo(
                      color: snippetColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Snippet
                  if (item.body != null && item.body!.isNotEmpty)
                    Text(
                      item.body!,
                      style: GoogleFonts.archivo(
                        color: snippetColor,
                        fontSize: 10,
                      ),
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

class _TypePill extends StatelessWidget {
  const _TypePill({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final color = _getPillColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          fontFamily: 'DM Mono',
        ),
      ),
    );
  }

  Color _getPillColor(String type) {
    switch (type.toUpperCase()) {
      case 'MIX':
        return const Color(0xFFC9A96E);
      case 'RELEASE':
        return const Color(0xFF4E9A06);
      case 'EP':
        return const Color(0xFFAB47BC);
      case 'ALBUM':
        return const Color(0xFF42A5F5);
      case 'TRACK':
      default:
        return const Color(0xFFFF5500);
    }
  }
}

class _PreOrderStar extends StatelessWidget {
  const _PreOrderStar();

  @override
  Widget build(BuildContext context) {
    return const Tooltip(
      message: 'Pre-order',
      child: Icon(Icons.star, size: 11, color: Color(0xFFFFB800)),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.platform});
  final String platform;

  @override
  Widget build(BuildContext context) {
    final color = _getPlatformColor(platform);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      height: 18,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Text(
          platform.toUpperCase(),
          style: GoogleFonts.dmMono(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'soundcloud':
        return const Color(0xFFFF5500);
      case 'bandcamp':
        return const Color(0xFF4E9A06);
      case 'twitch':
        return const Color(0xFF9146FF);
      case 'youtube':
        return const Color(0xFFFF4444);
      default:
        return Colors.grey;
    }
  }
}

@Preview(name: 'Feed Card - Track')
Widget previewXeneFeedCard() {
  return Material(
    child: XeneFeedCard(
      item: FeedItem(
        id: 'preview',
        platform: 'SoundCloud',
        artistName: 'Gemini Artist',
        contentType: 'track',
        title: 'Previewing the Widget',
        body: 'This is a snippet of the content that appears on the card.',
        publishedAt: DateTime.now(),
        externalUrl: 'https://soundcloud.com',
        artworkUrl:
            'https://i1.sndcdn.com/artworks-000570766259-3j1z9w-t500x500.jpg',
      ),
    ),
  );
}
