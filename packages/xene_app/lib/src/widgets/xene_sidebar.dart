import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widget_previews.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xene_app/src/providers/articles_provider.dart';
import 'package:xene_app/src/providers/preset_provider.dart';
import 'package:xene_app/src/widgets/preset_dial.dart';

class XeneSidebar extends ConsumerStatefulWidget {
  const XeneSidebar({super.key});

  @override
  ConsumerState<XeneSidebar> createState() => _XeneSidebarState();
}

class _XeneSidebarState extends ConsumerState<XeneSidebar>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  Ticker? _crawlTicker;
  Duration _lastTickTime = Duration.zero;
  bool _isPaused = false;
  Orientation? _lastOrientation;
  bool _isLandscape = false;
  bool _needsScroll = false;

  // contentThreshold is the height of one content set
  double _getSetHeight(bool isLandscape) => isLandscape ? 740.0 : 700.0;
  static const double _contentThreshold = 600.0;
  static const double _crawlPixelsPerMillisecond = 0.043;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    final orientation = mediaQuery.orientation;

    if (_lastOrientation != orientation) {
      _isLandscape = orientation == Orientation.landscape;
      _lastTickTime = Duration.zero;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
    _lastOrientation = orientation;
  }

  void _startCrawl() {
    if (_crawlTicker?.isActive ?? false) return;

    _lastTickTime = Duration.zero;
    _crawlTicker ??= createTicker((elapsed) {
      if (!_isPaused && _needsScroll && _scrollController.hasClients) {
        final delta = _lastTickTime == Duration.zero
            ? Duration.zero
            : elapsed - _lastTickTime;
        _lastTickTime = elapsed;

        final pixels =
            delta.inMicroseconds / 1000.0 * _crawlPixelsPerMillisecond;
        final singleExtent = _getSetHeight(_isLandscape);
        final current = _scrollController.offset;

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
  }

  void _stopCrawl() {
    _crawlTicker?.stop();
    _lastTickTime = Duration.zero;
  }

  void _setPaused(bool paused) {
    if (_isPaused == paused) return;

    setState(() => _isPaused = paused);
    if (paused) {
      _lastTickTime = Duration.zero;
    } else {
      _startCrawl();
    }
  }

  @override
  void dispose() {
    _crawlTicker?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildContentSet(bool isLandscape) {
    final double baseLogoSize = isLandscape ? 220.0 : 200.0;
    final double logoNSize = baseLogoSize + 4.0;
    final double logoBoxHeight = isLandscape ? 220.0 : 160.0;
    // GAP ADJUSTMENT: Logo now sits higher to align with the Feed header
    final double topSetPadding = isLandscape ? 10.0 : 20.0;
    final double logoToDialGap = isLandscape ? 95.0 : 95.0;

    return SizedBox(
      height: _getSetHeight(isLandscape),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topSetPadding),
          // LOGO SECTION
          SizedBox(
            width: isLandscape ? 240 : 191,
            height: logoBoxHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'XE\n'),
                        TextSpan(
                          text: 'N',
                          style: GoogleFonts.jaro(fontSize: logoNSize),
                        ),
                        const TextSpan(text: 'E'),
                      ],
                    ),
                    textAlign: TextAlign.left,
                    style: GoogleFonts.jaro(
                      fontSize: baseLogoSize,
                      height: 0.68,
                      letterSpacing: -0.06 * 375,
                      color: Colors.black,
                    ),
                    softWrap: false,
                    overflow: TextOverflow.visible,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: logoToDialGap),

          _PresetDialDock(isLandscape: isLandscape),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (size.height < 150) return const SizedBox.shrink();

    final availableHeight = size.height - 56;
    final currentOrientation = MediaQuery.of(context).orientation;
    final isLandscape = currentOrientation == Orientation.landscape;
    final needsScroll = isLandscape || (availableHeight < _contentThreshold);
    _isLandscape = isLandscape;
    _needsScroll = needsScroll;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (needsScroll && _scrollController.hasClients) {
        _startCrawl();
      } else {
        _stopCrawl();
        if (_scrollController.hasClients && _scrollController.offset != 0) {
          _scrollController.jumpTo(0);
        }
      }
    });

    final width = size.width * 0.30;
    final clampedWidth = width.clamp(180.0, 210.0);

    return Container(
      width: clampedWidth,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: isLandscape
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: Listener(
                onPointerDown: (_) => _setPaused(true),
                onPointerUp: (_) => _setPaused(false),
                onPointerCancel: (_) => _setPaused(false),
                child: MouseRegion(
                  onEnter: (_) => _setPaused(true),
                  onExit: (_) => _setPaused(false),
                  child: ListView(
                    controller: _scrollController,
                    clipBehavior: Clip.hardEdge,
                    physics: needsScroll
                        ? const ClampingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: [
                      _buildContentSet(isLandscape),
                      if (needsScroll) _buildContentSet(isLandscape),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // PINNED BOTTOM SECTION
          _ArticlesDock(isLandscape: isLandscape),
          SizedBox(height: isLandscape ? 12 : 30),
        ],
      ),
    );
  }
}

class _ArticlesSlider extends StatefulWidget {
  const _ArticlesSlider({
    super.key,
    required this.isLandscape,
    required this.articles,
  });
  final bool isLandscape;
  final List<ArticleItem> articles;

  @override
  State<_ArticlesSlider> createState() => _ArticlesSliderState();
}

// Sidebar article carousel. The title/source/snippet text rendering for the
// pinned ARTICLES block is controlled in this widget.
class _ArticlesSliderState extends State<_ArticlesSlider> {
  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startTimer();
  }

  Future<void> _openArticle(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.articles.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || !_pageController.hasClients) return;
      _currentPage = (_currentPage + 1) % widget.articles.length;
      // try-catch: if the widget is deactivated mid-animation the scroll-end
      // notification can reach an inactive Material._InkFeatures element.
      // Swallowing here is safe — the next tick will succeed if still mounted.
      try {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Settle any in-flight animation synchronously before dispose so that
    // PageController.dispose() does not trigger ScrollEndNotification while
    // the Material ancestor's _InkFeatures element is already inactive.
    try {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentPage);
      }
    } catch (_) {}
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.isLandscape ? 96.0 : 210.0;
    final crossAxis = widget.isLandscape
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final textAlign =
        widget.isLandscape ? TextAlign.right : TextAlign.left;

    return SizedBox(
      height: height,
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.articles.length,
        itemBuilder: (context, index) {
          final article = widget.articles[index];
          return MouseRegion(
            cursor: article.url.isNotEmpty
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            child: GestureDetector(
              onTap: () => _openArticle(article.url),
              child: Column(
                crossAxisAlignment: crossAxis,
                children: [
                  Text(
                    article.title,
                    textAlign: textAlign,
                    style: GoogleFonts.teko(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      height: 1.05,
                    ),
                    maxLines: widget.isLandscape ? 2 : null,
                    overflow: widget.isLandscape
                        ? TextOverflow.ellipsis
                        : TextOverflow.visible,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    article.snippet,
                    textAlign: textAlign,
                    style: GoogleFonts.archivo(
                      fontSize: 12,
                      color: const Color(0xFF444444),
                    ),
                    maxLines: widget.isLandscape ? 2 : 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/*
class _JumpingChevron extends StatefulWidget {
  const _JumpingChevron();
  @override
  State<_JumpingChevron> createState() => _JumpingChevronState();
}

class _JumpingChevronState extends State<_JumpingChevron> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _leadAnim;
  late Animation<double> _trail1Anim;
  late Animation<double> _trail2Anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
    
    // Define the single 'Jump' sequence
    final jumpSequence = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -12.0).chain(CurveTween(curve: Curves.easeOutCubic)), 
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -12.0, end: 0.0).chain(CurveTween(curve: Curves.easeInCubic)), 
        weight: 50,
      ),
    ]);

    // Create staggered animations using Intervals
    _leadAnim = jumpSequence.animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.1, curve: Curves.linear)),
    );
    _trail1Anim = jumpSequence.animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.02, 0.12, curve: Curves.linear)),
    );
    _trail2Anim = jumpSequence.animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.04, 0.14, curve: Curves.linear)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: 32,
          height: 20,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Furthest Trail (Last to move, lowest opacity)
              Transform.translate(
                offset: Offset(0, _trail2Anim.value),
                child: Opacity(
                  opacity: (_trail2Anim.value / -12.0).abs().clamp(0.0, 0.15),
                  child: const _ChevronShape(),
                ),
              ),
              // 2. Middle Trail (Medium delay)
              Transform.translate(
                offset: Offset(0, _trail1Anim.value),
                child: Opacity(
                  opacity: (_trail1Anim.value / -12.0).abs().clamp(0.0, 0.3),
                  child: const _ChevronShape(),
                ),
              ),
              // 3. Lead Chevron (First to move)
              Transform.translate(
                offset: Offset(0, _leadAnim.value),
                child: const _ChevronShape(),
              ),
            ],
          ),
        );
      }
    );
  }
}

/// Extracted shape to avoid duplication
class _ChevronShape extends StatelessWidget {
  const _ChevronShape();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(32, 20),
      painter: _ChevronPainter(),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.square;
    final path = Path();
    path.moveTo(4, 16);
    path.lineTo(size.width / 2, 4);
    path.lineTo(size.width - 4, 16);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
*/

@Preview(name: 'Sidebar - Default')
Widget previewXeneSidebar() {
  return const ProviderScope(child: Material(child: XeneSidebar()));
}

class _ArticlesDock extends ConsumerWidget {
  const _ArticlesDock({required this.isLandscape});

  final bool isLandscape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articlesAsync = ref.watch(presetArticlesProvider);
    final slug = ref.watch(activePresetSlugProvider);

    return Align(
      alignment: isLandscape ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isLandscape
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            'ARTICLES',
            textAlign: isLandscape ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              fontFamily: 'Teko',
              fontSize: 12,
              color: Color(0xFF666666),
              letterSpacing: 1.44,
              height: 1.66,
            ),
          ),
          const SizedBox(height: 4),
          articlesAsync.when(
            data: (articles) {
              if (articles.isEmpty) {
                return const SizedBox(
                  height: 60,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No articles yet',
                      style: TextStyle(
                        fontFamily: 'Archivo',
                        fontSize: 11,
                        color: Color(0xFFAAAAAA),
                      ),
                    ),
                  ),
                );
              }
              return _ArticlesSlider(
                key: ValueKey(slug),
                isLandscape: isLandscape,
                articles: articles,
              );
            },
            loading: () => SizedBox(
              height: isLandscape ? 96.0 : 260.0,
              child: const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Color(0xFFBBBBBB),
                  ),
                ),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _PresetDialDock extends ConsumerWidget {
  const _PresetDialDock({required this.isLandscape});

  final bool isLandscape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dialAsync = ref.watch(presetDialProvider);

    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: SizedBox(
          width: 150,
          height: 160,
          child: dialAsync.when(
            data: (state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'PRESETS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Teko',
                      fontSize: 12,
                      color: Color(0xFF666666),
                      letterSpacing: 1.44,
                      height: 1.66,
                    ),
                  ),
                  const SizedBox(
                    height: 2,
                  ), // GAP ADJUSTMENT: Reduced gap between label and dial for better balance
                  PresetDial(
                    slots: state.slots,
                    activeSlug: state.activePresetSlug,
                    onChanged: (slot) {
                      ref
                          .read(presetDialProvider.notifier)
                          .selectPreset(slot.slug);
                    },
                  ),
                ],
              );
            },
            loading: () => const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
