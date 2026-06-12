import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart'
    hide PlayerState;

import '../providers/articles_provider.dart';
import '../theme/xene_theme.dart';

// ─── Entry point ──────────────────────────────────────────────────────────────

class XeneArticleSheet extends ConsumerWidget {
  const XeneArticleSheet({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final sheetMaxWidth = _articleSheetMaxWidth(context);
    return DraggableScrollableSheet(
      initialChildSize: isLandscape ? 0.91 : 0.69,
      minChildSize: 0.20,
      maxChildSize: 0.97,
      builder: (context, scrollController) {
        final topControlSpace = isLandscape ? 46.0 : 0.0;
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: sheetMaxWidth),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  top: topControlSpace,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: ColoredBox(
                      color: const Color(0xFF0D0D0D),
                      child: Column(
                        children: [
                          const _DragHandle(),
                          Expanded(
                            child: Stack(
                              children: [
                                _ArticleContent(
                                  slug: slug,
                                  scrollController: scrollController,
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 18,
                                  child: _ScrollCueOverlay(
                                    scrollController: scrollController,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (isLandscape)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _SheetCloseButton(
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
        ),
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

double _articleSheetMaxWidth(BuildContext context) {
  final mq = MediaQuery.of(context);
  if (mq.orientation != Orientation.landscape || mq.size.width >= 950) {
    return double.infinity;
  }

  return (mq.size.width * 0.75).clamp(320.0, 370.0);
}

// ─── Content (async) ──────────────────────────────────────────────────────────

class _ArticleContent extends ConsumerWidget {
  const _ArticleContent({required this.slug, required this.scrollController});

  final String slug;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(xeneArticleProvider(slug));

    return async.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: XeneTheme.tealDark,
        ),
      ),
      error: (e, _) {
        debugPrint('[XeneArticleSheet] Error: $e');
        return Center(
          child: Text(
            'Could not load article.',
            style: GoogleFonts.dmMono(
              fontSize: 12,
              color: const Color(0xFF666666),
            ),
          ),
        );
      },
      data: (article) {
        if (article == null) {
          return Center(
            child: Text(
              'Article not found.',
              style: GoogleFonts.dmMono(
                fontSize: 12,
                color: const Color(0xFF666666),
              ),
            ),
          );
        }
        final accent =
            _parseThemeColor(article.themeColor) ?? XeneTheme.tealDark;
        return CustomScrollView(
          controller: scrollController,
          slivers: [
            if (article.coverImageUrl != null)
              SliverToBoxAdapter(
                child: _CoverImage(url: article.coverImageUrl!),
              ),
            SliverToBoxAdapter(
              child: _ArticleHeader(article: article, accent: accent),
            ),
            SliverList.builder(
              itemCount: article.blocks.length,
              itemBuilder: (context, i) =>
                  _BlockRenderer(block: article.blocks[i], accent: accent),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        );
      },
    );
  }
}

// ─── Structural widgets ───────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
    );
  }
}

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
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollCueOverlay extends StatefulWidget {
  const _ScrollCueOverlay({required this.scrollController});

  final ScrollController scrollController;

  @override
  State<_ScrollCueOverlay> createState() => _ScrollCueOverlayState();
}

class _ScrollCueOverlayState extends State<_ScrollCueOverlay> {
  bool _atBottom = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(_ScrollCueOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController == widget.scrollController) return;
    oldWidget.scrollController.removeListener(_update);
    widget.scrollController.addListener(_update);
    _update();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (!mounted) return;
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    final atBottom = position.pixels >= position.maxScrollExtent - 8;
    if (atBottom != _atBottom) {
      setState(() => _atBottom = atBottom);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _atBottom ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        child: const _JumpingChevron(),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final maxW = _sheetMediaMaxWidth(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: CachedNetworkImage(
          imageUrl: url,
          width: double.infinity,
          fit: BoxFit.contain,
          placeholder: (_, __) =>
              const AspectRatio(aspectRatio: 16 / 9, child: SizedBox()),
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _ArticleHeader extends StatelessWidget {
  const _ArticleHeader({required this.article, required this.accent});
  final XeneArticle article;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Section label: custom text wins, otherwise derive from template
          Text(
            (article.sectionLabel != null && article.sectionLabel!.isNotEmpty)
                ? article.sectionLabel!.toUpperCase()
                : _templateLabel(article.layoutTemplate),
            textAlign: TextAlign.right,
            style: GoogleFonts.dmMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          // Title
          Text(
            article.title,
            textAlign: TextAlign.right,
            style: GoogleFonts.teko(
              fontSize: 38,
              height: 0.95,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          // Dek
          if (article.dek != null && article.dek!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              article.dek!,
              textAlign: TextAlign.right,
              style: GoogleFonts.archivo(
                fontSize: 15,
                height: 1.4,
                color: const Color(0xFFAAAAAA),
              ),
            ),
          ],
          // Author
          if (article.author != null && article.author!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'BY ${article.author!.toUpperCase()}',
              textAlign: TextAlign.right,
              style: GoogleFonts.dmMono(
                fontSize: 10,
                color: const Color(0xFF666666),
                letterSpacing: 1.2,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Divider(color: const Color(0xFF222222), height: 1),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Block dispatcher ─────────────────────────────────────────────────────────

class _BlockRenderer extends StatelessWidget {
  const _BlockRenderer({required this.block, required this.accent});
  final XeneArticleBlock block;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case 'text':
        return _TextBlock(block: block);
      case 'quote':
        return _QuoteBlock(block: block, accent: accent);
      case 'image':
        return _ImageBlock(block: block);
      case 'video':
        return _VideoBlock(block: block);
      case 'voice_note':
        return _VoiceNoteBlock(block: block, accent: accent);
      case 'spacer':
        return _SpacerBlock(block: block);
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─── Text block ───────────────────────────────────────────────────────────────

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.block});
  final XeneArticleBlock block;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (block.heading != null && block.heading!.isNotEmpty) ...[
            Text(
              block.heading!,
              textAlign: TextAlign.right,
              style: GoogleFonts.teko(
                fontSize: 26,
                height: 1.0,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (block.body != null && block.body!.isNotEmpty)
            Text(
              block.body!,
              textAlign: TextAlign.right,
              style: GoogleFonts.archivo(
                fontSize: 15,
                height: 1.65,
                color: const Color(0xFFCCCCCC),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Quote block ──────────────────────────────────────────────────────────────

class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.block, required this.accent});
  final XeneArticleBlock block;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (block.text != null)
                  Text(
                    '”${block.text!}”',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.teko(
                      fontSize: 24,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                if (block.attribution != null &&
                    block.attribution!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${block.attribution!} —',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      color: XeneTheme.muted,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            width: 3,
            height: 60,
            color: accent,
            margin: const EdgeInsets.only(left: 16, top: 4),
          ),
        ],
      ),
    );
  }
}

// ─── Image block ──────────────────────────────────────────────────────────────

class _ImageBlock extends StatelessWidget {
  const _ImageBlock({required this.block});
  final XeneArticleBlock block;

  double _aspectRatio() {
    final parts = (block.aspect ?? '16:9').split(':');
    if (parts.length != 2) return 16 / 9;
    final w = double.tryParse(parts[0]) ?? 16;
    final h = double.tryParse(parts[1]) ?? 9;
    return h == 0 ? 16 / 9 : w / h;
  }

  @override
  Widget build(BuildContext context) {
    if (block.url == null || block.url!.isEmpty) return const SizedBox.shrink();
    final maxW = _sheetMediaMaxWidth(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: AspectRatio(
                aspectRatio: _aspectRatio(),
                child: CachedNetworkImage(
                  imageUrl: block.url!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      const ColoredBox(color: Color(0xFF1A1A1A)),
                  errorWidget: (_, url, error) {
                    debugPrint(
                      '[ImageBlock] Failed to load: $url error: $error',
                    );
                    return const ColoredBox(color: Color(0xFF1A1A1A));
                  },
                ),
              ),
            ),
          ),
          if (block.caption != null && block.caption!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                block.caption!,
                textAlign: TextAlign.right,
                style: GoogleFonts.dmMono(
                  fontSize: 10,
                  color: const Color(0xFF666666),
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Video block ──────────────────────────────────────────────────────────────

class _VideoBlock extends StatefulWidget {
  const _VideoBlock({required this.block});
  final XeneArticleBlock block;

  @override
  State<_VideoBlock> createState() => _VideoBlockState();
}

class _VideoBlockState extends State<_VideoBlock> {
  YoutubePlayerController? _ytController;
  bool _ytActive = false;

  @override
  void dispose() {
    _ytController?.close();
    super.dispose();
  }

  // Handles watch?v=, youtu.be/, embed/, AND /shorts/ URLs.
  static String? _extractVideoId(String url) {
    final fromPackage = YoutubePlayerController.convertUrlToId(url);
    if (fromPackage != null) return fromPackage;
    // Shorts: youtube.com/shorts/VIDEO_ID
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host.replaceFirst('www.', '');
    if (host == 'youtube.com' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments[0] == 'shorts') {
      final id = uri.pathSegments[1];
      return id.isNotEmpty ? id : null;
    }
    return null;
  }

  // Returns a usable image URL for the thumbnail.
  // Ignores explicit_thumb if it is a YouTube video/shorts page URL (not an image).
  String? get _thumbnailUrl {
    final url = widget.block.url;
    final explicit = widget.block.thumbnailUrl;
    debugPrint('[VideoBlock] url=$url | explicit_thumb=$explicit');

    final isPageUrl =
        explicit != null &&
        (explicit.contains('/shorts/') ||
            explicit.contains('/watch') ||
            explicit.contains('youtu.be/'));

    if (explicit != null && explicit.isNotEmpty && !isPageUrl) {
      debugPrint('[VideoBlock] Using explicit thumbnail: $explicit');
      return explicit;
    }

    if (url == null || url.isEmpty) {
      debugPrint('[VideoBlock] No video URL — cannot derive thumbnail');
      return null;
    }
    final videoId = _extractVideoId(url);
    debugPrint('[VideoBlock] videoId=$videoId');
    if (videoId == null) return null;
    final derived = 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
    debugPrint('[VideoBlock] Derived thumbnail: $derived');
    return derived;
  }

  Future<void> _onTap() async {
    final url = widget.block.url;
    if (url == null || url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // Flutter Web: HtmlElementView iframes break inside DraggableScrollableSheet
    // due to CSS transform conflicts. Always open in a new browser tab on web.
    if (kIsWeb) {
      debugPrint('[VideoBlock] Web — opening in new tab: $url');
      final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!launched) debugPrint('[VideoBlock] launchUrl failed for: $url');
      return;
    }

    final videoId = _extractVideoId(url);
    if (videoId != null) {
      debugPrint('[VideoBlock] Loading YouTube inline id=$videoId');
      final controller = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          mute: false,
        ),
      );
      setState(() {
        _ytController = controller;
        _ytActive = true;
      });
    } else {
      debugPrint('[VideoBlock] Non-YouTube — opening externally: $url');
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) debugPrint('[VideoBlock] launchUrl failed for: $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxW = _sheetMediaMaxWidth(context);

    if (_ytActive && _ytController != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: YoutubePlayer(
              controller: _ytController!,
              aspectRatio: 16 / 9,
            ),
          ),
        ),
      );
    }

    final thumb = _thumbnailUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: GestureDetector(
            onTap: _onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (thumb != null)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          const ColoredBox(color: Color(0xFF1A1A1A)),
                      errorWidget: (_, url, err) {
                        debugPrint(
                          '[VideoBlock] Thumbnail failed: $url error: $err',
                        );
                        return const ColoredBox(color: Color(0xFF1A1A1A));
                      },
                    ),
                  )
                else
                  const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(color: Color(0xFF1A1A1A)),
                  ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Voice note block ─────────────────────────────────────────────────────────

class _VoiceNoteBlock extends StatefulWidget {
  const _VoiceNoteBlock({required this.block, required this.accent});
  final XeneArticleBlock block;
  final Color accent;

  @override
  State<_VoiceNoteBlock> createState() => _VoiceNoteBlockState();
}

class _VoiceNoteBlockState extends State<_VoiceNoteBlock> {
  late final AudioPlayer _player;
  bool _loading = true;
  bool _error = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initAudio();
  }

  Future<void> _initAudio() async {
    final url = widget.block.url;
    if (url == null || url.isEmpty) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    try {
      _durSub = _player.durationStream.listen((d) {
        if (d != null && mounted) setState(() => _duration = d);
      });
      _posSub = _player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _stateSub = _player.playerStateStream.listen((s) {
        if (mounted) setState(() => _playing = s.playing);
      });
      await _player.setUrl(url);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('[VoiceNoteBlock] Error loading audio: $e');
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
        });
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final block = widget.block;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Player container
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF222222)),
            ),
            child: _error
                ? Text(
                    'Audio unavailable',
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      color: const Color(0xFF666666),
                    ),
                  )
                : _loading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: accent,
                    ),
                  )
                : Row(
                    children: [
                      // Play / pause
                      GestureDetector(
                        onTap: () {
                          _playing ? _player.pause() : _player.play();
                        },
                        child: Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Elapsed time
                      Text(
                        _fmt(_position),
                        style: GoogleFonts.dmMono(
                          fontSize: 10,
                          color: XeneTheme.muted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Scrubber
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                            activeTrackColor: accent,
                            inactiveTrackColor: const Color(0xFF333333),
                            thumbColor: accent,
                            overlayColor: accent.withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            value: _duration.inMilliseconds > 0
                                ? (_position.inMilliseconds /
                                          _duration.inMilliseconds)
                                      .clamp(0.0, 1.0)
                                : 0.0,
                            onChanged: (v) {
                              final target = Duration(
                                milliseconds: (v * _duration.inMilliseconds)
                                    .round(),
                              );
                              _player.seek(target);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Duration
                      Text(
                        _fmt(_duration),
                        style: GoogleFonts.dmMono(
                          fontSize: 10,
                          color: XeneTheme.muted,
                        ),
                      ),
                    ],
                  ),
          ),
          // Transcript
          if (block.transcript != null && block.transcript!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'TRANSCRIPT',
              textAlign: TextAlign.right,
              style: GoogleFonts.dmMono(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF555555),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              block.transcript!,
              textAlign: TextAlign.right,
              style: GoogleFonts.archivo(
                fontSize: 13,
                height: 1.6,
                color: XeneTheme.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Spacer block ─────────────────────────────────────────────────────────────

class _SpacerBlock extends StatelessWidget {
  const _SpacerBlock({required this.block});
  final XeneArticleBlock block;

  @override
  Widget build(BuildContext context) {
    final height = switch (block.size) {
      'sm' => 16.0,
      'lg' => 56.0,
      _ => 32.0, // 'md' or unrecognized
    };
    return SizedBox(height: height);
  }
}

// ─── Utilities ────────────────────────────────────────────────────────────────

String _templateLabel(String template) {
  const labels = {
    'editorial': 'EDITORIAL',
    'interview': 'INTERVIEW',
    'visual_essay': 'VISUAL ESSAY',
    'audio_story': 'AUDIO STORY',
  };
  return labels[template] ?? template.toUpperCase().replaceAll('_', ' ');
}

Color? _parseThemeColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  if (h.length != 6) return null;
  final value = int.tryParse('FF$h', radix: 16);
  return value != null ? Color(value) : null;
}

double _sheetMediaMaxWidth(BuildContext context) {
  return double.infinity;
}
