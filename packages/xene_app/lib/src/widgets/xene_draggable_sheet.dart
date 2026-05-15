import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:xene_domain/xene_domain.dart';
import 'package:xene_app/src/providers/feed_provider.dart';
import 'package:xene_app/src/providers/preset_provider.dart';
import 'package:xene_app/src/providers/sheet_provider.dart';
import 'package:xene_app/src/widgets/xene_content_modal.dart';
import 'package:xene_app/src/widgets/xene_feed_card.dart';

const _kToggleHeight = 30.0;

class XeneDraggableSheet extends ConsumerStatefulWidget {
  const XeneDraggableSheet({super.key});

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
      ),
    );
  }

  DateTime _localDate(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  List<_ArchiveDateSection> _buildDateSections(List<FeedItem> items) {
    final sorted = List<FeedItem>.from(items)
      ..sort((a, b) {
        final byDate = b.publishedAt.compareTo(a.publishedAt);
        if (byDate != 0) return byDate;

        final byArtist = a.artistName.compareTo(b.artistName);
        if (byArtist != 0) return byArtist;

        return a.id.compareTo(b.id);
      });

    final sections = <_ArchiveDateSection>[];
    _ArchiveDateSection? currentSection;

    for (final item in sorted) {
      final date = _localDate(item.publishedAt);

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
        final next =
            isFullFeed ? FeedMode.methodical : FeedMode.fullFeed;
        ref.read(feedModeProvider.notifier).state = next;
      },
      child: Container(
        height: _kToggleHeight,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(_kToggleHeight / 2),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
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
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'FULL GREED',
                          style: GoogleFonts.teko(
                            fontSize: 12,
                            color:
                                isFullFeed ? Colors.white : Colors.white38,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 11,
                          color:
                              isFullFeed ? Colors.white : Colors.white38,
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

  List<Widget> _buildArchiveSlivers(List<_ArchiveDateSection> sections) {
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
                  return XeneFeedCard(
                    key: ValueKey(
                      'archive_${sectionIndex}_${itemIndex}_${item.id}',
                    ),
                    item: item,
                    dark: true,
                    onTap: () => showXeneContent(context, item),
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
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final topOffset = topPadding + 56;

    final sheetController = ref.watch(sheetProvider);
    final feedAsync = ref.watch(feedProvider);
    final activePresetSlug = ref.watch(activePresetSlugProvider);
    final archiveAsync = ref.watch(filteredArchiveFeedProvider);
    final feedMode = ref.watch(feedModeProvider);

    // Reset the archive fetch gate when the feed mode changes so the sheet
    // re-fetches with the new mode on its next open (or immediately if open).
    if (_lastFeedMode != feedMode) {
      _lastFeedMode = feedMode;
      _archiveFetched = false;
    }

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final logoBottom = isLandscape ? topOffset : topOffset + 277;

    final maxRatio = ((screenHeight - logoBottom) / screenHeight).clamp(
      0.1,
      1.0,
    );

    const double minHeight = 23.0;
    final minRatio = (minHeight / screenHeight).clamp(0.01, maxRatio);

    return DraggableScrollableSheet(
      controller: sheetController,
      initialChildSize: minRatio,
      minChildSize: minRatio,
      maxChildSize: maxRatio,
      snap: true,
      snapSizes: [minRatio, maxRatio],
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

            if (_lastPresetSlug != activePresetSlug) {
              _lastPresetSlug = activePresetSlug;
              _archiveFetched = false;
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
              child: Container(
                decoration: BoxDecoration(
                  color: sheetColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        if (!sheetController.isAttached) return;
                        final delta = -details.delta.dy / screenHeight;
                        sheetController.jumpTo(
                          (sheetController.size + delta).clamp(
                            minRatio,
                            maxRatio,
                          ),
                        );
                      },
                      onVerticalDragEnd: (details) {
                        if (!sheetController.isAttached) return;
                        final mid = (minRatio + maxRatio) / 2;
                        final target = sheetController.size >= mid
                            ? maxRatio
                            : minRatio;
                        sheetController.animateTo(
                          target,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      child: _dragHandle(sheetController, minRatio),
                    ),
                    Expanded(
                      child: ClipRect(
                        child: Opacity(opacity: opacity, child: child),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
                child: _buildModeToggle(feedMode),
              ),
              Expanded(
                child: archiveAsync.when(
                  loading: () => CustomScrollView(
                    controller: scrollController,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverToBoxAdapter(child: _archiveHeader()),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, __) => const _ArchiveCardSkeleton(),
                            childCount: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  error: (e, _) => ListView(
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
                  ),
                  data: (items) {
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
                        slivers: _buildArchiveSlivers(sections),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
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

class _ArchiveCardSkeleton extends StatelessWidget {
  const _ArchiveCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
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
