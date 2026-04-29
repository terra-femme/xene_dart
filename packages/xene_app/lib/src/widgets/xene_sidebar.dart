import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class XeneSidebar extends StatelessWidget {
  const XeneSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.30;
    final clampedWidth = width.clamp(180.0, 210.0);

    return Container(
      width: clampedWidth,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
      ),
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 15),
          
          // 1. The XENE Logo (Crucial Breaking Logic)
          SizedBox(
            width: 191,
            height: 160,
            child: Text(
              'XE\nNE',
              style: GoogleFonts.jaro(
                fontSize: 210,
                height: 0.60, // Even tighter stacking: from 0.65 to 0.60
                letterSpacing: -0.06 * 210, // Closer horizontally: from -0.04 to -0.06
                color: Colors.black,
              ),
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),

          const SizedBox(height: 120), // Significantly moved Nav down: from 40 to 120

          // 2. Primary Nav Frame (ARTIST/NETWORK)
          SizedBox(
            height: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NavText(label: 'ARTIST', fontSize: 48, height: 0.8),
                const SizedBox(height: -8), // Negative overlap
                _NavText(label: 'NETWORK', fontSize: 48, height: 1.0),
              ],
            ),
          ),

          const SizedBox(height: 60), // Adjusted from 100 to 60 to fit everything

          // 3. Articles Frame
          const SizedBox(
            width: 161,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ARTICLES',
                  style: TextStyle(
                    fontFamily: 'Teko',
                    fontSize: 12,
                    color: Color(0xFF666666),
                    letterSpacing: 1.44, // 0.12 * 12
                    height: 1.66, // height: 20px / 12px
                  ),
                ),
                SizedBox(height: 4),
                _ArticlesSlider(),
              ],
            ),
          ),

          const Spacer(),

          // 4. Fresh Feed Frame & Jumping Chevron
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  height: 80,
                  child: Text(
                    'FRESH\nFEED',
                    style: TextStyle(
                      fontFamily: 'Teko',
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                // Debugging container to find the chevron
                Container(
                  color: Colors.red.withOpacity(0.1), 
                  child: const _JumpingChevron(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavText extends StatelessWidget {
  const _NavText({
    required this.label,
    required this.fontSize,
    required this.height,
  });

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
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _ArticlesSlider extends StatefulWidget {
  const _ArticlesSlider();

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
      'snippet': 'Yamatai Records announce the return of core member and staple artist R3IDY with his debut release for 2025...',
    },
    {
      'title': 'THE FUTURE OF D&B',
      'snippet': 'Exploring the underground sounds that are shaping the next decade of drum and bass culture...',
    },
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentPage < _mockArticles.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      if (_pageController.hasClients) {
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
                  color: Colors.black,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                article['snippet']!,
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

class _JumpingChevron extends StatefulWidget {
  const _JumpingChevron();

  @override
  State<_JumpingChevron> createState() => _JumpingChevronState();
}

class _JumpingChevronState extends State<_JumpingChevron> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // Mandate: 60-second loop animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();

    _animation = TweenSequence<double>([
      // Step 1: 0ms to 500ms: Jump from 0 to -12
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -12.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 0.5 / 60,
      ),
      // Step 2: 500ms to 1000ms: Return to 0
      TweenSequenceItem(
        tween: Tween<double>(begin: -12.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 0.5 / 60,
      ),
      // Step 3: 1000ms to 1500ms: Jump from 0 to -6
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -6.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 0.5 / 60,
      ),
      // Step 4: 1500ms to 2000ms: Return to 0
      TweenSequenceItem(
        tween: Tween<double>(begin: -6.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 0.5 / 60,
      ),
      // Wait: 2000ms to 60000ms: no-op (Stay at Y: 0)
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: 58.0 / 60,
      ),
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
            child: CustomPaint(
              painter: _ChevronPainter(),
            ),
          ),
        );
      },
    );
  }
}

class _ChevronPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 // Mandate: strokeWidth 3
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
