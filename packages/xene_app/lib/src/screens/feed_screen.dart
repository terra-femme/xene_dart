import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/feed_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/xene_feed_card.dart';
import '../widgets/xene_content_modal.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  late ScrollController _scrollController;
  Timer? _crawlTimer;
  bool _isPaused = false;
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _startCrawl();
  }

  void _startCrawl() {
    _crawlTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_isPaused && _scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.offset;
        
        // Infinite loop logic: If we're past half way, we jump back to maintain the illusion
        // (Note: This assumes we duplicate the list items for a seamless loop)
        if (currentScroll >= maxScroll / 2) {
          _scrollController.jumpTo(0);
        } else {
          _scrollController.jumpTo(currentScroll + 0.7);
        }
      }
    });
  }

  void _pauseCrawl() {
    setState(() => _isPaused = true);
    _resumeTimer?.cancel();
  }

  void _resumeCrawl() {
    _resumeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _isPaused = false);
      }
    });
  }

  @override
  void dispose() {
    _crawlTimer?.cancel();
    _resumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedProvider);
    final viewWidth = MediaQuery.of(context).size.width;

    return Column(
      children: [
        // 1. "JUST DROPPED" Header
        Container(
          height: 80,
          width: double.infinity,
          alignment: Alignment.bottomRight,
          padding: const EdgeInsets.only(right: 16, bottom: 12),
          child: Text(
            'JUST DROPPED',
            style: GoogleFonts.teko(
              fontSize: (viewWidth * 0.08).clamp(32.0, 52.0),
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),

        // 2. Control Bar
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CHANNELS +',
                style: GoogleFonts.teko(
                  fontSize: 11,
                  color: const Color(0xFF888888),
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                'FILTER BY -',
                style: GoogleFonts.teko(
                  fontSize: 11,
                  color: const Color(0xFF888888),
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),

        // 3. The Crawl (Auto-Scroll Feed)
        Expanded(
          child: feedAsync.when(
            data: (items) {
              if (items.isEmpty) return const Center(child: Text('Empty feed'));
              
              // Duplicate items for seamless infinite scroll
              final duplicatedItems = [...items, ...items];
              
              return Listener(
                onPointerDown: (_) => _pauseCrawl(),
                onPointerUp: (_) => _resumeCrawl(),
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: duplicatedItems.length,
                  separatorBuilder: (context, index) {
                    final current = duplicatedItems[index];
                    final next = (index + 1 < duplicatedItems.length) 
                        ? duplicatedItems[index + 1] 
                        : null;
                    
                    // Show date divider if the date changes
                    if (next != null && 
                        DateFormat('MM.dd.yy').format(current.publishedAt) != 
                        DateFormat('MM.dd.yy').format(next.publishedAt)) {
                      return _DateDivider(date: next.publishedAt);
                    }
                    return const SizedBox(height: 2);
                  },
                  itemBuilder: (context, index) {
                    final item = duplicatedItems[index];
                    return XeneFeedCard(
                      item: item,
                      onTap: () {
                        ref.read(playerProvider.notifier).playTrack(item);
                        showXeneContent(context, item);
                      },
                    );
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFF5F5F5), thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              DateFormat('MM.dd.yy').format(date),
              style: GoogleFonts.teko(
                fontSize: 10,
                color: const Color(0xFFFF5500),
                letterSpacing: 2.0,
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFFF5F5F5), thickness: 1)),
        ],
      ),
    );
  }
}
