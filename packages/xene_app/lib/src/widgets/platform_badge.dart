import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:url_launcher/url_launcher.dart';

class PlatformBadge extends StatelessWidget {
  const PlatformBadge({super.key, required this.platform, this.url});

  final String platform;
  /// If provided, tapping the badge opens this URL.
  final String? url;

  static Color colorFor(String platform) {
    switch (platform.toLowerCase()) {
      case 'soundcloud':  return const Color(0xFFFF5500);
      case 'youtube':     return const Color(0xFFFF0000);
      case 'bandcamp':    return const Color(0xFF629AA9);
      case 'beatport':    return const Color(0xFF01FF95);
      case 'spotify':     return const Color(0xFF1DB954);
      case 'instagram':   return const Color(0xFFE1306C);
      case 'twitter':
      case 'x':           return const Color(0xFF1DA1F2);
      case 'twitch':      return const Color(0xFF9146FF);
      case 'tiktok':      return const Color(0xFF010101);
      case 'patreon':     return const Color(0xFFFF424D);
      case 'gumroad':     return const Color(0xFF36A9AE);
      case 'website':
      case 'linktree':    return const Color(0xFF43E660);
      default:            return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(platform);
    final label = platform.length > 8 ? platform.substring(0, 8).toUpperCase() : platform.toUpperCase();

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );

    if (url == null) return badge;
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(url!);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: badge,
    );
  }
}

@Preview(name: 'Platform Badge - SoundCloud')
Widget previewPlatformBadgeSoundCloud() {
  return const Center(child: PlatformBadge(platform: 'SoundCloud'));
}

@Preview(name: 'Platform Badge - YouTube')
Widget previewPlatformBadgeYouTube() {
  return const Center(child: PlatformBadge(platform: 'YouTube'));
}
