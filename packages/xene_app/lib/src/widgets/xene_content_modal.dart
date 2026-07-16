import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xene_app/src/layout/xene_responsive_debug.dart';
import 'package:xene_domain/xene_domain.dart';

import '../providers/player_provider.dart';
import 'bandcamp_open_button.dart';

class XeneContentModal extends ConsumerWidget {
  const XeneContentModal({super.key, required this.item});

  final FeedItem item;

  Future<void> _launchUrl(String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('[UI] Error launching URL: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final isCurrent = playerState.currentTrack?.id == item.id;
    final isPlaying = isCurrent && playerState.isPlaying;
    final isPlayable = canPlayInApp(item);
    final repostAttribution = _repostAttribution(item);
    final bodyText = _bodyWithoutAttribution(item.body, repostAttribution);
    final bottomInteractionPadding =
        MediaQuery.of(context).padding.bottom + 128;

    return LayoutBuilder(
      builder: (context, constraints) {
        XeneResponsiveDebug.constraints('ContentModal', constraints);
        XeneResponsiveDebug.values('ContentModal.item', {
          'id': item.id,
          'platform': item.platform,
          'contentType': item.contentType,
          'isPlayable': isPlayable,
        });

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF111111),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              children: [
                _PinnedDismissPill(onDismiss: () => Navigator.pop(context)),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      24,
                      12,
                      24,
                      bottomInteractionPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: LayoutBuilder(
                            builder: (context, artworkConstraints) {
                              final artworkSize = artworkConstraints.maxWidth
                                  .clamp(96.0, 200.0)
                                  .toDouble();

                              XeneResponsiveDebug.values(
                                'ContentModal.artwork',
                                {
                                  'maxWidth': artworkConstraints.maxWidth,
                                  'artworkSize': artworkSize,
                                },
                              );

                              return SizedBox(
                                key: const ValueKey('contentModalArtwork'),
                                width: artworkSize,
                                height: artworkSize,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: CachedNetworkImage(
                                        imageUrl: item.artworkUrl ?? '',
                                        width: artworkSize,
                                        height: artworkSize,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    if (isPlayable)
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            print(
                                              '[UI] Play button tapped for item: ${item.id}',
                                            );
                                            ref
                                                .read(playerProvider.notifier)
                                                .playTrack(item);
                                            Navigator.pop(context);
                                          },
                                          borderRadius: BorderRadius.circular(
                                            50,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.black.withValues(
                                                alpha: 0.4,
                                              ),
                                            ),
                                            child: Icon(
                                              isPlaying
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              color: Colors.white,
                                              size: (artworkSize * 0.24)
                                                  .clamp(32.0, 48.0)
                                                  .toDouble(),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _PlatformBadge(platform: item.platform),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                item.contentType.toUpperCase(),
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: const TextStyle(
                                  color: Color(0xFFFF5500),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          item.title ?? 'Untitled',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                          softWrap: true,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.artistName,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (repostAttribution != null) ...[
                          const SizedBox(height: 10),
                          _RepostAttribution(text: repostAttribution),
                        ],
                        const SizedBox(height: 24),
                        if (bodyText != null && bodyText.isNotEmpty)
                          Text(
                            bodyText,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 15,
                              height: 1.6,
                            ),
                          ),
                        const SizedBox(height: 40),
                        Center(
                          child: item.platform.toLowerCase() == 'bandcamp'
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    BandcampOpenButton(
                                      onTap: () => _launchUrl(item.externalUrl),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'OPEN IN BANDCAMP',
                                      style: GoogleFonts.teko(
                                        color: Colors.white38,
                                        fontSize: 12,
                                        letterSpacing: 1.0,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _launchUrl(item.externalUrl),
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: _getPlatformIcon(item.platform),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'TAP TO OPEN',
                                      style: GoogleFonts.teko(
                                        color: Colors.white38,
                                        fontSize: 12,
                                        letterSpacing: 1.0,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'soundcloud':
        return Image.asset(
          'assets/soundcloud_logo.png',
          width: 32,
          height: 32,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.cloud, color: Color(0xFFFF5500), size: 32),
        );
      case 'youtube':
        return Image.asset(
          'assets/yt_icon_red_digital.png',
          width: 32,
          height: 32,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.play_circle_filled,
            color: Color(0xFFFF0000),
            size: 32,
          ),
        );
      default:
        return const Icon(Icons.launch, color: Colors.white24, size: 24);
    }
  }
}

class _RepostAttribution extends StatelessWidget {
  const _RepostAttribution({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5500).withValues(alpha: 0.14),
          border: Border.all(
            color: const Color(0xFFFF5500).withValues(alpha: 0.38),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.dmMono(
            color: const Color(0xFFFFA06A),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
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

class _PinnedDismissPill extends StatelessWidget {
  const _PinnedDismissPill({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      onVerticalDragUpdate: (details) {
        if ((details.primaryDelta ?? 0) > 3) {
          onDismiss();
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        platform.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

void showXeneContent(BuildContext context, FeedItem item) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => XeneContentModal(item: item),
  );
}
