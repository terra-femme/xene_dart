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
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCrawl());
  }

  void _startCrawl() {
    _crawlTimer?.cancel();
    _crawlTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_isPaused && _scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.offset;
        
        if (maxScroll <= 0) return;
        
        if (currentScroll >= maxScroll / 2) {
          _scrollController.jumpTo(0);
        } else {
          _scrollController.jumpTo(currentScroll + 0.7);
        }
      }
    });
  }

  void _pauseCrawl() {
    if (!_isPaused) setState(() => _isPaused = true);
    _resumeTimer?.cancel();
  }

  void _resumeCrawl() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _isPaused = false);
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
    final size = MediaQuery.of(context).size;

    if (size.height < 150) return const SizedBox.shrink();

    return Column(
      children: [
        // 1. Header (Fixed Overflow)
        Container(
          height: 80,
          width: double.infinity,
          alignment: Alignment.bottomRight,
          padding: const EdgeInsets.only(right: 16, bottom: 12),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'JUST DROPPED',
              style: GoogleFonts.teko(
                fontSize: (size.width * 0.08).clamp(32.0, 52.0),
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
        ),
        // 2. Control Bar (Fixed Overflow)
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text('CHANNELS +', 
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.teko(fontSize: 11, color: const Color(0xFF888888)))),
              Flexible(
                child: Text('FILTER BY -', 
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.teko(fontSize: 11, color: const Color(0xFF888888)))),
            ],
          ),
        ),
        // 3. Feed
        Expanded(
          child: feedAsync.when(
            data: (items) {
              if (items.isEmpty) return const Center(child: Text('Empty feed'));
              
              // We duplicate items for the "infinite crawl" effect
              final duplicatedItems = [...items, ...items];
              
              return Listener(
                onPointerDown: (_) => _pauseCrawl(),
                onPointerUp: (_) => _resumeCrawl(),
                child: ListView.separated(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: duplicatedItems.length,
                  separatorBuilder: (context, index) {
                    final current = duplicatedItems[index];
                    final next = (index + 1 < duplicatedItems.length) 
                        ? duplicatedItems[index + 1] 
                        : null;
                    
                    if (next != null && current.publishedAt != null && next.publishedAt != null) {
                      if (DateFormat('MM.dd.yy').format(current.publishedAt!) != 
                          DateFormat('MM.dd.yy').format(next.publishedAt!)) {
                        return _DateDivider(
                          key: ValueKey('divider_${index}_${next.id}'),
                          date: next.publishedAt!
                        );
                      }
                    }
                    return const SizedBox(height: 2);
                  },
                  itemBuilder: (context, index) {
                    final item = duplicatedItems[index];
                    return XeneFeedCard(
                      // IMPORTANT: Unique key prevents "laid out exactly once" error
                      key: ValueKey('feed_card_${index}_${item.id}'),
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
  const _DateDivider({super.key, required this.date});
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