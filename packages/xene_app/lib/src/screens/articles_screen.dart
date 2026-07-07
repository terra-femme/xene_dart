import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/articles_provider.dart';
import '../theme/xene_theme.dart';
import 'xene_article_sheet.dart';

class ArticlesScreen extends ConsumerWidget {
  const ArticlesScreen({super.key});

  static const _teal = XeneTheme.tealDark;
  static const _muted = XeneTheme.muted;
  static const _orange = XeneTheme.orange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverAsync = ref.watch(magazineCoverProvider);
    final articlesAsync = ref.watch(featuredArticlesProvider);

    // SizedBox.expand forces this widget to fill the Expanded slot in
    // _InnerPageLayout exactly, so LayoutBuilder inside _MagazineLayout
    // always receives finite, tight constraints — never double.infinity.
    return SizedBox.expand(
      child: articlesAsync.when(
        loading: () => const ColoredBox(
          color: Colors.white,
          child: Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
          ),
        ),
        error: (_, __) =>
            const ColoredBox(color: Colors.white, child: _EmptyState()),
        data: (articles) {
          final visible = articles.where((a) => a.url.isNotEmpty).toList();

          final cover = coverAsync.when(
            loading: () => null,
            error: (_, __) => null,
            data: (c) => c,
          );

          return _ContainedMagazineLayout(cover: cover, articles: visible);
        },
      ),
    );
  }
}

class _ContainedMagazineLayout extends StatefulWidget {
  const _ContainedMagazineLayout({required this.cover, required this.articles});

  final MagazineCover? cover;
  final List<ArticleItem> articles;

  @override
  State<_ContainedMagazineLayout> createState() =>
      _ContainedMagazineLayoutState();
}

class _ContainedMagazineLayoutState extends State<_ContainedMagazineLayout> {
  static const _stripHeight = 200.0;
  bool _landscapeAtBottom = false;
  bool _portraitAtBottom = false;

  bool _handleLandscapeScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;

    final atBottom = metrics.pixels >= metrics.maxScrollExtent - 8;
    if (atBottom != _landscapeAtBottom) {
      setState(() => _landscapeAtBottom = atBottom);
    }
    return false;
  }

  bool _handlePortraitScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;

    final atBottom = metrics.pixels >= metrics.maxScrollExtent - 8;
    if (atBottom != _portraitAtBottom) {
      setState(() => _portraitAtBottom = atBottom);
    }
    return false;
  }

  // Shared cover Stack — hotspot and motion layer coords are fractions of
  // coverW/coverH, so they scale correctly regardless of which layout branch
  // places this stack.
  Stack _coverStack(
    double coverW,
    double coverH, {
    BoxFit backgroundFit = BoxFit.contain,
    bool showScrollCue = false,
    double? scrollCueTop,
    double? scrollCueBottom,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _CoverBackground(cover: widget.cover, fit: backgroundFit),
        if (widget.cover != null)
          for (final layer in widget.cover!.motionLayers)
            _MotionLayerOverlay(
              layer: layer,
              coverLeft: 0,
              coverTop: 0,
              coverW: coverW,
              coverH: coverH,
            ),
        if (widget.cover != null)
          for (final spot in widget.cover!.hotspots)
            _HotspotZone(
              hotspot: spot,
              coverLeft: 0,
              coverTop: 0,
              coverW: coverW,
              coverH: coverH,
            ),
        if (showScrollCue)
          Positioned(
            left: 0,
            right: 0,
            top: scrollCueTop,
            bottom: scrollCueBottom,
            child: const IgnorePointer(child: _JumpingChevron()),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final mediaPadding = mediaQuery.padding;
    final bottomPad = mediaPadding.bottom;

    // Use full viewport width/height instead of constrained layout width.
    // On real Safari (vs device_preview), the LayoutBuilder constraints are
    // reduced by safe areas. Using a SizedBox with explicit dimensions ensures
    // the magazine cover spans edge-to-edge on all platforms without being
    // constrained by parent layout constraints.
    final w = mediaQuery.size.width;
    final h = mediaQuery.size.height;
    final rawAspect = widget.cover?.aspectRatioValue ?? 3 / 4;
    final coverAspect = rawAspect > 0 ? rawAspect : 3 / 4;
    final isLandscape = w > h;

    debugPrint(
      '[ContainedMagazineLayout] screen=${w}x${h} '
      'coverAspect=$coverAspect cover=${widget.cover?.id ?? "none"} '
      'landscape=$isLandscape safeL=${mediaPadding.left}',
    );

    // Shift the entire content block up by 5 px so the cover sits flush
    // against the nav bar with no visible seam. Content paints last in
    // the parent Column so it renders on top of the divider cleanly.
    const landscapeLift = 20.0;
    const portraitLift = 5.0;

    // Wrap in SizedBox with explicit full viewport width to prevent parent
    // layout constraints from reducing the width on real Safari devices.
    return SizedBox(
      width: w,
      height: h,
      child: Builder(
        builder: (context) {
          if (isLandscape) {
            // Cover fills full width at its natural (portrait) aspect ratio —
            // much taller than the screen. User scrolls down through the cover,
            // then reaches the article strip at the bottom.
            // Keep the authored cover fully visible in landscape; the source
            // art is positioned carefully and should not be horizontally cropped.
            final coverH = w / coverAspect;

            // ClipRect prevents the translated scrollable from painting over the
            // nav bar. The trade-off is the top landscapeLift px of the cover are
            // clipped, but the cover is ~1000 px tall so it is imperceptible.
            return ClipRect(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: _handleLandscapeScroll,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(left: mediaPadding.left),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: w,
                            height: coverH - landscapeLift,
                            child: ClipRect(
                              child: Transform.translate(
                                offset: const Offset(0, -landscapeLift),
                                child: SizedBox(
                                  width: w,
                                  height: coverH,
                                  child: _coverStack(w, coverH),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            key: const ValueKey('landscapeArticleStrip'),
                            height: _stripHeight + bottomPad,
                            child: ColoredBox(
                              color: Colors.white,
                              child: _ArticleStrip(
                                articles: widget.articles,
                                bottomPad: bottomPad,
                                landscape: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_landscapeAtBottom)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 32 + bottomPad,
                      child: const IgnorePointer(child: _JumpingChevron()),
                    ),
                ],
              ),
            );
          } else {
            final imgH = w / coverAspect;
            final portraitContentH =
                imgH + portraitLift + 5 + _stripHeight + bottomPad * 2 + 12;
            final portraitCanScroll = portraitContentH > h + 8;

            return ClipRect(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: _handlePortraitScroll,
                    child: Transform.translate(
                      offset: const Offset(0, -portraitLift),
                      child: CustomScrollView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        slivers: [
                          SliverToBoxAdapter(
                            child: SizedBox(
                              width: w,
                              height: imgH + portraitLift,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: SizedBox(
                                  width: w,
                                  height: imgH,
                                  child: _coverStack(w, imgH),
                                ),
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 5)),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              key: const ValueKey('portraitArticleStrip'),
                              height: _stripHeight + bottomPad,
                              child: ColoredBox(
                                color: Colors.white,
                                child: _ArticleStrip(
                                  articles: widget.articles,
                                  bottomPad: bottomPad,
                                  landscape: false,
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(height: bottomPad + 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (portraitCanScroll && !_portraitAtBottom)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 32 + bottomPad,
                      child: const IgnorePointer(child: _JumpingChevron()),
                    ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}

// ─── Cover background ─────────────────────────────────────────────────────────

class _CoverBackground extends StatelessWidget {
  const _CoverBackground({required this.cover, this.fit = BoxFit.contain});

  final MagazineCover? cover;
  final BoxFit fit;

  // URLs recorded as fully displayed this app session.
  // Prevents the loading placeholder from flashing on every tab revisit
  // because GoRouter rebuilds the screen from scratch on each navigation.
  static final Set<String> _seenUrls = {};

  @override
  Widget build(BuildContext context) {
    final url = cover?.backgroundImageUrl ?? '';
    if (url.isEmpty) return const _LightFallbackPattern();

    final alreadySeen = _seenUrls.contains(url);

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      fadeInDuration: alreadySeen
          ? Duration.zero
          : const Duration(milliseconds: 700),
      fadeInCurve: Curves.easeIn,
      fadeOutDuration: alreadySeen
          ? Duration.zero
          : const Duration(milliseconds: 500),
      fadeOutCurve: Curves.easeOut,
      imageBuilder: (_, imageProvider) {
        _seenUrls.add(url);
        return Image(image: imageProvider, fit: fit);
      },
      placeholder: alreadySeen
          ? null
          : (_, __) => const _LightFallbackPattern(),
      errorWidget: (_, __, ___) => const _LightFallbackPattern(),
    );
  }
}

class _LightFallbackPattern extends StatelessWidget {
  const _LightFallbackPattern();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Text(
          'XENE COVER LOADING...',
          style: GoogleFonts.teko(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            height: 1.0,
            color: Colors.black.withValues(alpha: 0.15),
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

// ─── Bottom gradient ──────────────────────────────────────────────────────────

class _JumpingChevron extends StatefulWidget {
  const _JumpingChevron();

  @override
  State<_JumpingChevron> createState() => _JumpingChevronState();
}

class _JumpingChevronState extends State<_JumpingChevron>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _offset = Tween<double>(
      begin: -2,
      end: 9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _offset.value),
          child: child,
        );
      },
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.88),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.45),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Lottie overlay ───────────────────────────────────────────────────────────

class _MotionLayerOverlay extends StatefulWidget {
  const _MotionLayerOverlay({
    required this.layer,
    required this.coverLeft,
    required this.coverTop,
    required this.coverW,
    required this.coverH,
  });

  final MagazineMotionLayer layer;
  final double coverLeft;
  final double coverTop;
  final double coverW;
  final double coverH;

  @override
  State<_MotionLayerOverlay> createState() => _MotionLayerOverlayState();
}

class _MotionLayerOverlayState extends State<_MotionLayerOverlay>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  void _onLottieLoaded(LottieComposition composition) {
    if (!mounted) return;
    final speed = widget.layer.speed.clamp(0.1, 5.0);
    final controller = AnimationController(
      vsync: this,
      duration: Duration(
        microseconds: (composition.duration.inMicroseconds / speed).round(),
      ),
    );
    setState(() => _controller = controller);
    if (widget.layer.loop) {
      controller.repeat();
    } else {
      controller.forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final type = layer.type.toLowerCase();

    if (type == 'shader') {
      return _PositionedLayer(
        layer: layer,
        coverLeft: widget.coverLeft,
        coverTop: widget.coverTop,
        coverW: widget.coverW,
        coverH: widget.coverH,
        child: _ShaderOverlay(layer: layer),
      );
    }

    if (layer.url.isEmpty || type != 'lottie') return const SizedBox();

    return _PositionedLayer(
      layer: layer,
      coverLeft: widget.coverLeft,
      coverTop: widget.coverTop,
      coverW: widget.coverW,
      coverH: widget.coverH,
      child: Opacity(
        opacity: layer.opacity.clamp(0.0, 1.0),
        child: Lottie.network(
          layer.url,
          controller: _controller,
          onLoaded: _onLottieLoaded,
          errorBuilder: (_, __, ___) => const SizedBox(),
        ),
      ),
    );
  }
}

class _PositionedLayer extends StatelessWidget {
  const _PositionedLayer({
    required this.layer,
    required this.coverLeft,
    required this.coverTop,
    required this.coverW,
    required this.coverH,
    required this.child,
  });

  final MagazineMotionLayer layer;
  final double coverLeft;
  final double coverTop;
  final double coverW;
  final double coverH;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = layer.width <= 0 ? 1.0 : layer.width;
    final height = layer.height <= 0 ? 1.0 : layer.height;

    return Positioned(
      left: coverLeft + coverW * layer.x,
      top: coverTop + coverH * layer.y,
      width: coverW * width,
      height: coverH * height,
      child: child,
    );
  }
}

class _ShaderOverlay extends StatefulWidget {
  const _ShaderOverlay({required this.layer});

  final MagazineMotionLayer layer;

  @override
  State<_ShaderOverlay> createState() => _ShaderOverlayState();
}

class _ShaderOverlayState extends State<_ShaderOverlay>
    with SingleTickerProviderStateMixin {
  static final Future<ui.FragmentProgram> _program =
      ui.FragmentProgram.fromAsset('assets/shaders/magazine_liquid.frag');

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
    if (widget.layer.loop) {
      _ctrl.repeat();
    } else {
      _ctrl.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _ShaderOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer.loop == widget.layer.loop) return;
    if (widget.layer.loop) {
      _ctrl.repeat();
    } else {
      _ctrl
        ..stop()
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.FragmentProgram>(
      future: _program,
      builder: (context, snapshot) {
        final program = snapshot.data;
        if (program == null) return const SizedBox();

        return IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => CustomPaint(
                painter: _MagazineShaderPainter(
                  program: program,
                  time: _ctrl.value * _ctrl.duration!.inMilliseconds / 1000.0,
                  intensity: _shaderIntensity(widget.layer.url),
                  accent: _shaderAccent(widget.layer.url),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MagazineShaderPainter extends CustomPainter {
  const _MagazineShaderPainter({
    required this.program,
    required this.time,
    required this.intensity,
    required this.accent,
  });

  final ui.FragmentProgram program;
  final double time;
  final double intensity;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, intensity)
      ..setFloat(4, (accent.r * 255.0).round() / 255.0)
      ..setFloat(5, (accent.g * 255.0).round() / 255.0)
      ..setFloat(6, (accent.b * 255.0).round() / 255.0);

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.screen,
    );
  }

  @override
  bool shouldRepaint(_MagazineShaderPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.intensity != intensity ||
        oldDelegate.accent != accent ||
        oldDelegate.program != program;
  }
}

double _shaderIntensity(String value) {
  final match = RegExp(r'intensity=([0-9.]+)').firstMatch(value);
  final parsed = match == null ? null : double.tryParse(match.group(1)!);
  return (parsed ?? 1.0).clamp(0.0, 2.0).toDouble();
}

Color _shaderAccent(String value) {
  final match = RegExp(r'#[0-9a-fA-F]{6}').firstMatch(value);
  final hex = match?.group(0)?.substring(1);
  if (hex == null) return ArticlesScreen._teal;
  return Color(int.parse('FF$hex', radix: 16));
}

// ─── Hotspot tap zone ─────────────────────────────────────────────────────────

class _HotspotZone extends StatelessWidget {
  const _HotspotZone({
    required this.hotspot,
    required this.coverLeft,
    required this.coverTop,
    required this.coverW,
    required this.coverH,
  });

  final MagazineHotspot hotspot;
  final double coverLeft;
  final double coverTop;
  final double coverW;
  final double coverH;

  Future<void> _onTap(BuildContext context) async {
    final url = hotspot.articleUrl;
    debugPrint(
      '[HotspotZone] tapped id=${hotspot.id} title=${hotspot.title} url=$url',
    );

    if (url != null && url.startsWith('xene://article/')) {
      final slug = url.replaceFirst('xene://article/', '');
      debugPrint('[HotspotZone] Opening Xene article slug=$slug');
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        builder: (_) => XeneArticleSheet(slug: slug),
      );
      return;
    }

    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null)
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: coverLeft + coverW * hotspot.x,
      top: coverTop + coverH * hotspot.y,
      width: coverW * hotspot.width,
      height: coverH * hotspot.height,
      child: GestureDetector(
        onTap: () => _onTap(context),
        behavior: HitTestBehavior.opaque,
        child: const ColoredBox(color: Colors.transparent),
      ),
    );
  }
}

// ─── Article strip ────────────────────────────────────────────────────────────

class _ArticleStrip extends StatefulWidget {
  const _ArticleStrip({
    required this.articles,
    required this.bottomPad,
    this.landscape = false,
  });

  final List<ArticleItem> articles;
  final double bottomPad;
  final bool landscape;

  @override
  State<_ArticleStrip> createState() => _ArticleStripState();
}

class _ArticleStripState extends State<_ArticleStrip> {
  late final ScrollController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = ScrollController();
    debugPrint('[ArticleStrip] init with ${widget.articles.length} articles');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _open(ArticleItem article) async {
    debugPrint('[ArticleStrip] opening pip for url=${article.url}');
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ArticlePreviewSheet(article: article),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.articles.isEmpty) {
      return Center(
        child: Text(
          'NO ARTICLES YET',
          style: GoogleFonts.dmMono(
            fontSize: 10,
            color: ArticlesScreen._muted,
            letterSpacing: 1.4,
          ),
        ),
      );
    }

    return ListView.separated(
      controller: _ctrl,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: widget.landscape
          ? EdgeInsets.fromLTRB(16, 10, 16, 10 + widget.bottomPad)
          : EdgeInsets.fromLTRB(20, 12, 20, 12 + widget.bottomPad),
      itemCount: widget.articles.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, i) => _DarkCard(
        article: widget.articles[i],
        onTap: () => _open(widget.articles[i]),
        landscape: widget.landscape,
      ),
    );
  }
}

// ─── Dark article card ────────────────────────────────────────────────────────

class _DarkCard extends StatefulWidget {
  const _DarkCard({
    required this.article,
    required this.onTap,
    this.landscape = false,
  });

  final ArticleItem article;
  final VoidCallback onTap;
  final bool landscape;

  @override
  State<_DarkCard> createState() => _DarkCardState();
}

class _DarkCardState extends State<_DarkCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final source = widget.article.source?.trim();
    final date = widget.article.publishedAt;

    if (widget.landscape) {
      // Compact fixed-width card for the landscape overlay strip.
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: 148,
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0xCC1A1A1A)
                  : const Color(0xBB111111),
              border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _CardThumb(article: widget.article)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (source != null && source.isNotEmpty)
                        Text(
                          source.toUpperCase(),
                          style: GoogleFonts.dmMono(
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                            color: ArticlesScreen._teal,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 2),
                      Text(
                        widget.article.title,
                        style: GoogleFonts.teko(
                          fontSize: 13,
                          height: 0.97,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Portrait card: vertical layout, fixed 158px wide
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: 158,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF1A1A1A) : const Color(0xFF111111),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF444444)
                  : const Color(0xFF222222),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 96, child: _CardThumb(article: widget.article)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (source != null && source.isNotEmpty)
                            Expanded(
                              child: Text(
                                source.toUpperCase(),
                                style: GoogleFonts.dmMono(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: ArticlesScreen._teal,
                                  letterSpacing: 0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          else
                            const Spacer(),
                          if (date != null)
                            Text(
                              DateFormat('MM.dd').format(date),
                              style: GoogleFonts.dmMono(
                                fontSize: 8,
                                color: ArticlesScreen._muted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Expanded(
                        child: Text(
                          widget.article.title,
                          style: GoogleFonts.teko(
                            fontSize: 16,
                            height: 0.97,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardThumb extends StatelessWidget {
  const _CardThumb({required this.article});

  final ArticleItem article;

  @override
  Widget build(BuildContext context) {
    final url = article.imageUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 160),
        errorWidget: (_, __, ___) => _thumbFallback(),
        placeholder: (_, __) => _thumbFallback(),
      );
    }
    return _thumbFallback();
  }

  Widget _thumbFallback() {
    final seed = article.title.codeUnits.fold<int>(0, (a, b) => a + b);
    final accent = seed.isEven ? ArticlesScreen._orange : ArticlesScreen._teal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E0E),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.6), width: 3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            (article.source ?? 'XENE').toUpperCase(),
            style: GoogleFonts.dmMono(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.8,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

// ─── Article preview sheet (PiP overlay) ─────────────────────────────────────

class _ArticlePreviewSheet extends StatelessWidget {
  const _ArticlePreviewSheet({required this.article});

  final ArticleItem article;

  static const _bg = Color(0xFF0D0D0D);
  static const _teal = ArticlesScreen._teal;

  Future<void> _readFull(BuildContext context) async {
    final uri = Uri.tryParse(article.url);
    if (uri == null) return;
    debugPrint('[ArticlePreviewSheet] opening in-app url=${article.url}');
    final launched = await launchUrl(uri, mode: LaunchMode.inAppWebView);
    if (!launched) {
      debugPrint(
        '[ArticlePreviewSheet] inAppWebView failed, fallback to external',
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.38,
      maxChildSize: 0.88,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: ColoredBox(
            color: _bg,
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF444444),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  // Cover image
                  if (article.imageUrl != null && article.imageUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: article.imageUrl!,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 220),
                      placeholder: (_, __) => const SizedBox(
                        height: 200,
                        child: ColoredBox(color: Color(0xFF111111)),
                      ),
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Source + date row
                        Row(
                          children: [
                            if (article.source != null &&
                                article.source!.trim().isNotEmpty)
                              Text(
                                article.source!.trim().toUpperCase(),
                                style: GoogleFonts.dmMono(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: _teal,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            const Spacer(),
                            if (article.publishedAt != null)
                              Text(
                                DateFormat(
                                  'MMM d, yyyy',
                                ).format(article.publishedAt!),
                                style: GoogleFonts.dmMono(
                                  fontSize: 9,
                                  color: const Color(0xFF666666),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Title
                        Text(
                          article.title,
                          style: GoogleFonts.teko(
                            fontSize: 30,
                            height: 0.97,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        // Snippet
                        if (article.snippet.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            article.snippet,
                            style: GoogleFonts.archivo(
                              fontSize: 14,
                              height: 1.55,
                              color: const Color(0xFF999999),
                            ),
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 24),
                        // CTA button
                        GestureDetector(
                          onTap: () => _readFull(context),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              border: Border.all(color: _teal, width: 1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  article.source != null &&
                                          article.source!.trim().isNotEmpty
                                      ? 'READ ON ${article.source!.trim().toUpperCase()}'
                                      : 'READ FULL ARTICLE',
                                  style: GoogleFonts.teko(
                                    fontSize: 15,
                                    letterSpacing: 1.2,
                                    color: _teal,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: _teal,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'NO ARTICLES YET',
        style: GoogleFonts.teko(
          fontSize: 28,
          color: ArticlesScreen._muted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
