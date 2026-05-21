import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widget_previews.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xene_app/src/layout/xene_layout_metrics.dart';
import 'package:xene_app/src/layout/xene_responsive_debug.dart';
import 'package:xene_app/src/providers/articles_provider.dart';
import 'package:xene_app/src/providers/auth_provider.dart';
import 'package:xene_app/src/providers/preset_provider.dart';
import 'package:xene_app/src/widgets/auth_gate_sheet.dart';
import 'package:xene_app/src/widgets/preset_dial.dart';

// PROTECTED UI SURFACE - DO NOT REFACTOR CASUALLY.
//
// This sidebar, its preset dial placement, and the articles dock/reveal timing
// have been hand-tuned after repeated regressions involving clipping, jumping,
// misplaced articles, and dial-label flicker. Any coding agent or developer
// must leave this file's sidebar/dial/articles behavior untouched unless the
// user explicitly asks for changes to this exact surface.
//
// SIDEBAR INVARIANTS:
// - Do not change the authored XENE logo sizing, box dimensions, tracking, left
//   alignment, line rhythm, or sidebar width clamp during responsive refactors.
//   The logo lockup is intentional brand spacing, not layout debt.
// - Do not enable sidebar auto-crawl in portrait. Portrait should remain still
//   unless the product/design direction is explicitly changed.
// - Do not move the authored ARTICLES dock placement or replace its fixed
//   carousel heights with generic responsive metrics unless the visual design
//   is explicitly revised.
const double _xeneLogoLetterSpacing = -0.06 * 375;
const double _articlesSliderHeightLandscape = 96.0;
const double _articlesSliderHeightPortrait = 210.0;
const double _articlesSliderHeightCompactPortrait = 28.0;
const double _articlesHeaderHeight = 24.0;
const double _articlesBottomGapLandscape = 12.0;
const double _articlesBottomGapPortrait = 30.0;
const double _articlesBottomGapCompactPortrait = 18.0;
const double _presetArticleMinGap = 16.0;
const double _presetDockLabelAndGapHeight = 24.0;
const double _sidebarAutoCrawlMaxHeight = 540.0;

class XeneSidebar extends ConsumerStatefulWidget {
  const XeneSidebar({super.key, this.metrics});

  final XeneLayoutMetrics? metrics;

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
  bool _needsScroll = false;
  double _contentCycleHeight = 700.0;
  bool _isDialOverlayActive = false;

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
        final singleExtent = _contentCycleHeight;
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

  void _setDialOverlayActive(bool active) {
    if (_isDialOverlayActive == active) return;
    setState(() => _isDialOverlayActive = active);
  }

  @override
  void dispose() {
    _crawlTicker?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildContentSet({
    required bool isLandscape,
    required bool compactPortrait,
    required XeneLayoutMetrics? layoutMetrics,
    required double contentCycleHeight,
    required bool alignRight,
  }) {
    // Authored XENE logo lockup geometry. Keep these fixed unless the visual
    // identity is deliberately redesigned; the custom tracking depends on them.
    final double baseLogoSize = isLandscape ? 220.0 : 200.0;
    final double logoNSize = baseLogoSize + 4.0;
    final double logoBoxHeight = isLandscape ? 220.0 : 160.0;
    final double topSetPadding = isLandscape ? 10.0 : 20.0;
    final double logoToDialGap = 95.0;
    final double logoWidth = isLandscape ? 240.0 : 191.0;

    XeneResponsiveDebug.values('Sidebar.contentSet', {
      'contentCycleHeight': contentCycleHeight,
      'baseLogoSize': baseLogoSize,
      'logoBoxHeight': logoBoxHeight,
      'logoToDialGap': logoToDialGap,
      'alignRight': alignRight,
      'compactPortrait': compactPortrait,
    });

    return SizedBox(
      height: contentCycleHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topSetPadding),
          // Authored XENE logo lockup. Do not change text alignment, tracking,
          // or line rhythm as part of responsive/layout cleanup.
          SizedBox(
            width: logoWidth,
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
                      letterSpacing: _xeneLogoLetterSpacing,
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

          _PresetDialDock(
            isLandscape: isLandscape,
            metrics: layoutMetrics,
            onOverlayChanged: _setDialOverlayActive,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layoutMetrics = widget.metrics ?? XeneLayoutScope.maybeOf(context);
    if (layoutMetrics != null) {
      XeneResponsiveDebug.values('Sidebar.receivedMetrics', {
        'sidebarWidth': layoutMetrics.sidebarWidth,
        'dialKnobSize': layoutMetrics.dialKnobSize,
        'dialReservedHeight': layoutMetrics.dialReservedHeight,
        'textScaleFactor': layoutMetrics.textScaleFactor,
      });
    }

    final size = MediaQuery.of(context).size;
    if (size.height < 150) return const SizedBox.shrink();

    final currentOrientation = MediaQuery.of(context).orientation;
    final isLandscape = currentOrientation == Orientation.landscape;
    final alignRight = isLandscape && size.width > size.height;
    // Authored sidebar width clamp. Do not narrow this from responsive metrics:
    // the XENE logo lockup depends on this minimum horizontal room.
    final sidebarWidth = (size.width * 0.30).clamp(180.0, 210.0);
    final sidebarPadding = layoutMetrics?.sidebarPadding ?? 12.0;

    return Container(
      width: sidebarWidth,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
      ),
      padding: EdgeInsets.symmetric(horizontal: sidebarPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          final topSetPadding = isLandscape ? 10.0 : 20.0;
          final logoBoxHeight = isLandscape ? 220.0 : 160.0;
          final normalLogoToDialGap = isLandscape ? 95.0 : 95.0;
          final hintedDialReservedHeight =
              layoutMetrics?.dialReservedHeight ?? 166.0;
          final estimatedPresetLabelBottom =
              topSetPadding +
              logoBoxHeight +
              normalLogoToDialGap +
              _presetDockLabelAndGapHeight +
              hintedDialReservedHeight;
          final normalArticleReserve =
              (isLandscape
                  ? _articlesSliderHeightLandscape
                  : _articlesSliderHeightPortrait) +
              (isLandscape
                  ? _articlesBottomGapLandscape
                  : _articlesBottomGapPortrait);
          final normalArticleTop = availableHeight - normalArticleReserve;
          final compactPortrait =
              !isLandscape &&
              normalArticleTop <
                  estimatedPresetLabelBottom + _presetArticleMinGap;
          final articleSliderHeight = isLandscape
              ? _articlesSliderHeightLandscape
              : compactPortrait
              ? _articlesSliderHeightCompactPortrait
              : _articlesSliderHeightPortrait;
          final articleBottomGap = isLandscape
              ? _articlesBottomGapLandscape
              : compactPortrait
              ? _articlesBottomGapCompactPortrait
              : _articlesBottomGapPortrait;
          final bottomReserve = articleSliderHeight + articleBottomGap;
          final scrollViewportHeight = (availableHeight - bottomReserve).clamp(
            0.0,
            double.infinity,
          );
          const presetLabelReserve = 28.0;
          // Authored sidebar cycle height. Keep this independent from shared
          // metrics so global density changes cannot move the logo/articles.
          final contentCycleHeight = isLandscape ? 740.0 : 700.0;
          final measuredContentCycleHeight =
              contentCycleHeight + presetLabelReserve;
          // Portrait mode is intentionally static. Auto-crawl is allowed only
          // for genuinely short landscape sidebars where the authored content
          // cannot fit vertically. Wide desktop/tablet windows must stay still.
          final needsScroll =
              isLandscape &&
              availableHeight <= _sidebarAutoCrawlMaxHeight &&
              availableHeight < measuredContentCycleHeight;

          _needsScroll = needsScroll;
          _contentCycleHeight = measuredContentCycleHeight;

          XeneResponsiveDebug.constraints('Sidebar.inner', constraints);
          XeneResponsiveDebug.values('Sidebar.layout', {
            'sidebarWidth': sidebarWidth,
            'sidebarPadding': sidebarPadding,
            'availableHeight': availableHeight,
            'bottomReserve': bottomReserve,
            'scrollViewportHeight': scrollViewportHeight,
            'contentCycleHeight': measuredContentCycleHeight,
            'needsScroll': needsScroll,
            'autoCrawlMaxHeight': _sidebarAutoCrawlMaxHeight,
            'alignRight': alignRight,
            'compactPortrait': compactPortrait,
            'estimatedPresetLabelBottom': estimatedPresetLabelBottom,
            'normalArticleTop': normalArticleTop,
            'presetArticleMinGap': _presetArticleMinGap,
          });

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            if (needsScroll && _scrollController.hasClients) {
              _startCrawl();
            } else {
              _stopCrawl();
              if (_scrollController.hasClients &&
                  _scrollController.offset != 0) {
                _scrollController.jumpTo(0);
              }
            }
          });

          return Column(
            crossAxisAlignment: alignRight
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
                          _buildContentSet(
                            isLandscape: isLandscape,
                            compactPortrait: compactPortrait,
                            layoutMetrics: layoutMetrics,
                            contentCycleHeight: measuredContentCycleHeight,
                            alignRight: alignRight,
                          ),
                          if (needsScroll)
                            _buildContentSet(
                              isLandscape: isLandscape,
                              compactPortrait: compactPortrait,
                              layoutMetrics: layoutMetrics,
                              contentCycleHeight: measuredContentCycleHeight,
                              alignRight: alignRight,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // PINNED BOTTOM SECTION
              AnimatedOpacity(
                opacity: _isDialOverlayActive ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: _isDialOverlayActive,
                  child: _ArticlesDock(
                    isLandscape: isLandscape,
                    alignRight: alignRight,
                    compactPortrait: compactPortrait,
                  ),
                ),
              ),
              SizedBox(height: articleBottomGap),
            ],
          );
        },
      ),
    );
  }
}

class _ArticlesSlider extends StatefulWidget {
  const _ArticlesSlider({
    required this.isLandscape,
    required this.alignRight,
    required this.compactPortrait,
    required this.articles,
  });
  final bool isLandscape;
  final bool alignRight;
  final bool compactPortrait;
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
    final crossAxis = widget.alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final textAlign = widget.alignRight ? TextAlign.right : TextAlign.left;
    final height = widget.isLandscape
        ? _articlesSliderHeightLandscape
        : widget.compactPortrait
        ? _articlesSliderHeightCompactPortrait
        : _articlesSliderHeightPortrait;

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
                    maxLines: widget.compactPortrait
                        ? 1
                        : widget.isLandscape
                        ? 2
                        : 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!widget.compactPortrait) ...[
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DelayedTopFadeIn extends StatefulWidget {
  const _DelayedTopFadeIn({
    super.key,
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  State<_DelayedTopFadeIn> createState() => _DelayedTopFadeInState();
}

// Articles reveal invariant: loading/error/data must reserve the same dock
// height, and the title must be inside this delayed reveal. Otherwise the
// ARTICLES header or carousel flashes/jumps before the fade begins.
class _DelayedTopFadeInState extends State<_DelayedTopFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _delayTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        child: SizedBox(height: widget.height, child: widget.child),
        builder: (context, child) {
          final reveal = Curves.easeOutCubic.transform(_controller.value);
          final opacity = Curves.easeOut.transform(_controller.value);
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: reveal,
              child: Opacity(opacity: opacity, child: child),
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
  const _ArticlesDock({
    required this.isLandscape,
    required this.alignRight,
    required this.compactPortrait,
  });

  final bool isLandscape;
  final bool alignRight;
  final bool compactPortrait;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articlesAsync = ref.watch(presetArticlesProvider);
    final slug = ref.watch(activePresetSlugProvider);
    final sliderHeight = isLandscape
        ? _articlesSliderHeightLandscape
        : compactPortrait
        ? _articlesSliderHeightCompactPortrait
        : _articlesSliderHeightPortrait;

    XeneResponsiveDebug.values('ArticlesDock.geometry', {
      'isLandscape': isLandscape,
      'alignRight': alignRight,
      'sliderHeight': sliderHeight,
      'bottomGap': isLandscape
          ? _articlesBottomGapLandscape
          : _articlesBottomGapPortrait,
    });

    // Keep this height identical for loading, error, empty, and data states.
    final dockHeight = _articlesHeaderHeight + sliderHeight;

    Widget buildContent(Widget body) {
      return Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: alignRight
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              'ARTICLES',
              textAlign: alignRight ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontFamily: 'Teko',
                fontSize: 12,
                color: Color(0xFF666666),
                letterSpacing: 1.44,
                height: 1.66,
              ),
            ),
            const SizedBox(height: 4),
            body,
          ],
        ),
      );
    }

    // Auth gate: anonymous users see a sign-in prompt on the custom preset.
    // All other presets (genre-based) are public and unaffected.
    final isAnon = ref.watch(isAnonymousProvider);
    if (isAnon && slug == 'custom') {
      return _DelayedTopFadeIn(
        key: const ValueKey('articles-auth-gate'),
        height: dockHeight,
        child: buildContent(
          SizedBox(
            height: sliderHeight,
            child: Align(
              alignment: alignRight
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => showAuthGate(
                  // _ArticlesDock is a ConsumerWidget so context is available
                  // via the surrounding build scope — safe to call here.
                  // ignore: use_build_context_synchronously
                  context,
                  featureHint: 'to access editorial picks, curated fresh daily',
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: alignRight
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOG IN OR CREATE AN ACCOUNT',
                      textAlign: alignRight ? TextAlign.right : TextAlign.left,
                      style: const TextStyle(
                        fontFamily: 'Teko',
                        fontSize: 11,
                        color: Color(0xFFFF5500),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'editorial picks, curated fresh daily',
                      textAlign: alignRight ? TextAlign.right : TextAlign.left,
                      style: const TextStyle(
                        fontFamily: 'Archivo',
                        fontSize: 10,
                        color: Color(0xFFAAAAAA),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return articlesAsync.when(
      data: (articles) {
        final body = articles.isEmpty
            ? SizedBox(
                height: sliderHeight,
                child: Align(
                  alignment: alignRight
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: const Text(
                    'No articles yet',
                    style: TextStyle(
                      fontFamily: 'Archivo',
                      fontSize: 11,
                      color: Color(0xFFAAAAAA),
                    ),
                  ),
                ),
              )
            : _ArticlesSlider(
                isLandscape: isLandscape,
                alignRight: alignRight,
                compactPortrait: compactPortrait,
                articles: articles,
              );

        // The ARTICLES title is intentionally inside the reveal child. Do not
        // render it separately above the provider state; that causes a visible
        // title jump before the article body fades in.
        return _DelayedTopFadeIn(
          key: ValueKey('articles-reveal-$slug'),
          height: dockHeight,
          child: buildContent(body),
        );
      },
      loading: () => SizedBox(height: dockHeight),
      error: (_, __) => SizedBox(height: dockHeight),
    );
  }
}

class _PresetDialDock extends ConsumerWidget {
  const _PresetDialDock({
    required this.isLandscape,
    required this.metrics,
    required this.onOverlayChanged,
  });

  final bool isLandscape;
  final XeneLayoutMetrics? metrics;
  final ValueChanged<bool> onOverlayChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dialAsync = ref.watch(presetDialProvider);

    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fallbackReservedWidth = metrics?.dialReservedWidth ?? 150.0;
            final availableWidth =
                constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : fallbackReservedWidth;
            final minReservedWidth = availableWidth < 96.0
                ? availableWidth
                : 96.0;
            final dialReservedWidth = fallbackReservedWidth
                .clamp(minReservedWidth, availableWidth)
                .toDouble();
            final maxKnobSize = (dialReservedWidth - 40.0)
                .clamp(48.0, 104.0)
                .toDouble();
            final dialKnobSize = (metrics?.dialKnobSize ?? 92.0)
                .clamp(48.0, maxKnobSize)
                .toDouble();
            final dialReservedHeight =
                (metrics?.dialReservedHeight ?? dialKnobSize + 74.0)
                    .clamp(dialKnobSize + 56.0, dialKnobSize + 96.0)
                    .toDouble();

            XeneResponsiveDebug.constraints('PresetDialDock', constraints);
            XeneResponsiveDebug.values('PresetDialDock.geometry', {
              'isLandscape': isLandscape,
              'availableWidth': availableWidth,
              'dialKnobSize': dialKnobSize,
              'dialReservedWidth': dialReservedWidth,
              'dialReservedHeight': dialReservedHeight,
            });

            return SizedBox(
              width: dialReservedWidth,
              child: dialAsync.when(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: true,
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
                        knobSize: dialKnobSize,
                        reservedWidth: dialReservedWidth,
                        reservedHeight: dialReservedHeight,
                        onOverlayChanged: onOverlayChanged,
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
            );
          },
        ),
      ),
    );
  }
}
