import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MagazineHero extends StatefulWidget {
  const MagazineHero({super.key});

  @override
  State<MagazineHero> createState() => _MagazineHeroState();
}

class _MagazineHeroState extends State<MagazineHero> {
  late PageController _pageController;
  int _activeIndex = 0;
  Timer? _timer;

  // Mock articles for scaffolding (replaces articles state in Feed.jsx)
  final List<Map<String, String>> _articles = [
    {
      'title': 'The Future of Underground D&B',
      'imageUrl': 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=1000',
    },
    {
      'title': 'Xene: New Platform Features',
      'imageUrl': 'https://images.unsplash.com/photo-1493225255756-d9584f8606e9?auto=format&fit=crop&q=80&w=1000',
    },
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _syncWithHour();
    
    // ELI5: Every minute, we check if the hour changed to update the "Billboard."
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _syncWithHour();
    });
  }

  void _syncWithHour() {
    if (_articles.isEmpty) return;
    final hourIndex = DateTime.now().hour % _articles.length;
    if (hourIndex != _activeIndex) {
      setState(() {
        _activeIndex = hourIndex;
      });
      _pageController.animateToPage(
        hourIndex,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_articles.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 300,
      child: Stack(
        children: [
          // 1. The Sliding Posters
          PageView.builder(
            controller: _pageController,
            itemCount: _articles.length,
            onPageChanged: (index) => setState(() => _activeIndex = index),
            itemBuilder: (context, index) {
              final article = _articles[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: article['imageUrl']!,
                    fit: BoxFit.cover,
                  ),
                  // Dark gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color.fromARGB(204, 0, 0, 0),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // 2. The Text Overlay
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FEATURED',
                  style: TextStyle(
                    color: Color(0xFFFF5500),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _articles[_activeIndex]['title']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // 3. Page Indicators (Small dots)
          Positioned(
            bottom: 15,
            right: 20,
            child: Row(
              children: List.generate(_articles.length, (index) {
                return Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _activeIndex == index
                        ? const Color(0xFFFF5500)
                        : const Color.fromARGB(76, 255, 255, 255),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
