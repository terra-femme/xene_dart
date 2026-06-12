import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_domain/xene_domain.dart';

import '../providers/auth_provider.dart';
import '../providers/queue_provider.dart';
import '../theme/xene_theme.dart';
import 'auth_gate_sheet.dart';

class XeneFeedCard extends StatelessWidget {
  const XeneFeedCard({
    super.key,
    required this.item,
    this.onTap,
    this.dark = false,
    this.videoMode = false,
  });

  final FeedItem item;
  final VoidCallback? onTap;
  final bool dark;
  final bool videoMode;

  @override
  Widget build(BuildContext context) {
    if (videoMode && item.platform.toLowerCase() == 'youtube') {
      return _YoutubeVideoCard(item: item, onTap: onTap, dark: dark);
    }

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
    final snippetColor = dark ? Colors.white54 : Colors.black87;
    final errorIconColor = dark ? Colors.white54 : null;
    final repostAttribution = _repostAttribution(item);
    final bodyText = _bodyWithoutAttribution(item.body, repostAttribution);

    final hasArtwork = item.artworkUrl != null && item.artworkUrl!.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 180;
        final thumbnailSize = compact ? 32.0 : 39.0;
        final cardPadding = compact ? 6.0 : 8.0;
        final contentGap = compact ? 6.0 : 7.0;
        final badgeMaxWidth = compact ? 70.0 : 112.0;
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final thumbnailCacheSize = (thumbnailSize * devicePixelRatio)
            .ceil()
            .clamp(48, 128);
        final backgroundCacheWidth = (constraints.maxWidth * devicePixelRatio)
            .ceil()
            .clamp(160, 640);
        final backgroundCacheHeight =
            ((compact ? 84.0 : 90.0) * devicePixelRatio).ceil().clamp(96, 256);
        final artworkProvider = hasArtwork
            ? _resizedArtworkProvider(
                item.artworkUrl!,
                width: backgroundCacheWidth,
                height: backgroundCacheHeight,
              )
            : null;
        final thumbnailProvider = hasArtwork
            ? _resizedArtworkProvider(
                item.artworkUrl!,
                width: thumbnailCacheSize,
                height: thumbnailCacheSize,
              )
            : null;
        final bgImage = artworkProvider == null
            ? null
            : DecorationImage(
                image: artworkProvider,
                fit: BoxFit.cover,
                opacity: 1.0,
                colorFilter: dark
                    ? ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.50),
                        BlendMode.multiply,
                      )
                    : null,
              );

        final platform = item.platform.toLowerCase();
        final contentDesc =
            '${item.title ?? 'Untitled'} by ${item.artistName}, '
            '${item.contentType} on $platform';

        return RepaintBoundary(
          child: Semantics(
            label: contentDesc,
            button: true,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                constraints: BoxConstraints(minHeight: compact ? 84.0 : 90.0),
                margin: const EdgeInsets.fromLTRB(6, 0, 6, 2),
                decoration: BoxDecoration(
                  color: cardColor,
                  image: dark ? bgImage : null,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: 1),
                ),
                foregroundDecoration: item.isNew
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: const Border(
                          left: BorderSide(color: XeneTheme.teal, width: 2.5),
                        ),
                        color: const Color(0x1100C5A5),
                      )
                    : null,
                child: Stack(
                  children: [
                    if (!dark && hasArtwork)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColorFiltered(
                                colorFilter: ColorFilter.mode(
                                  Colors.white.withValues(alpha: 0.90),
                                  BlendMode.modulate,
                                ),
                                child: Image(
                                  image: artworkProvider!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Colors.white,
                                      Colors.white,
                                      Colors.white.withValues(alpha: 0.62),
                                      Colors.white.withValues(alpha: 0.0),
                                    ],
                                    stops: const [0.0, 0.40, 0.55, 1.0],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.all(cardPadding),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Thumbnail (Left) — decorative, described by card label
                          ExcludeSemantics(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: thumbnailProvider == null
                                  ? Container(
                                      width: thumbnailSize,
                                      height: thumbnailSize,
                                      color: placeholderColor,
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.music_note,
                                        size: compact ? 18 : 20,
                                        color: errorIconColor,
                                      ),
                                    )
                                  : Image(
                                      image: thumbnailProvider,
                                      width: thumbnailSize,
                                      height: thumbnailSize,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                      errorBuilder: (context, error, stack) =>
                                          Container(
                                            width: thumbnailSize,
                                            height: thumbnailSize,
                                            color: placeholderColor,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Icons.music_note,
                                              size: compact ? 18 : 20,
                                              color: errorIconColor,
                                            ),
                                          ),
                                    ),
                            ),
                          ),

                          SizedBox(width: contentGap),

                          // 2. Content Frame (Right)
                          Expanded(
                            child: ExcludeSemantics(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top badges wrap instead of overflowing when the feed
                                  // column gets narrow beside the fixed sidebar.
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 3,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: badgeMaxWidth,
                                        ),
                                        child: _TypePill(
                                          type: item.contentType,
                                        ),
                                      ),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: badgeMaxWidth,
                                        ),
                                        child: _PlatformBadge(
                                          platform: item.platform,
                                        ),
                                      ),
                                      if (item.publishedAt.isAfter(
                                        DateTime.now(),
                                      ))
                                        const _PreOrderStar(),
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
                                    overflow: TextOverflow.fade,
                                  ),

                                  // Artist name
                                  Text(
                                    item.artistName,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.archivo(
                                      color: dark ? Colors.white : Colors.black,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  if (repostAttribution != null)
                                    Text(
                                      repostAttribution,
                                      style: GoogleFonts.dmMono(
                                        color: XeneTheme.scOrange,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),

                                  // Snippet
                                  if (bodyText != null && bodyText.isNotEmpty)
                                    Text(
                                      bodyText,
                                      style: GoogleFonts.archivo(
                                        color: snippetColor,
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),

                                  // Duration (SC) or track count (BC) — mutually exclusive
                                  if (item.durationSeconds != null &&
                                      item.durationSeconds! > 0)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.schedule,
                                            size: 9,
                                            color: snippetColor,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            _formatDuration(
                                              item.durationSeconds!,
                                            ),
                                            style: GoogleFonts.dmMono(
                                              color: snippetColor,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (item.trackCount != null &&
                                      item.trackCount! > 1)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.queue_music,
                                            size: 9,
                                            color: snippetColor,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            '${item.trackCount} tracks',
                                            style: GoogleFonts.dmMono(
                                              color: snippetColor,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if ([
                            'soundcloud',
                            'youtube',
                          ].contains(item.platform.toLowerCase()))
                            _SaveButton(item: item, dark: dark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// YouTube video card — full-width 16:9 thumbnail with play button overlay.
// Used when the active preset is 'videos' and the item is from YouTube.
// ---------------------------------------------------------------------------
class _YoutubeVideoCard extends StatelessWidget {
  const _YoutubeVideoCard({required this.item, this.onTap, this.dark = false});

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
    final snippetColor = dark ? Colors.white54 : Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(6, 0, 6, 2),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail + play overlay
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(7),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: item.artworkUrl ?? '',
                      fit: BoxFit.cover,
                      memCacheWidth:
                          (MediaQuery.devicePixelRatioOf(context) * 360).ceil(),
                      placeholder: (context, url) =>
                          Container(color: placeholderColor),
                      errorWidget: (context, url, error) => Container(
                        color: placeholderColor,
                        child: const Icon(
                          Icons.ondemand_video,
                          size: 40,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    // YouTube-style play button
                    Center(
                      child: Container(
                        width: 52,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xCC000000),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Info below thumbnail
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _TypePill(type: item.contentType),
                            _PlatformBadge(platform: item.platform),
                            if (item.publishedAt.isAfter(DateTime.now()))
                              const _PreOrderStar(),
                          ],
                        ),
                      ),
                      _SaveButton(item: item, dark: dark),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.title ?? 'Untitled',
                    style: GoogleFonts.archivo(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Save-to-queue button
// ---------------------------------------------------------------------------

class _SaveButton extends ConsumerWidget {
  const _SaveButton({required this.item, this.dark = false});
  final FeedItem item;
  final bool dark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAnon = ref.watch(isAnonymousProvider);
    final isQueued = ref.watch(
      queueProvider.select(
        (s) => s.items.any((i) => i.externalUrl == item.externalUrl),
      ),
    );
    final iconColor = isQueued
        ? XeneTheme.purple
        : (dark ? Colors.white : const Color(0xFFFFD23F));
    final iconShadows = dark
        ? [
            Shadow(
              color: Colors.black.withValues(alpha: 0.70),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
            Shadow(color: Colors.black.withValues(alpha: 0.70), blurRadius: 8),
          ]
        : null;

    return Semantics(
      label: isQueued ? 'Remove from queue' : 'Add to queue',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (isAnon) {
            showAuthGate(context, featureHint: 'to save tracks');
            return;
          }
          if (!isQueued) {
            ref.read(queueProvider.notifier).addItem(item);
          }
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                isQueued
                    ? Icons.bookmark
                    : (dark ? Icons.bookmark_add : Icons.bookmark_add_outlined),
                size: 24,
                color: iconColor,
                shadows: iconShadows,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

ImageProvider<Object> _resizedArtworkProvider(
  String url, {
  required int width,
  required int height,
}) {
  return ResizeImage(
    CachedNetworkImageProvider(url),
    width: width,
    height: height,
    allowUpscaling: false,
  );
}

String? _repostAttribution(FeedItem item) {
  final body = item.body?.trim();
  if (body != null && body.startsWith('\u21bb by ')) {
    return body.split('\n').first;
  }

  if (item.platform.toLowerCase() != 'soundcloud') return null;

  final title = item.title?.trim();
  if (title == null || title.isEmpty) return null;
  final separator = title.indexOf(' - ');
  if (separator <= 0) return null;

  final producer = title.substring(0, separator).trim();
  if (producer.isEmpty) return null;
  if (_normaliseName(producer) == _normaliseName(item.artistName)) {
    return null;
  }

  return '\u21bb by ${item.artistName}';
}

String? _bodyWithoutAttribution(String? body, String? attribution) {
  final clean = body?.trim();
  if (clean == null || clean.isEmpty) return null;
  if (attribution != null && clean.startsWith(attribution)) {
    final rest = clean.substring(attribution.length).trim();
    return rest.isEmpty ? null : rest;
  }
  return clean;
}

String _normaliseName(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }

  Color _getPillColor(String type) {
    switch (type.toUpperCase()) {
      case 'MIX':
        return XeneTheme.mixGold;
      case 'RELEASE':
        return XeneTheme.bcGreen;
      case 'EP':
        return XeneTheme.epPurple;
      case 'ALBUM':
        return XeneTheme.albumBlue;
      case 'TRACK':
      default:
        return XeneTheme.orange;
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
    );
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'soundcloud':
        return XeneTheme.scOrange;
      case 'bandcamp':
        return XeneTheme.bcGreen;
      case 'twitch':
        return XeneTheme.twitchPurple;
      case 'youtube':
        return XeneTheme.ytRed;
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
