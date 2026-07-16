import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:xene_app/src/layout/xene_layout_metrics.dart';
import 'package:xene_app/src/layout/xene_responsive_debug.dart';
import 'package:xene_domain/xene_domain.dart';
import 'package:xene_app/src/providers/feed_provider.dart';
import 'package:xene_app/src/providers/preset_provider.dart';
import 'package:xene_app/src/providers/sheet_provider.dart';
import 'package:xene_app/src/widgets/xene_content_modal.dart';
import 'package:xene_app/src/widgets/xene_feed_card.dart';

const _kToggleHeight = 30.0;
const _kSheetGestureZoneHeight = 74.0;

class XeneDraggableSheet extends ConsumerStatefulWidget {
  const XeneDraggableSheet({super.key, this.metrics});

  final XeneLayoutMetrics? metrics;

  @override
  ConsumerState<XeneDraggableSheet> createState() => _XeneDraggableSheetState();
}

class _XeneDraggableSheetState extends ConsumerState<XeneDraggableSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _jumpController;
  late Animation<double> _jumpAnimation;
  // Tracks whether the archive fetch has been triggered.
  // Once true, further sheet opens are no-ops (ArchiveFetchNotifier is idempotent).
  bool _archiveFetched = false;
  String? _lastPresetSlug;
  FeedMode? _lastFeedMode;
  // True after the first-load card stagger has run. Reset on preset/mode change.
  bool _archiveCardsAnimated = false;
  // Tracked so it can be cancelled when the archive reloads, preventing a stale
  // timer from flipping _archiveCardsAnimated=true before the new stagger plays.
  Timer? _staggerResetTimer;
  // Incremented on preset/mode change — used in card keys so Flutter fully
  // recreates _ArchiveFeedCard widgets (fresh initState) rather than reusing
  // state where _animated is already locked to false.
  int _archiveGeneration = 0;
  // Deferred-stagger flags — see data branch in archiveAsync.when().
  bool _sheetWasCollapsed = true;
  bool _dataArrivedCollapsed = false;
  Stopwatch? _archiveLoadWatch;
  int _archiveLoadSeq = 0;
  int _archiveLoadingLoggedGen = -1;
  bool _archiveLottieVisible = false;
  bool _sheetDragActive = false;
  double _sheetDragTotalDy = 0.0;

  String _archiveElapsedLabel() {
    final elapsed = _archiveLoadWatch?.elapsedMilliseconds;
    return elapsed == null ? 'n/a' : '${elapsed}ms';
  }

  @override
  void initState() {
    super.initState();
    _jumpController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    _jumpAnimation =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 0.0,
              end: -12.0,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 50,
          ),
          TweenSequenceItem(
            tween: Tween<double>(
              begin: -12.0,
              end: 0.0,
            ).chain(CurveTween(curve: Curves.easeInCubic)),
            weight: 50,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _jumpController,
            curve: const Interval(0.0, 0.1, curve: Curves.linear),
          ),
        );
  }

  @override
  void dispose() {
    _staggerResetTimer?.cancel();
    _jumpController.dispose();
    super.dispose();
  }

  Widget _dragHandle(DraggableScrollableController ctrl, double minRatio) {
    return GestureDetector(
      onTap: () {
        if (ctrl.isAttached) {
          ctrl.animateTo(
            minRatio,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 20,
        alignment: Alignment.center,
        child: Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _archiveHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
      child: Text(
        '8 – 31 DAYS',
        style: GoogleFonts.teko(fontSize: 18, color: const Color(0xFF888888)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _collapsedPreview(
    AsyncValue<List<FeedItem>> feedAsync,
    FeedMode mode,
  ) {
    final label = mode == FeedMode.fullFeed ? 'GREEDY' : 'CYCLED';

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFFF5500).withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFFFF5500).withValues(alpha: 0.34),
            ),
          ),
          child: const Icon(
            Icons.keyboard_double_arrow_up_rounded,
            color: Color(0xFFFF5500),
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '8 - 31 DAYS  /  $label',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.teko(
              fontSize: 16,
              color: Colors.white70,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  DateTime _localDate(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  List<_ArchiveDateSection> _buildDateSections(List<FeedItem> items) {
    final sorted = List<FeedItem>.from(items)
      ..sort((a, b) {
        final byDate = b.timelineAt.compareTo(a.timelineAt);
        if (byDate != 0) return byDate;

        final byArtist = a.artistName.compareTo(b.artistName);
        if (byArtist != 0) return byArtist;

        return a.id.compareTo(b.id);
      });

    final sections = <_ArchiveDateSection>[];
    _ArchiveDateSection? currentSection;

    for (final item in sorted) {
      final date = _localDate(item.timelineAt);

      if (currentSection == null || currentSection.date != date) {
        currentSection = _ArchiveDateSection(date: date, items: <FeedItem>[]);
        sections.add(currentSection);
      }

      currentSection.items.add(item);
    }

    return sections;
  }

  void _fetchArchive({Duration delay = Duration.zero}) {
    if (_archiveFetched) {
      if (delay == Duration.zero) {
        ref.read(archiveFetchProvider.notifier).fetchOnce();
      }
      return;
    }
    _archiveFetched = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(delay, () {
        if (mounted) {
          ref.read(archiveFetchProvider.notifier).fetchOnce();
        }
      });
    });
  }

  Widget _buildModeToggle(FeedMode mode) {
    final isFullFeed = mode == FeedMode.fullFeed;
    return GestureDetector(
      onTap: () {
        final next = isFullFeed ? FeedMode.methodical : FeedMode.fullFeed;
        ref.read(feedModeProvider.notifier).state = next;
      },
      child: Container(
        height: _kToggleHeight,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(_kToggleHeight / 2),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Stack(
          children: [
            // Sliding thumb
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: isFullFeed
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isFullFeed
                        ? const Color(0xFFFF5500)
                        : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(
                      (_kToggleHeight / 2) - 3,
                    ),
                  ),
                ),
              ),
            ),
            // Labels
            Row(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      'CYCLED',
                      style: GoogleFonts.teko(
                        fontSize: 12,
                        color: !isFullFeed ? Colors.white : Colors.white38,
                        letterSpacing: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            'GREEDY',
                            style: GoogleFonts.teko(
                              fontSize: 12,
                              color: isFullFeed ? Colors.white : Colors.white38,
                              letterSpacing: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 11,
                          color: isFullFeed ? Colors.white : Colors.white38,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildArchiveSlivers(
    List<_ArchiveDateSection> sections, {
    bool shouldAnimate = false,
  }) {
    Widget padSliver(Widget sliver) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        sliver: sliver,
      );
    }

    final slivers = <Widget>[
      padSliver(SliverToBoxAdapter(child: _archiveHeader())),
    ];

    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];

      slivers.add(
        padSliver(
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _ArchiveDateHeaderDelegate(
                  child: _ArchiveDateDivider(date: section.date),
                  backgroundColor: Colors.black,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, itemIndex) {
                  final item = section.items[itemIndex];
                  // Section-relative animIndex: each date group cascades in
                  // after the previous. Using sectionIndex*3+itemIndex means
                  // section 0 → indices 0,1,2; section 1 → 3,4,5; etc.
                  // Capped at 12 (max delay 540ms) so no card waits longer
                  // than 540ms regardless of how many sections there are.
                  final sectionAnimIndex = min(
                    sectionIndex * 3 + itemIndex,
                    12,
                  );
                  return _ArchiveFeedCard(
                    key: ValueKey(
                      'arc_g${_archiveGeneration}_${sectionIndex}_$itemIndex',
                    ),
                    item: item,
                    onTap: () => showXeneContent(context, item),
                    animIndex: shouldAnimate ? sectionAnimIndex : -1,
                  );
                }, childCount: section.items.length),
              ),
            ],
          ),
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final layoutMetrics = widget.metrics ?? XeneLayoutScope.maybeOf(context);
    if (layoutMetrics != null) {
      XeneResponsiveDebug.values('Sheet.receivedMetrics', {
        'sheetMinHeight': layoutMetrics.sheetMinHeight,
        'sheetMaxHeight': layoutMetrics.sheetMaxHeight,
        'archiveSheetMinRatio': layoutMetrics.archiveSheetMinRatio,
        'archiveSheetMaxRatio': layoutMetrics.archiveSheetMaxRatio,
      });
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final topOffset = topPadding + 56;

    final sheetController = ref.watch(sheetProvider);
    final feedAsync = ref.watch(feedProvider);
    final activePresetSlug = ref.watch(activePresetSlugProvider);
    final archiveAsync = ref.watch(filteredArchiveFeedProvider);
    final feedMode = ref.watch(feedModeProvider);

    // Reset animation state synchronously when mode changes so the first data
    // build (not a delayed ref.listen callback) already sees shouldAnimate=true.
    // CRITICAL: also cancel the stagger timer — if it was still ticking from the
    // previous mode's load, it would fire and set _archiveCardsAnimated=true
    // before the new data arrives, making shouldAnimate=false on first data build.
    if (_lastFeedMode != feedMode) {
      _lastFeedMode = feedMode;
      _archiveFetched = false;
      _staggerResetTimer?.cancel();
      _staggerResetTimer = null;
      _archiveGeneration++;
      _archiveCardsAnimated = false;
      _sheetWasCollapsed = true;
      _dataArrivedCollapsed = false;
      debugPrint(
        '[Sheet] MODE CHANGE → mode=$feedMode gen=$_archiveGeneration animated=false archiveAsync.isLoading=${archiveAsync.isLoading}',
      );
    }

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    // Portrait: the expanded sheet's top edge lands at logoBottom. The +7 drops
    // that resting edge 7px below the sidebar XENE logo so the snapped-open sheet
    // no longer touches it. Landscape is unaffected (sidebar logo crawls there).
    final logoBottom = isLandscape ? topOffset : topOffset + 297;

    final maxRatio = ((screenHeight - logoBottom + 4.0) / screenHeight).clamp(
      0.1,
      1.0,
    );

    // Collapsed height. The 20px drag handle sits at the TOP of the collapsed
    // sheet, so its grab zone lands at ~minHeight above the screen bottom. On a
    // home-indicator iPhone the old flat 23px put that handle INSIDE the system
    // edge-gesture zone (≈ the bottom safe-area inset), so iOS claimed every
    // upward swipe as home/app-switcher and the sheet never got the drag. Fold
    // the bottom inset + a tap-sized margin in so the handle clears that zone;
    // the sheet still fills to the physical bottom edge. (Swipes from the very
    // bottom edge remain iOS's home gesture by design — grab the handle instead.)
    final minHeight = bottomPadding + 44.0;
    final minRatio = (minHeight / screenHeight).clamp(0.01, maxRatio);

    // Capture collapse state now so archiveAsync.when(data:) can decide
    // whether to skip the stagger. If data arrives via prewarm while the sheet
    // is still closed, the animation would run and complete invisibly (the parent
    // Opacity wrapper is 0.0 when collapsed), causing all cards to appear at
    // full opacity simultaneously once the sheet opens.
    double buildSize = minRatio;
    if (sheetController.isAttached) {
      buildSize = sheetController.size;
    }
    final isCollapsedAtBuild = (buildSize - minRatio).abs() < 0.001;

    return DraggableScrollableSheet(
      controller: sheetController,
      initialChildSize: minRatio,
      minChildSize: minRatio,
      maxChildSize: maxRatio,
      snap: true,
      // snapSizes omitted — min and max are the only snap targets, which
      // is the default when snap:true has no explicit snapSizes. Passing
      // [minRatio, maxRatio] triggers a Flutter assertion that snapSizes
      // must be strictly between min and max (exclusive).
      builder: (context, scrollController) {
        return ListenableBuilder(
          listenable: sheetController,
          builder: (context, child) {
            double currentSize = minRatio;
            if (sheetController.isAttached) {
              currentSize = sheetController.size;
            }

            final opacity = ((currentSize - minRatio) / 0.05).clamp(0.0, 1.0);
            final sheetColor = Colors.black.withValues(
              alpha: opacity.clamp(0.8, 1.0),
            );

            final isCollapsed = (currentSize - minRatio).abs() < 0.001;

            // Detect collapse→expand transition and trigger deferred stagger.
            if (_sheetWasCollapsed && !isCollapsed) {
              _sheetWasCollapsed = false;
              if (_dataArrivedCollapsed && !_archiveCardsAnimated) {
                _dataArrivedCollapsed = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _archiveGeneration++);
                });
              }
            } else if (isCollapsed && !_sheetWasCollapsed) {
              _sheetWasCollapsed = true;
            }

            if (_lastPresetSlug != activePresetSlug) {
              _lastPresetSlug = activePresetSlug;
              _archiveFetched = false;
              _staggerResetTimer?.cancel();
              _staggerResetTimer = null;
              _archiveGeneration++;
              _archiveCardsAnimated = false;
              _sheetWasCollapsed = true;
              _dataArrivedCollapsed = false;
              debugPrint(
                '[Sheet] PRESET CHANGE → preset=$activePresetSlug gen=$_archiveGeneration animated=false',
              );
            }

            // Prewarm one small archive page after the recent feed settles.
            // Opening the sheet still triggers it immediately if prewarm has
            // not happened yet.
            if (isCollapsed && feedAsync.hasValue && !_archiveFetched) {
              _fetchArchive(delay: const Duration(milliseconds: 900));
            }

            // Trigger the archive fetch the first time the sheet opens.
            if (!isCollapsed && !_archiveFetched) {
              _fetchArchive();
            }

            return AnimatedBuilder(
              animation: _jumpAnimation,
              builder: (context, animChild) {
                final offset = isCollapsed ? _jumpAnimation.value : 0.0;
                return Transform.translate(
                  offset: Offset(0, offset),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (isCollapsed)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: -100,
                          height: 100,
                          child: Container(color: sheetColor),
                        ),
                      animChild!,
                    ],
                  ),
                );
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  if (!sheetController.isAttached) return;
                  final startedInHeader =
                      event.localPosition.dy <= _kSheetGestureZoneHeight;
                  final nearCollapsed =
                      (sheetController.size - minRatio).abs() < 0.04;
                  _sheetDragActive = startedInHeader || nearCollapsed;
                  _sheetDragTotalDy = 0.0;
                },
                onPointerMove: (event) {
                  if (!_sheetDragActive) return;
                  // buttons == 0 means hover (no button / finger held down).
                  if (event.buttons == 0) return;
                  if (event.delta.dy.abs() < 0.5) return;
                  if (!sheetController.isAttached) return;
                  _sheetDragTotalDy += event.delta.dy;
                  final delta = -event.delta.dy / screenHeight;
                  sheetController.jumpTo(
                    (sheetController.size + delta).clamp(minRatio, maxRatio),
                  );
                },
                onPointerUp: (_) {
                  if (!_sheetDragActive) return;
                  _sheetDragActive = false;
                  if (!sheetController.isAttached) return;
                  final mid = (minRatio + maxRatio) / 2;
                  final target = _sheetDragTotalDy > 24
                      ? minRatio
                      : _sheetDragTotalDy < -24
                      ? maxRatio
                      : sheetController.size >= mid
                      ? maxRatio
                      : minRatio;
                  sheetController.animateTo(
                    target,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
                onPointerCancel: (_) {
                  if (!_sheetDragActive) return;
                  _sheetDragActive = false;
                  if (!sheetController.isAttached) return;
                  final mid = (minRatio + maxRatio) / 2;
                  final target = _sheetDragTotalDy > 24
                      ? minRatio
                      : _sheetDragTotalDy < -24
                      ? maxRatio
                      : sheetController.size >= mid
                      ? maxRatio
                      : minRatio;
                  sheetController.animateTo(
                    target,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: sheetColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          _dragHandle(sheetController, minRatio),
                          Expanded(
                            child: ClipRect(
                              // OverflowBox decouples the content layout from the
                              // sheet's current height so no relayout happens during
                              // drag.  The child is wrapped in a SizedBox(maxRatio *
                              // screenHeight) so inner Expanded widgets have a real
                              // bound rather than infinity (which would give them 0).
                              // ClipRect hides any overflow when collapsed.
                              child: Opacity(
                                opacity: opacity,
                                child: OverflowBox(
                                  maxHeight: double.infinity,
                                  alignment: Alignment.topCenter,
                                  child: child,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isCollapsed)
                        Positioned(
                          left: 24,
                          right: 24,
                          top: 22,
                          child: IgnorePointer(
                            child: _collapsedPreview(feedAsync, feedMode),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
          child: SizedBox(
            // Explicit height gives the inner Expanded(archive) a real bound
            // even though OverflowBox above passes infinity down.
            // Subtract 20 (drag handle) so content doesn't clip the last card.
            height: (maxRatio * screenHeight - 20).clamp(
              200.0,
              double.infinity,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
                  child: _buildModeToggle(feedMode),
                ),
                Expanded(
                  child: archiveAsync.when(
                    loading: () {
                      if (_archiveLoadingLoggedGen != _archiveGeneration ||
                          !_archiveLottieVisible) {
                        _archiveLoadSeq++;
                        _archiveLoadingLoggedGen = _archiveGeneration;
                        _archiveLoadWatch = Stopwatch()..start();
                        _archiveLottieVisible = true;
                        debugPrint(
                          '[Sheet][UX seq=$_archiveLoadSeq +0ms] '
                          'Archive Lottie shown gen=$_archiveGeneration '
                          'preset=$activePresetSlug mode=$feedMode',
                        );
                      }
                      // Use scrollController so the DraggableScrollableSheet keeps
                      // its scroll relationship intact. Without this, the sheet
                      // detects a detached controller and snaps back to minRatio,
                      // causing cards to appear invisible (opacity=0) on data arrival.
                      return CustomScrollView(
                        controller: scrollController,
                        physics: const NeverScrollableScrollPhysics(),
                        slivers: [
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Lottie.asset(
                                'assets/animations/LoadingLottie.json',
                                width: 120,
                                height: 120,
                                repeat: true,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                    error: (e, _) {
                      if (_archiveLottieVisible) {
                        _archiveLottieVisible = false;
                        debugPrint(
                          '[Sheet][UX seq=$_archiveLoadSeq +${_archiveElapsedLabel()}] '
                          'Archive Lottie hidden -> error gen=$_archiveGeneration error=$e',
                        );
                      }
                      return ListView(
                        controller: scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        children: [
                          Center(
                            child: Text(
                              'Error loading archive',
                              style: GoogleFonts.archivo(color: Colors.white54),
                            ),
                          ),
                        ],
                      );
                    },
                    data: (items) {
                      if (_archiveLottieVisible) {
                        _archiveLottieVisible = false;
                        debugPrint(
                          '[Sheet][UX seq=$_archiveLoadSeq +${_archiveElapsedLabel()}] '
                          'Archive Lottie hidden -> data build gen=$_archiveGeneration '
                          'items=${items.length} collapsed=$isCollapsedAtBuild',
                        );
                      }
                      if (items.isEmpty) {
                        return ListView(
                          controller: scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          children: [
                            _archiveHeader(),
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Center(
                                child: Text(
                                  'Nothing in the archive yet',
                                  style: GoogleFonts.archivo(
                                    color: Colors.white38,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      final sections = _buildDateSections(items);

                      // Prewarm fetch delivered data while the sheet was closed.
                      // Don't mark _archiveCardsAnimated=true here — instead defer
                      // the stagger to when the sheet first opens. The transition
                      // detector in ListenableBuilder.builder will increment the
                      // generation, rebuilding cards with shouldAnimate=true.
                      if (isCollapsedAtBuild && !_archiveCardsAnimated) {
                        _dataArrivedCollapsed = true;
                        debugPrint(
                          '[Sheet] DATA arrived COLLAPSED — deferring stagger gen=$_archiveGeneration',
                        );
                      }

                      // No animation if: already animated, or data arrived while
                      // collapsed (wait for sheet to open before triggering stagger).
                      final shouldAnimate =
                          !_archiveCardsAnimated && !isCollapsedAtBuild;

                      debugPrint(
                        '[Sheet] DATA BUILD gen=$_archiveGeneration items=${items.length} '
                        'shouldAnimate=$shouldAnimate archiveCardsAnimated=$_archiveCardsAnimated '
                        'timerActive=${_staggerResetTimer != null} collapsed=$isCollapsedAtBuild',
                      );

                      if (shouldAnimate) {
                        _staggerResetTimer?.cancel();
                        // Max animIndex=12 × 45ms interval + 260ms animation + 100ms buffer.
                        const staggerMs = 12 * 45 + 260 + 100; // 900ms
                        debugPrint(
                          '[Sheet] scheduling stagger timer ${staggerMs}ms gen=$_archiveGeneration',
                        );
                        _staggerResetTimer = Timer(
                          Duration(milliseconds: staggerMs),
                          () {
                            _staggerResetTimer = null;
                            debugPrint(
                              '[Sheet] stagger timer fired → archiveCardsAnimated=true gen=$_archiveGeneration',
                            );
                            if (mounted)
                              setState(() => _archiveCardsAnimated = true);
                          },
                        );
                      }

                      return NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          final metrics = notification.metrics;
                          if (metrics.maxScrollExtent > 0 &&
                              metrics.maxScrollExtent - metrics.pixels < 600) {
                            ref
                                .read(archiveFetchProvider.notifier)
                                .fetchNextPage();
                          }
                          return false;
                        },
                        child: CustomScrollView(
                          controller: scrollController,
                          physics: const BouncingScrollPhysics(),
                          slivers: _buildArchiveSlivers(
                            sections,
                            shouldAnimate: shouldAnimate,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ), // Column
          ), // SizedBox
        );
      },
    );
  }
}

class _ArchiveDateDivider extends StatelessWidget {
  const _ArchiveDateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Colors.white12, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              DateFormat('MM.dd.yy').format(date),
              style: GoogleFonts.teko(
                fontSize: 20,
                color: const Color(0xFFFF5500),
                letterSpacing: 2.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          const Expanded(child: Divider(color: Colors.white12, thickness: 1)),
        ],
      ),
    );
  }
}

class _ArchiveDateSection {
  _ArchiveDateSection({required this.date, required this.items});

  final DateTime date;
  final List<FeedItem> items;
}

// Wraps XeneFeedCard with a one-shot fade + slide-up animation on first load.
// animIndex >= 0 triggers the animation with a stagger delay of animIndex * 55ms.
// animIndex == -1 renders the card immediately with no animation.
class _ArchiveFeedCard extends StatefulWidget {
  const _ArchiveFeedCard({
    required super.key,
    required this.item,
    required this.onTap,
    required this.animIndex,
  });

  final FeedItem item;
  final VoidCallback onTap;
  final int animIndex;

  @override
  State<_ArchiveFeedCard> createState() => _ArchiveFeedCardState();
}

class _ArchiveFeedCardState extends State<_ArchiveFeedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  // Locked at initState — new generation keys recreate the widget so this is
  // always set correctly for the current animation round.
  late final bool _animated;

  // Called on every animation tick so this widget rebuilds independently of
  // any parent rebuild cycle. FadeTransition (AnimatedWidget) was the previous
  // approach but its internal setState can be suppressed inside SliverList
  // when the delegate's shouldRebuild=true causes the sliver to rebuild the
  // element before AnimatedWidget's listener has a chance to fire.
  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _animated = widget.animIndex >= 0;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    debugPrint(
      '[ArchiveCard] initState key=${widget.key} animIndex=${widget.animIndex} _animated=$_animated',
    );

    if (_animated) {
      _ctrl.addListener(_onTick);
      if (widget.animIndex == 0) {
        _ctrl.forward();
      } else {
        Future.delayed(Duration(milliseconds: widget.animIndex * 45), () {
          if (mounted) _ctrl.forward();
        });
      }
    } else {
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        XeneResponsiveDebug.constraints('ArchiveCard', constraints);
        XeneResponsiveDebug.values('ArchiveCard.item', {
          'id': widget.item.id,
          'platform': widget.item.platform,
          'contentType': widget.item.contentType,
          'animated': _animated,
          'animIndex': widget.animIndex,
        });

        final card = XeneFeedCard(
          item: widget.item,
          dark: true,
          onTap: widget.onTap,
        );

        if (!_animated) {
          return card;
        }
        final t = Curves.easeOut.transform(_ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1.0 - t) * 10.0),
            child: card,
          ),
        );
      },
    );
  }
}

class _ArchiveDateHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ArchiveDateHeaderDelegate({
    required this.child,
    required this.backgroundColor,
  });

  final Widget child;
  final Color backgroundColor;

  @override
  double get minExtent => 34;

  @override
  double get maxExtent => 34;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(color: backgroundColor),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _ArchiveDateHeaderDelegate oldDelegate) {
    return child != oldDelegate.child ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
