import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_app/src/layout/xene_layout_metrics.dart';
import 'package:xene_app/src/providers/accessibility_provider.dart';
import 'package:xene_app/src/layout/xene_responsive_debug.dart';
import 'package:xene_app/src/providers/auth_provider.dart';
import 'package:xene_app/src/providers/nav_swipe_provider.dart';
import 'package:xene_app/src/providers/player_provider.dart';
import 'package:xene_app/src/providers/saved_provider.dart';
import 'package:xene_app/src/widgets/auth_gate_sheet.dart';
import 'package:xene_app/src/widgets/soundcloud_embed.dart';
import 'package:xene_app/src/widgets/youtube_embed.dart';
import 'package:xene_domain/xene_domain.dart';

class LogoPipPlayer extends ConsumerStatefulWidget {
  const LogoPipPlayer({super.key, this.metrics});

  final XeneLayoutMetrics? metrics;

  @override
  ConsumerState<LogoPipPlayer> createState() => _LogoPipPlayerState();
}

class _LogoPipPlayerState extends ConsumerState<LogoPipPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryController;
  double _dragOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    final reduceMotion = ref.read(accessibilityProvider).reduceMotion;
    if (reduceMotion) {
      _entryController.value = 1.0;
    } else {
      _entryController.forward();
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    setState(() {
      _dragOffset += details.delta.dx;

      if (isLandscape) {
        // Landscape (Right Edge): Only allow dragging to the right to close
        if (_dragOffset < 0) _dragOffset = 0;
      } else {
        // Portrait (Left Edge): Only allow dragging to the left to close
        if (_dragOffset > 0) _dragOffset = 0;
      }
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    ref.read(navSwipeBlockedProvider.notifier).state = false;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // Logic for swipe-to-close based on orientation
    final bool thresholdMet = isLandscape
        ? (_dragOffset > 50 || details.primaryVelocity! > 300) // Swipe Right
        : (_dragOffset < -50 || details.primaryVelocity! < -300); // Swipe Left

    if (thresholdMet) {
      _close();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  void _handleDragCancel() {
    ref.read(navSwipeBlockedProvider.notifier).state = false;
    setState(() => _dragOffset = 0);
  }

  void _close() {
    ref.read(navSwipeBlockedProvider.notifier).state = false;
    _entryController.stop();
    _entryController.value = 0.0;
    ref.read(playerProvider.notifier).stopAndHide();
  }

  @override
  Widget build(BuildContext context) {
    final layoutMetrics = widget.metrics ?? XeneLayoutScope.maybeOf(context);
    if (layoutMetrics != null) {
      XeneResponsiveDebug.values('LogoPipPlayer.receivedMetrics', {
        'playerWidth': layoutMetrics.playerWidth,
        'playerHeight': layoutMetrics.playerHeight,
      });
    }

    final playerState = ref.watch(playerProvider);
    final currentTrack = playerState.currentTrack;
    final isAnon = ref.watch(isAnonymousProvider);
    ref.watch(savedProvider);
    final isBookmarked =
        currentTrack != null &&
        ref
                .read(savedProvider.notifier)
                .matchForUrl(currentTrack.externalUrl) !=
            null;
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    final reduceMotion = ref.watch(accessibilityProvider).reduceMotion;

    // Listen for visibility change
    ref.listen(playerProvider.select((s) => s.isVisible), (previous, next) {
      if (next == true && previous != true) {
        setState(() {
          _dragOffset = 0.0;
        });
        if (reduceMotion) {
          _entryController.value = 1.0;
        } else {
          _entryController.forward(from: 0.0);
        }
      }
    });

    // Listen for track changes
    ref.listen(playerProvider.select((s) => s.currentTrack?.id), (
      previous,
      next,
    ) {
      if (next != null && next != previous && playerState.isVisible) {
        setState(() {
          _dragOffset = 0.0;
        });
        if (reduceMotion) {
          _entryController.value = 1.0;
        } else {
          _entryController.forward(from: 0.0);
        }
      }
    });

    if (!playerState.isVisible || currentTrack == null) {
      return const SizedBox.shrink();
    }
    final premiereLabel = _premiereLabel(currentTrack);
    final isPremierePreview =
        playerState.activePlatform == ActivePlatform.youtube &&
        premiereLabel != null;

    // Constants
    const double sheetWidth = 175.0;
    const double sheetHeight = 275.0;

    // Landscape vs Portrait adjustments
    final Color bgColor = isLandscape
        ? Colors.grey[350]!
        : const Color(0xFF111111);
    final Color iconColor = isLandscape ? Colors.black54 : Colors.white38;
    final Color handleColor = isLandscape ? Colors.black26 : Colors.white24;

    // Animation: Slide from right in Landscape, from left in Portrait
    final slideAnimation =
        Tween<Offset>(
          begin: isLandscape ? const Offset(1.5, 0.0) : const Offset(-1.5, 0.0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutBack),
        );

    return Positioned(
      top: isLandscape ? null : topPadding + 50,
      bottom: isLandscape ? 16.0 : null,
      left: isLandscape ? null : 0 + _dragOffset,
      right: isLandscape ? 16.0 - _dragOffset : null,
      child: SlideTransition(
        position: slideAnimation,
        child: LayoutBuilder(
          builder: (context, constraints) {
            XeneResponsiveDebug.constraints(
              'LogoPipPlayer.positioned',
              constraints,
            );
            XeneResponsiveDebug.values('LogoPipPlayer.geometry', {
              'sheetWidth': sheetWidth,
              'sheetHeight': sheetHeight,
              'isLandscape': isLandscape,
              'dragOffset': _dragOffset,
            });

            return Container(
              key: const ValueKey('logoPipPlayerSurface'),
              width: sheetWidth,
              height: sheetHeight,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: isLandscape
                    ? BorderRadius.circular(24)
                    : const BorderRadius.only(
                        topRight: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isLandscape ? 0.3 : 0.6,
                    ),
                    blurRadius: 30,
                    spreadRadius: 5,
                    offset: isLandscape
                        ? const Offset(0, 10)
                        : const Offset(10, 0),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: isLandscape
                              ? MainAxisAlignment.start
                              : MainAxisAlignment.end,
                          children: [
                            Semantics(
                              label: isBookmarked
                                  ? 'Remove bookmark'
                                  : 'Bookmark track',
                              button: true,
                              child: GestureDetector(
                                onTap: () async {
                                  if (isAnon) {
                                    showAuthGate(
                                      context,
                                      featureHint: 'to save tracks',
                                    );
                                    return;
                                  }
                                  final match = ref
                                      .read(savedProvider.notifier)
                                      .matchForUrl(currentTrack.externalUrl);
                                  if (match != null) {
                                    await ref
                                        .read(savedProvider.notifier)
                                        .unbookmark(match.id);
                                  } else {
                                    await ref
                                        .read(savedProvider.notifier)
                                        .bookmarkFeedItem(currentTrack);
                                  }
                                },
                                child: SizedBox(
                                  width: 44,
                                  height: 32,
                                  child: Icon(
                                    isBookmarked
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    color: isBookmarked
                                        ? const Color(0xFF39FF14)
                                        : iconColor,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                            Semantics(
                              label: 'Close player',
                              button: true,
                              child: GestureDetector(
                                onTap: _close,
                                child: SizedBox(
                                  width: 44,
                                  height: 32,
                                  child: Icon(
                                    Icons.close,
                                    color: iconColor,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (premiereLabel != null && !isPremierePreview)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFF0000,
                              ).withValues(alpha: isLandscape ? 0.10 : 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(
                                  0xFFFF0000,
                                ).withValues(alpha: 0.34),
                              ),
                            ),
                            child: Text(
                              premiereLabel,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isLandscape
                                    ? const Color(0xFFB00000)
                                    : const Color(0xFFFF9A9A),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),

                      // Player Well
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          child: LayoutBuilder(
                            builder: (context, wellConstraints) {
                              XeneResponsiveDebug.constraints(
                                'LogoPipPlayer.well',
                                wellConstraints,
                              );
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: switch (playerState.activePlatform) {
                                  ActivePlatform.soundcloud => SoundCloudEmbed(
                                    key: ValueKey(
                                      'pip-soundcloud-${currentTrack.id}-${currentTrack.externalUrl}',
                                    ),
                                    trackId: currentTrack.id,
                                    isVisual: true,
                                    artworkUrl: currentTrack.artworkUrl,
                                    title: currentTrack.title,
                                    artistName: currentTrack.artistName,
                                    durationSeconds:
                                        currentTrack.durationSeconds,
                                  ),
                                  ActivePlatform.youtube =>
                                    isPremierePreview
                                        ? _PremiereThumbnailPreview(
                                            item: currentTrack,
                                            label: premiereLabel,
                                            isLandscape: isLandscape,
                                          )
                                        : YouTubeEmbed(
                                            key: ValueKey(
                                              'pip-youtube-${currentTrack.id}-${currentTrack.externalUrl}',
                                            ),
                                            videoId: currentTrack.id,
                                            externalUrl:
                                                currentTrack.externalUrl,
                                            artworkUrl: currentTrack.artworkUrl,
                                          ),
                                  ActivePlatform.none =>
                                    const SizedBox.shrink(),
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Drag Handle — gesture only, no semantic meaning.
                  // Positioned must be a direct child of Stack; ExcludeSemantics
                  // wraps the gesture *inside* it (not around it).
                  Positioned(
                    top: 32,
                    bottom: 0,
                    left: isLandscape ? 0 : null,
                    right: isLandscape ? null : 0,
                    width: 50,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: _handleDragUpdate,
                        onHorizontalDragStart: (_) {
                          ref.read(navSwipeBlockedProvider.notifier).state =
                              true;
                        },
                        onHorizontalDragEnd: _handleDragEnd,
                        onHorizontalDragCancel: _handleDragCancel,
                        child: Align(
                          alignment: isLandscape
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            width: 4,
                            height: 50,
                            margin: isLandscape
                                ? const EdgeInsets.only(left: 4)
                                : const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: handleColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
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
    );
  }
}

class _PremiereThumbnailPreview extends StatelessWidget {
  const _PremiereThumbnailPreview({
    required this.item,
    required this.label,
    required this.isLandscape,
  });

  final FeedItem item;
  final String label;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final artworkUrl = item.artworkUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (artworkUrl != null && artworkUrl.isNotEmpty)
          Image.network(
            artworkUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _PremiereThumbnailFallback(),
          )
        else
          const _PremiereThumbnailFallback(),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.78),
              ],
            ),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: 10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0000).withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (item.title?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 7),
                Text(
                  item.title!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isLandscape ? 10 : 11,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PremiereThumbnailFallback extends StatelessWidget {
  const _PremiereThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF120808),
      child: Center(
        child: Icon(Icons.event_available, color: Color(0xFFFF6B6B), size: 32),
      ),
    );
  }
}

String? _premiereLabel(FeedItem item) {
  if (item.platform.toLowerCase() != 'youtube') return null;
  final date = _upcomingDate(item);
  if (date == null) return null;
  return 'PREMIERES ON ${_formatShortDateTime(date)}';
}

DateTime? _upcomingDate(FeedItem item) {
  final now = DateTime.now();
  final releaseAt = item.releaseAt?.toLocal();
  if (item.isUpcoming && releaseAt != null) return releaseAt;
  if (releaseAt != null && releaseAt.isAfter(now)) return releaseAt;
  final publishedAt = item.publishedAt.toLocal();
  if (publishedAt.isAfter(now)) return publishedAt;
  return _premiereDateFromText(item.title) ?? _premiereDateFromText(item.body);
}

DateTime? _premiereDateFromText(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final match = RegExp(
    r'premieres?\s+(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{2,4})(?:,?\s+(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?))?',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) return null;

  final month = int.tryParse(match.group(1)!);
  final day = int.tryParse(match.group(2)!);
  var year = int.tryParse(match.group(3)!);
  if (month == null || day == null || year == null) return null;
  if (year < 100) year += 2000;

  var hour = int.tryParse(match.group(4) ?? '0') ?? 0;
  final minute = int.tryParse(match.group(5) ?? '0') ?? 0;
  final period = match.group(6)?.toLowerCase().replaceAll('.', '');
  if (period == 'pm' && hour < 12) hour += 12;
  if (period == 'am' && hour == 12) hour = 0;

  final parsed = DateTime(year, month, day, hour, minute);
  return parsed.isAfter(DateTime.now()) ? parsed : null;
}

String _formatShortDateTime(DateTime value) {
  final local = value.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.month}.${local.day}.${local.year % 100} $hour12:$minute $period';
}
