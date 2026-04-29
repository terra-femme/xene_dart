import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class XeneSidebar extends StatelessWidget {
  const XeneSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    if (view.physicalSize.height <= 0 || view.physicalSize.width <= 0) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.of(context).size;
    if (size.height < 150) return const SizedBox.shrink();

    final width = size.width * 0.30;
    final clampedWidth = width.clamp(180.0, 210.0);

    return Container(
      width: clampedWidth,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
      ),
      padding: const EdgeInsets.only(left: 12),
      child: ListView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 15),
          
          // LOGO SECTION - Wrapped in OverflowBox to prevent clipping at 210pt
          SizedBox(
            width: 191,
            height: 140,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: 250,
              child: Text(
                'XE\nNE',
                style: GoogleFonts.jaro(
                  fontSize: 210,
                  height: 0.60, 
                  letterSpacing: -0.06 * 210,
                  color: Colors.black,
                ),
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
          ),
          
          const SizedBox(height: 110),
          
          // NAVIGATION - Using Transform instead of negative SizedBox
          _NavText(label: 'ARTIST', fontSize: 48, height: 0.8),
          Transform.translate(
            offset: const Offset(0, -12),
            child: _NavText(label: 'NETWORK', fontSize: 48, height: 1.0),
          ),
          
          const SizedBox(height: 50),
          
          // ARTICLES SLIDER
          const Text(
            'ARTICLES', 
            style: TextStyle(
              fontFamily: 'Teko', 
              fontSize: 12, 
              color: Color(0xFF666666), 
              letterSpacing: 1.44, 
              height: 1.66
            )
          ),
          const SizedBox(height: 4),
          const _ArticlesSlider(), 
          
          const SizedBox(height: 80),
          
          // BOTTOM FEED SECTION
          const Text(
            'FRESH\nFEED', 
            style: TextStyle(
              fontFamily: 'Teko', 
              fontSize: 40, 
              fontWeight: FontWeight.bold, 
              color: Colors.black, 
              height: 1.0
            )
          ),
          const SizedBox(height: 10),
          const _JumpingChevron(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _NavText extends StatelessWidget {
  const _NavText({required this.label, required this.fontSize, required this.height});
  final String label;
  final double fontSize;
  final double height;
  
  @override
  Widget build(BuildContext context) {
    return Text(
      label, 
      style: GoogleFonts.teko(
        fontSize: fontSize, 
        height: height, 
        color: Colors.black, 
        fontWeight: FontWeight.w400
      )
    );
  }
}

class _ArticlesSlider extends StatefulWidget {
  const _ArticlesSlider({super.key});
  @override
  State<_ArticlesSlider> createState() => _ArticlesSliderState();
}

class _ArticlesSliderState extends State<_ArticlesSlider> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;
  
  final List<Map<String, String>> _mockArticles = [
    {'title': 'R3IDY - SPINDLE', 'snippet': 'Yamatai Records announce the return...'},
    {'title': 'THE FUTURE OF D&B', 'snippet': 'Exploring the underground sounds...'},
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
          curve: Curves.easeInOut
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
      height: 110, 
      child: PageView.builder(
        controller: _pageController, 
        itemCount: _mockArticles.length, 
        itemBuilder: (context, index) {
          final article = _mockArticles[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              Text(
                article['title']!, 
                style: GoogleFonts.teko(
                  fontSize: 18, 
                  fontWeight: FontWeight.w600, 
                  color: Colors.black
                ), 
                maxLines: 2, 
                overflow: TextOverflow.ellipsis
              ),
              const SizedBox(height: 4),
              Text(
                article['snippet']!, 
                style: GoogleFonts.archivo(
                  fontSize: 12, 
                  color: const Color(0xFF444444)
                ), 
                maxLines: 4, 
                overflow: TextOverflow.ellipsis
              ),
            ]
          );
        }
      )
    );
  }
}

class _JumpingChevron extends StatefulWidget {
  const _JumpingChevron({super.key});
  @override
  State<_JumpingChevron> createState() => _JumpingChevronState();
}

class _JumpingChevronState extends State<_JumpingChevron> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: -12.0).chain(CurveTween(curve: Curves.easeOut)), weight: 0.5 / 60),
      TweenSequenceItem(tween: Tween<double>(begin: -12.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 0.5 / 60),
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 59.0 / 60),
    ]).animate(_controller);
  }

  @override
  void dispose() { 
    _controller.dispose(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation, 
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value), 
          child: SizedBox(
            width: 32, 
            height: 20, 
            child: CustomPaint(painter: _ChevronPainter())
          )
        );
      }
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