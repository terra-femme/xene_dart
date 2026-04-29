import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_domain/xene_domain.dart';

class XeneFeedCard extends StatelessWidget {
  const XeneFeedCard({
    super.key,
    required this.item,
    this.onTap,
  });

  final FeedItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 84, // Mandate: Small variant height
        margin: const EdgeInsets.fromLTRB(6, 0, 6, 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
        ),
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
                placeholder: (context, url) => Container(color: const Color(0xFFF5F5F5)),
                errorWidget: (context, url, error) => const Icon(Icons.music_note, size: 20),
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
                    ],
                  ),
                  const SizedBox(height: 4),
                  
                  // Title
                  Text(
                    item.title ?? 'Untitled',
                    style: GoogleFonts.archivo(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  // Snippet
                  if (item.body != null && item.body!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.body!,
                        style: GoogleFonts.archivo(
                          color: const Color(0xFF888888),
                          fontSize: 10,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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
      case 'TRACK':
      default:
        return const Color(0xFFFF5500);
    }
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
      case 'instagram':
        return const Color(0xFFE1306C);
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
