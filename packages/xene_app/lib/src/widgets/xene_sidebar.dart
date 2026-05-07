import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:google_fonts/google_fonts.dart';

class XeneSidebar extends StatefulWidget {
  const XeneSidebar({super.key});

  @override
  State<XeneSidebar> createState() => _XeneSidebarState();
}

class _XeneSidebarState extends State<XeneSidebar> {
  late ScrollController _scrollController;
  Timer? _scrollTimer;
  bool _isHovered = false;
  Orientation? _lastOrientation;
  Size _screenSize = Size.zero;
  Orientation _orientation = Orientation.portrait;

  // contentThreshold is the height of one content set
  double _getSetHeight(bool isLandscape) => isLandscape ? 740.0 : 700.0;
  static const double _contentThreshold = 600.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCrawl());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    _screenSize = mediaQuery.size;
    _orientation = mediaQuery.orientation;

    if (_lastOrientation == Orientation.landscape &&
        _orientation == Orientation.portrait) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
    _lastOrientation = _orientation;
  }

  void _startCrawl() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (!mounted) return;

      final availableHeight = _screenSize.height - 56;
      final isLandscape = _orientation == Orientation.landscape;

      final needsScroll = isLandscape || (availableHeight < _contentThreshold);

      if (needsScroll && !_isHovered && _scrollController.hasClients) {
        final currentScroll = _scrollController.offset;
        final setHeight = _getSetHeight(isLandscape);

        if (currentScroll >= setHeight) {
          _scrollController.jumpTo(currentScroll - setHeight);
        } else {
          _scrollController.jumpTo(currentScroll + 0.3);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildContentSet(bool isLandscape) {
    final double baseLogoSize = isLandscape ? 220.0 : 200.0;
    final double logoNSize = baseLogoSize + 4.0;
    final double logoBoxHeight = isLandscape ? 220.0 : 160.0;
    // GAP ADJUSTMENT: Logo now sits higher to align with the Feed header
    final double topSetPadding = isLandscape ? 10.0 : 20.0;
    final double logoToNavGap = isLandscape ? 130.0 : 110.0;

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
          SizedBox(height: logoToNavGap),
          const SizedBox(height: 50),

          Align(
            alignment: isLandscape
                ? Alignment.centerRight
                : Alignment.centerLeft,
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
                _ArticlesSlider(isLandscape: isLandscape),
              ],
            ),
          ),
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
                onPointerDown: (_) => setState(() => _isHovered = true),
                onPointerUp: (_) => setState(() => _isHovered = false),
                onPointerCancel: (_) => setState(() => _isHovered = false),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _isHovered = true),
                  onExit: (_) => setState(() => _isHovered = false),
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
                      if (needsScroll) _buildContentSet(isLandscape),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // PINNED BOTTOM SECTION
          Column(
            crossAxisAlignment: isLandscape
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              /*
              Text(
                'FRESH\nFEED',
                textAlign: isLandscape ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                  fontFamily: 'Teko',
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  height: 1.0
                )
              ),
              const SizedBox(height: 10),
              */
              /*
              const _JumpingChevron(),
              */
            ],
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _ArticlesSlider extends StatefulWidget {
  const _ArticlesSlider({required this.isLandscape});
  final bool isLandscape;
  @override
  State<_ArticlesSlider> createState() => _ArticlesSliderState();
}

class _ArticlesSliderState extends State<_ArticlesSlider> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;

  final List<Map<String, String>> _mockArticles = [
    {
      'title': 'R3IDY - SPINDLE',
      'snippet': 'Yamatai Records announce the return...',
    },
    {
      'title': 'THE FUTURE OF D&B',
      'snippet': 'Exploring the underground sounds...',
    },
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pageController.hasClients) {
        _currentPage = (_currentPage + 1) % _mockArticles.length;
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _mockArticles.length,
        itemBuilder: (context, index) {
          final article = _mockArticles[index];
          return Column(
            crossAxisAlignment: widget.isLandscape
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                article['title']!,
                textAlign: widget.isLandscape
                    ? TextAlign.right
                    : TextAlign.left,
                style: GoogleFonts.teko(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                article['snippet']!,
                textAlign: widget.isLandscape
                    ? TextAlign.right
                    : TextAlign.left,
                style: GoogleFonts.archivo(
                  fontSize: 12,
                  color: const Color(0xFF444444),
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
  return const Material(child: XeneSidebar());
}
