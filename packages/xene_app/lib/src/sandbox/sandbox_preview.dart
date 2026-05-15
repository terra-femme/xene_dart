import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'channel_dial.dart';
import 'channel_models.dart';
import 'channel_feed_wrapper.dart';

class SandboxPreview extends ConsumerWidget {
  const SandboxPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeChannel = ref.watch(activeChannelProvider);

    return Scaffold(
      backgroundColor: Colors.white, // Back to static white
      body: Stack(
        children: [
          // MAIN LAYOUT
          Row(
            children: [
              // 1. Sidebar Simulator
              Container(
                width: 160,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.black.withOpacity(0.05))),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        const ChannelDial(),
                      ],                  ),
                ),
              ),

              // 2. Feed Simulator
              Expanded(
                child: ChannelFeedWrapper(
                  builder: (channel) {
                    return ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: channel.mockArtists.length,
                      itemBuilder: (context, index) {
                        return _MockCard(
                          artist: channel.mockArtists[index],
                          channel: channel.name,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),

          // DEBUG OVERLAY
          Positioned(
            top: 40,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'MECHANICAL DIAL v2',
                    style: GoogleFonts.dmMono(color: Colors.greenAccent, fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PRESET: ${activeChannel.name}',
                    style: GoogleFonts.dmMono(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MockCard extends StatelessWidget {
  const _MockCard({required this.artist, required this.channel});
  final String artist;
  final String channel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF222222), // Hardware Black
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            ),
            child: const Icon(Icons.music_note, color: Colors.white24, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.archivo(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                Text(
                  'CURATED FOR $channel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.teko(
                    color: Colors.black38,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
