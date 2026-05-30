import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_app/src/layout/xene_layout_metrics.dart';
import 'package:xene_app/src/layout/xene_responsive_debug.dart';
import 'package:xene_app/src/providers/auth_provider.dart';
import 'package:xene_app/src/providers/player_provider.dart';
import 'package:xene_app/src/providers/saved_provider.dart';
import 'package:xene_app/src/widgets/auth_gate_sheet.dart';
import 'package:xene_app/src/widgets/soundcloud_embed.dart';
import 'package:xene_app/src/widgets/youtube_embed.dart';

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

    // Auto-start animation when widget is created
    _entryController.forward();
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

  void _close() async {
    if (_entryController.isAnimating) return;
    await _entryController.reverse();
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

    // Listen for visibility change
    ref.listen(playerProvider.select((s) => s.isVisible), (previous, next) {
      if (next == true && previous != true) {
        setState(() {
          _dragOffset = 0.0;
        });
        _entryController.forward(from: 0.0);
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
        _entryController.forward(from: 0.0);
      }
    });

    if (!playerState.isVisible || currentTrack == null) {
      return const SizedBox.shrink();
    }

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
                            GestureDetector(
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
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _close,
                              child: Icon(
                                Icons.close,
                                color: iconColor,
                                size: 16,
                              ),
                            ),
                          ],
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
                                  ),
                                  ActivePlatform.youtube => YouTubeEmbed(
                                    key: ValueKey(
                                      'pip-youtube-${currentTrack.id}-${currentTrack.externalUrl}',
                                    ),
                                    videoId: currentTrack.id,
                                    externalUrl: currentTrack.externalUrl,
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

                  // Drag Handle
                  Positioned(
                    top: 32,
                    bottom: 0,
                    left: isLandscape ? 0 : null,
                    right: isLandscape ? null : 0,
                    width: 50,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: _handleDragUpdate,
                      onHorizontalDragEnd: _handleDragEnd,
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
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
