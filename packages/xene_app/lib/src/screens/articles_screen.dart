import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/articles_provider.dart';
import 'xene_article_sheet.dart';

class ArticlesScreen extends ConsumerWidget {
  const ArticlesScreen({super.key});

  static const _teal = Color(0xFF00A88F);
  static const _muted = Color(0xFF888888);
  static const _orange = Color(0xFFFF5500);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverAsync = ref.watch(magazineCoverProvider);
    final articlesAsync = ref.watch(presetArticlesProvider);

    // SizedBox.expand forces this widget to fill the Expanded slot in
    // _InnerPageLayout exactly, so LayoutBuilder inside _MagazineLayout
    // always receives finite, tight constraints — never double.infinity.
    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.white,
        child: articlesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
          ),
          error: (_, __) => const _EmptyState(),
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
      ),
    );
  }
}

class _ContainedMagazineLayout extends StatelessWidget {
  const _ContainedMagazineLayout({required this.cover, required this.articles});

  final MagazineCover? cover;
  final List<ArticleItem> articles;

  static const _stripHeight = 200.0;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final rawAspect = cover?.aspectRatioValue ?? 3 / 4;
        final coverAspect = rawAspect > 0 ? rawAspect : 3 / 4;

        // Cover fills the full width at its native aspect ratio, pinned to top.
        // Clamp so the strip always has room below on very small screens.
        final maxCoverH = constraints.maxHeight - _stripHeight - bottomPad;
        final imgW = w;
        final imgH = (w / coverAspect).clamp(0.0, maxCoverH).toDouble();

        debugPrint(
          '[ContainedMagazineLayout] screen=${w}x${constraints.maxHeight} '
          'coverAspect=$coverAspect cover=${cover?.id ?? "none"} '
          'imgH=${imgH.toStringAsFixed(1)}',
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover pinned to top — SizedBox exactly matches 3:4 so
            // BoxFit.contain fills it with zero bars or distortion.
            SizedBox(
              width: imgW,
              height: imgH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CoverBackground(cover: cover),
                  if (cover != null)
                    for (final layer in cover!.motionLayers)
                      _MotionLayerOverlay(
                        layer: layer,
                        coverLeft: 0,
                        coverTop: 0,
                        coverW: imgW,
                        coverH: imgH,
                      ),
                  if (cover != null)
                    for (final spot in cover!.hotspots)
                      _HotspotZone(
                        hotspot: spot,
                        coverLeft: 0,
                        coverTop: 0,
                        coverW: imgW,
                        coverH: imgH,
                      ),
                ],
              ),
            ),
            // Articles strip with gradient background below the cover.
            SizedBox(
              height: _stripHeight + bottomPad,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _BottomGradient(),
                  _ArticleStrip(articles: articles, bottomPad: bottomPad),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Cover background ─────────────────────────────────────────────────────────

class _CoverBackground extends StatelessWidget {
  const _CoverBackground({required this.cover});

  final MagazineCover? cover;

  // URLs recorded as fully displayed this app session.
  // Prevents the loading placeholder from flashing on every tab revisit
  // because GoRouter rebuilds the screen from scratch on each navigation.
  static final Set<String> _seenUrls = {};

  @override
  Widget build(BuildContext context) {
    final url = cover?.backgroundImageUrl ?? '';
    if (url.isEmpty) return const _DarkFallbackPattern();

    final alreadySeen = _seenUrls.contains(url);

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
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
        return Image(image: imageProvider, fit: BoxFit.contain);
      },
      placeholder: alreadySeen ? null : (_, __) => const _DarkFallbackPattern(),
      errorWidget: (_, __, ___) => const _DarkFallbackPattern(),
    );
  }
}

class _DarkFallbackPattern extends StatelessWidget {
  const _DarkFallbackPattern();

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

class _BottomGradient extends StatelessWidget {
  const _BottomGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xCC000000), Colors.black],
          stops: [0.0, 0.55, 1.0],
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

  void _onTap(BuildContext context) {
    debugPrint('[HotspotZone] tapped id=${hotspot.id} title=${hotspot.title}');
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _HotspotSheet(hotspot: hotspot),
    );
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

class _HotspotSheet extends StatelessWidget {
  const _HotspotSheet({required this.hotspot});

  final MagazineHotspot hotspot;

  Future<void> _openLink(BuildContext context) async {
    final url = hotspot.articleUrl;
    if (url == null || url.isEmpty) return;

    // Xene native article — open in-app reader
    if (url.startsWith('xene://article/')) {
      final slug = url.replaceFirst('xene://article/', '');
      debugPrint('[HotspotSheet] Opening Xene article slug=$slug');
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => XeneArticleSheet(slug: slug),
      );
      return;
    }

    // External URL — open in browser
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hotspot.title,
              style: GoogleFonts.teko(
                fontSize: 32,
                height: 0.95,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            if (hotspot.body != null && hotspot.body!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                hotspot.body!,
                style: GoogleFonts.archivo(
                  fontSize: 13,
                  height: 1.5,
                  color: const Color(0xFFAAAAAA),
                ),
              ),
            ],
            if (hotspot.articleUrl != null &&
                hotspot.articleUrl!.isNotEmpty) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => _openLink(context),
                child: Text(
                  'READ →',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ArticlesScreen._teal,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Article strip ────────────────────────────────────────────────────────────

class _ArticleStrip extends StatefulWidget {
  const _ArticleStrip({required this.articles, required this.bottomPad});

  final List<ArticleItem> articles;
  final double bottomPad;

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
    debugPrint('[ArticleStrip] opening url=${article.url}');
    final uri = Uri.tryParse(article.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
      // Bottom padding lifts cards above the home indicator / system nav bar.
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + widget.bottomPad),
      itemCount: widget.articles.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, i) => _DarkCard(
        article: widget.articles[i],
        onTap: () => _open(widget.articles[i]),
      ),
    );
  }
}

// ─── Dark article card ────────────────────────────────────────────────────────

class _DarkCard extends StatefulWidget {
  const _DarkCard({required this.article, required this.onTap});

  final ArticleItem article;
  final VoidCallback onTap;

  @override
  State<_DarkCard> createState() => _DarkCardState();
}

class _DarkCardState extends State<_DarkCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final source = widget.article.source?.trim();
    final date = widget.article.publishedAt;

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
              // Thumbnail
              SizedBox(height: 96, child: _CardThumb(article: widget.article)),

              // Meta
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
