import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:xene_domain/xene_domain.dart';

import '../providers/feed_provider.dart';
import '../providers/preset_provider.dart';
import '../widgets/xene_feed_card.dart';
import '../widgets/xene_content_modal.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen>
    with TickerProviderStateMixin {
  late ScrollController _scrollController;
  Ticker? _crawlTicker;
  Duration _lastTickTime = Duration.zero;
  bool _isPaused = false;
  Timer? _resumeTimer;
  int _crawlCopyCount = 2;
  double _feedOpacity = 1.0;
  bool _isPresetTransition = false;

  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _searchActive = false;
  Timer? _transitionTimeoutTimer;
  bool _transitionRetried = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      final q = value.trim().isEmpty ? null : value.trim();
      ref.read(searchQueryProvider.notifier).state = q;
    });
  }

  void _activateSearch() {
    _crawlTicker?.dispose();
    _crawlTicker = null;
    setState(() => _searchActive = true);
  }

  void _clearSearch() {
    _searchController.clear();
    _searchDebounce?.cancel();
    ref.read(searchQueryProvider.notifier).state = null;
    setState(() => _searchActive = false);
    // Crawl will restart when filteredFeedProvider next emits via ref.listen.
  }

  // ------------------------------------------------------------
  // AUTO-SCROLL TICKER (correct wrap logic)
  // ------------------------------------------------------------
  void _startCrawl() {
    _crawlTicker?.dispose();
    _crawlTicker = null;
    _lastTickTime = Duration.zero;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) {
        // CustomScrollView detached during loading state — retry next frame.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted && _crawlTicker == null) _startCrawl();
        });
        return;
      }

      final maxScroll = _scrollController.position.maxScrollExtent;
      final viewport = _scrollController.position.viewportDimension;
      final contentExtent = maxScroll + viewport - 100;
      final singleExtent = contentExtent / _crawlCopyCount;

      debugPrint(
        '[FeedScreen] startCrawl maxScroll=$maxScroll viewport=$viewport '
        'singleExtent=${singleExtent.toStringAsFixed(1)} copyCount=$_crawlCopyCount',
      );

      if (maxScroll <= 0) return;

      // singleExtent must be >= viewport for the wrap to be seamless.
      // If not (too few items in this phase), abort and let BC items arrive —
      // the ref.listen on filteredFeedProvider will retry with more content.
      if (singleExtent < viewport) {
        debugPrint(
          '[FeedScreen] startCrawl ABORTED — singleExtent=${singleExtent.toStringAsFixed(1)} '
          '< viewport=$viewport (not enough content for seamless loop, waiting for more items)',
        );
        return;
      }

      _crawlTicker = createTicker((elapsed) {
        if (!_isPaused && _scrollController.hasClients) {
          final delta = _lastTickTime == Duration.zero
              ? Duration.zero
              : elapsed - _lastTickTime;
          _lastTickTime = elapsed;

          final pixels = delta.inMicroseconds / 1000.0 * 0.043;

          final position = _scrollController.position;
          final maxScroll = position.maxScrollExtent;
          final viewport = position.viewportDimension;
          final current = position.pixels;

          if (maxScroll <= 0) return;

          final contentExtent = maxScroll + viewport - 100;
          final singleExtent = contentExtent / _crawlCopyCount;

          double next = current + pixels;
          if (singleExtent > 0 && next >= singleExtent) {
            next -= singleExtent;
          }

          _scrollController.jumpTo(next);
        } else {
          _lastTickTime = elapsed;
        }
      });

      _crawlTicker!.start();
    });
  }

  void _pauseCrawl() {
    if (!_isPaused) setState(() => _isPaused = true);
    _resumeTimer?.cancel();
  }

  void _resumeCrawl() {
    if (_searchActive) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _isPaused = false);
    });
  }

  @override
  void dispose() {
    _crawlTicker?.dispose();
    _resumeTimer?.cancel();
    _transitionTimeoutTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------
  // BUILD DATE-GROUPED LIST BEFORE DUPLICATION
  // ------------------------------------------------------------
  DateTime _localDate(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  List<_FeedDateSection> _buildDateSections(List<FeedItem> items) {
    final sorted = List<FeedItem>.from(items)
      ..sort((a, b) {
        final byDate = b.publishedAt.compareTo(a.publishedAt);
        if (byDate != 0) return byDate;

        final byArtist = a.artistName.compareTo(b.artistName);
        if (byArtist != 0) return byArtist;

        return a.id.compareTo(b.id);
      });

    final sections = <_FeedDateSection>[];
    _FeedDateSection? currentSection;

    for (final item in sorted) {
      final date = _localDate(item.publishedAt);

      if (currentSection == null || currentSection.date != date) {
        currentSection = _FeedDateSection(date: date, items: <FeedItem>[]);
        sections.add(currentSection);
      }

      currentSection.items.add(item);
    }

    return sections;
  }

  _FeedCrawlLoop _duplicateSectionsForCrawl(
    List<_FeedDateSection> sections,
    double viewportHeight,
  ) {
    if (sections.isEmpty) {
      return _FeedCrawlLoop(sections: sections, copyCount: 1);
    }

    const minHeight = 2000.0;
    const estimatedItemHeight = 92.0;
    const estimatedHeaderHeight = 32.0;

    final singleCycleHeight = sections.fold<double>(
      0,
      (sum, section) =>
          sum +
          estimatedHeaderHeight +
          section.items.length * estimatedItemHeight,
    );

    final minCycleHeight = viewportHeight + 240.0;
    var cycleCopyCount = 1;
    while (singleCycleHeight * cycleCopyCount < minCycleHeight) {
      cycleCopyCount++;
    }

    const loopCopyCount = 2;
    while (singleCycleHeight * cycleCopyCount * loopCopyCount < minHeight) {
      cycleCopyCount++;
    }

    final duplicated = <_FeedDateSection>[];
    for (var loopIndex = 0; loopIndex < loopCopyCount; loopIndex++) {
      for (var cycleIndex = 0; cycleIndex < cycleCopyCount; cycleIndex++) {
        duplicated.addAll(sections);
      }
    }

    return _FeedCrawlLoop(sections: duplicated, copyCount: loopCopyCount);
  }

  // Pre-computes composite-id → stagger-index for items that should animate.
  // Built from the ORIGINAL (non-duplicated) sections so all infinite-scroll
  // copies of the same item share the same stagger timing.
  Map<String, int> _buildAnimIndexMap(
    List<_FeedDateSection> sections,
    Set<String> newItemIds,
  ) {
    final result = <String, int>{};
    var count = 0;
    for (final section in sections) {
      for (final item in section.items) {
        final id = '${item.platform}_${item.id}';
        if (newItemIds.contains(id)) {
          result[id] = count++;
        }
      }
    }
    debugPrint(
      '[FeedScreen] _buildAnimIndexMap — '
      '${result.length} new items mapped for animation',
    );
    return result;
  }

  List<Widget> _buildFeedSlivers(
    List<_FeedDateSection> sections,
    Set<String> newItemIds,
    Map<String, int> animIndexMap,
  ) {
    final slivers = <Widget>[];

    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      slivers.add(
        SliverMainAxisGroup(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _DateHeaderDelegate(
                child: _DateDivider(date: section.date),
                backgroundColor: Colors.white,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, itemIndex) {
                final item = section.items[itemIndex];
                final compositeId = '${item.platform}_${item.id}';
                final animIndex = animIndexMap[compositeId] ?? -1;
                return _AnimatingFeedCard(
                  key: ValueKey(
                    'feed_card_${sectionIndex}_${itemIndex}_${item.id}',
                  ),
                  item: item,
                  onTap: () => showXeneContent(context, item),
                  animIndex: animIndex,
                );
              }, childCount: section.items.length),
            ),
          ],
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 100)));
    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(searchQueryProvider);
    final isSearching = searchQuery != null;
    final feedAsync = isSearching
        ? ref.watch(searchFeedProvider).whenData((items) => items)
        : ref.watch(filteredFeedProvider);
    final currentPlatform = ref.watch(platformFilterProvider);
    final currentArtist = ref.watch(artistFilterProvider);
    final availableArtists = ref.watch(feedArtistsProvider);
    final newItemIds = ref.watch(newFeedItemIdsProvider);

    // Fade out cards and reset crawl when preset changes.
    ref.listen(activePresetSlugProvider, (prev, next) {
      if (prev != null && prev != next) {
        _crawlTicker?.dispose();
        _crawlTicker = null;
        _transitionRetried = false;
        // Cancel any previous fallback timer from the last transition.
        _transitionTimeoutTimer?.cancel();
        // Fallback: always end the transition after 6 seconds even if feed
        // never returns non-empty data (e.g. preset genuinely has no content).
        _transitionTimeoutTimer = Timer(const Duration(seconds: 6), () {
          if (mounted && _isPresetTransition) {
            debugPrint('[FeedScreen] Transition timeout — revealing feed (may be empty)');
            setState(() {
              _feedOpacity = 1.0;
              _isPresetTransition = false;
            });
          }
        });
        setState(() {
          _feedOpacity = 0.0;
          _isPresetTransition = true;
        });
      }
    });

    // Fade cards back in once new data arrives after a preset switch,
    // and (re)start the autoscroll crawler whenever data settles.
    ref.listen(filteredFeedProvider, (prev, next) {
      if (_isPresetTransition && next.hasValue && !next.isLoading) {
        if (next.value?.isNotEmpty ?? false) {
          // Real items arrived — end the transition cleanly.
          _transitionTimeoutTimer?.cancel();
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted)
              setState(() {
                _feedOpacity = 1.0;
                _isPresetTransition = false;
              });
          });
        } else if (!_transitionRetried) {
          // Empty response during transition — could be a stale/race response.
          // Fire one automatic retry so the backend has a second chance to serve
          // real cached data before we give up and show "Empty feed".
          _transitionRetried = true;
          debugPrint('[FeedScreen] Empty feed during preset transition — scheduling retry');
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted && _isPresetTransition) {
              debugPrint('[FeedScreen] Retrying feed fetch after empty transition response');
              ref.read(feedProvider.notifier).refresh();
            }
          });
        }
      }
      // Start crawl on initial data arrival and after preset changes settle.
      // Check _crawlTicker inside the callback (not here) to get the freshest state.
      if (next.hasValue && (next.value?.isNotEmpty ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _crawlTicker == null) _startCrawl();
        });
      }
    });

    final size = MediaQuery.of(context).size;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (size.height < 150) return const SizedBox.shrink();

    return Column(
      children: [
        // ------------------------------------------------------------
        // HEADER
        // ------------------------------------------------------------
        SizedBox(
          height: isLandscape ? 100 : 60,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: isLandscape ? -10 : -20,
                left: 0,
                right: 16,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final fontSize = (constraints.maxWidth * 0.16).clamp(
                      24.0,
                      52.0,
                    );

                    return Transform(
                      transform: Matrix4.diagonal3Values(1.0, 2.0, 1.0),
                      alignment: Alignment.topRight,
                      child: Text(
                        'JUST DROPPED',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: GoogleFonts.teko(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // ------------------------------------------------------------
        // CONTROL BAR
        // ------------------------------------------------------------
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 1,
                child: Text(
                  isSearching ? 'SEARCH' : '\u2264 7 DAYS',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.teko(
                    fontSize: 18,
                    color: isSearching
                        ? const Color(0xFFFF5500)
                        : const Color(0xFF888888),
                  ),
                ),
              ),
              Flexible(
                flex: 2,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _searchActive
                      ? Row(
                          key: const ValueKey('search'),
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                autofocus: true,
                                onChanged: _onSearchChanged,
                                style: GoogleFonts.teko(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'SEARCH...',
                                  hintStyle: GoogleFonts.teko(
                                    fontSize: 16,
                                    color: const Color(0xFF555555),
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _clearSearch,
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Color(0xFF888888),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          key: const ValueKey('filters'),
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value.startsWith('p:')) {
                                  final platform = value == 'p:all'
                                      ? null
                                      : value.substring(2);
                                  ref
                                      .read(platformFilterProvider.notifier)
                                      .state = platform;
                                } else if (value.startsWith('a:')) {
                                  final artist = value == 'a:all'
                                      ? null
                                      : value.substring(2);
                                  ref
                                      .read(artistFilterProvider.notifier)
                                      .state = artist;
                                }
                              },
                              offset: const Offset(0, 30),
                              child: Text(
                                'FILTER BY -',
                                style: GoogleFonts.teko(
                                  fontSize: 18,
                                  color: (currentPlatform != null ||
                                          currentArtist != null)
                                      ? const Color(0xFFFF5500)
                                      : const Color(0xFF888888),
                                ),
                              ),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  enabled: false,
                                  child: Text(
                                    'PLATFORM',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'p:all',
                                  child: Text('ALL PLATFORMS'),
                                ),
                                const PopupMenuItem(
                                  value: 'p:soundcloud',
                                  child: Text('SOUNDCLOUD'),
                                ),
                                const PopupMenuItem(
                                  value: 'p:bandcamp',
                                  child: Text('BANDCAMP'),
                                ),
                                const PopupMenuItem(
                                  value: 'p:youtube',
                                  child: Text('YOUTUBE'),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  enabled: false,
                                  child: Text(
                                    'ARTIST',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'a:all',
                                  child: Text('ALL ARTISTS'),
                                ),
                                ...availableArtists.map(
                                  (name) => PopupMenuItem(
                                    value: 'a:$name',
                                    child: Text(name.toUpperCase()),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _activateSearch,
                              child: const Icon(
                                Icons.search,
                                size: 18,
                                color: Color(0xFF888888),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),

        // ------------------------------------------------------------
        // FEED (with preset-switch crossfade)
        // ------------------------------------------------------------
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cards — fades out during preset transition.
              AnimatedOpacity(
                opacity: _feedOpacity,
                duration: const Duration(milliseconds: 350),
                child: feedAsync.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return Center(
                        child: Text(
                          isSearching ? 'No results' : 'Empty feed',
                          style: GoogleFonts.teko(
                            fontSize: 18,
                            color: const Color(0xFF555555),
                          ),
                        ),
                      );
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final sections = _buildDateSections(items);
                        // Skip infinite-scroll duplication during search —
                        // results are a finite flat list, not a looping crawl.
                        final loop = isSearching
                            ? _FeedCrawlLoop(sections: sections, copyCount: 1)
                            : _duplicateSectionsForCrawl(
                                sections,
                                constraints.maxHeight,
                              );
                        _crawlCopyCount = loop.copyCount;
                        // Compute animIndex from original sections (not duplicated)
                        // so duplicate copies of the same item share the same
                        // stagger timing.
                        final animIndexMap = newItemIds.isNotEmpty
                            ? _buildAnimIndexMap(sections, newItemIds)
                            : const <String, int>{};

                        return Listener(
                          onPointerDown: (_) => _pauseCrawl(),
                          onPointerUp: (_) => _resumeCrawl(),
                          child: CustomScrollView(
                            controller: _scrollController,
                            physics: const ClampingScrollPhysics(),
                            slivers: _buildFeedSlivers(
                              loop.sections,
                              newItemIds,
                              animIndexMap,
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const SizedBox.expand(),
                  error: (err, stack) => Center(child: Text('Error: $err')),
                ),
              ),

              // CardsLoading Lottie — fades in during preset transition.
              IgnorePointer(
                ignoring: _feedOpacity > 0.1,
                child: AnimatedOpacity(
                  opacity: (1.0 - _feedOpacity).clamp(0.0, 1.0),
                  duration: const Duration(milliseconds: 350),
                  child: Center(
                    child: _isPresetTransition
                        ? Lottie.asset(
                            'assets/animations/CardsLoading.json',
                            width: 140,
                            height: 140,
                            repeat: true,
                            fit: BoxFit.contain,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Wraps XeneFeedCard with a SizeTransition + FadeTransition on first build
// when the item's composite ID is in newFeedItemIdsProvider.
// animIndex drives the stagger delay (index * 50ms); -1 = no animation.
class _AnimatingFeedCard extends ConsumerStatefulWidget {
  const _AnimatingFeedCard({
    required super.key,
    required this.item,
    required this.onTap,
    required this.animIndex,
  });

  final FeedItem item;
  final VoidCallback onTap;
  final int animIndex;

  @override
  ConsumerState<_AnimatingFeedCard> createState() => _AnimatingFeedCardState();
}

class _AnimatingFeedCardState extends ConsumerState<_AnimatingFeedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _size;
  late final Animation<double> _opacity;
  bool _shouldAnimate = false;
  bool _isTreeActive = true;

  bool get _canUpdateProvider => mounted && _isTreeActive;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _size = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

    final compositeId = '${widget.item.platform}_${widget.item.id}';
    final newIds = ref.read(newFeedItemIdsProvider);
    _shouldAnimate = widget.animIndex >= 0 && newIds.contains(compositeId);

    if (_shouldAnimate) {
      debugPrint(
        '[AnimatingFeedCard] ${widget.item.platform}/${widget.item.artistName} '
        'ANIMATING (animIndex=${widget.animIndex} delay=${widget.animIndex * 50}ms)',
      );
      final delay = Duration(milliseconds: widget.animIndex * 50);
      Future.delayed(delay, () {
        if (!_canUpdateProvider) return;
        _ctrl.forward().then((_) {
          if (!_canUpdateProvider) return;
          debugPrint(
            '[AnimatingFeedCard] Animation complete for '
            '${widget.item.platform}/${widget.item.artistName} — removing from newIds',
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_canUpdateProvider) return;
            ref
                .read(newFeedItemIdsProvider.notifier)
                .update((s) => {...s}..remove(compositeId));
          });
        });
      });
    } else {
      if (widget.animIndex >= 0 && !newIds.contains(compositeId)) {
        debugPrint(
          '[AnimatingFeedCard] WARNING: animIndex=${widget.animIndex} set but '
          '$compositeId not in newFeedItemIds — animation skipped',
        );
      }
      _ctrl.value = 1.0;
    }
  }

  @override
  void activate() {
    super.activate();
    _isTreeActive = true;
  }

  @override
  void deactivate() {
    _isTreeActive = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldAnimate) {
      return XeneFeedCard(item: widget.item, onTap: widget.onTap);
    }
    return SizeTransition(
      sizeFactor: _size,
      axisAlignment: -1.0,
      child: FadeTransition(
        opacity: _opacity,
        child: XeneFeedCard(item: widget.item, onTap: widget.onTap),
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const Expanded(
            child: Divider(color: Color(0xFFF5F5F5), thickness: 1),
          ),
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
          const Expanded(
            child: Divider(color: Color(0xFFF5F5F5), thickness: 1),
          ),
        ],
      ),
    );
  }
}

class _FeedDateSection {
  _FeedDateSection({required this.date, required this.items});

  final DateTime date;
  final List<FeedItem> items;
}

class _FeedCrawlLoop {
  const _FeedCrawlLoop({required this.sections, required this.copyCount});

  final List<_FeedDateSection> sections;
  final int copyCount;
}

class _DateHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DateHeaderDelegate({
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
  bool shouldRebuild(covariant _DateHeaderDelegate oldDelegate) {
    return child != oldDelegate.child ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
