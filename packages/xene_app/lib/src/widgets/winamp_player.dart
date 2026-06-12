import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_media_item.dart';
import '../providers/accessibility_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/queue_provider.dart';
import '../providers/saved_provider.dart';
import '../providers/track_analysis_provider.dart';
import 'auth_gate_sheet.dart';
import 'soundcloud_embed_web.dart';
import 'track_visualizer.dart';
import 'youtube_embed_web.dart';

// Xene monochrome palette — platform colors appear only on tiny indicator dots.
const _teal = Color(0xFF00C5A5);
const _black = Colors.black;
const _gray = Color(0xFF888888);
const _lightGray = Color(0xFFAAAAAA);
const _border = Color(0xFFE0E0E0);
const _surface = Color(0xFFF5F5F5);
const _scOrange = Color(0xFFFF5500);
const _ytRed = Color(0xFFFF4444);

Color _platformDotColor(String platform) =>
    platform == 'youtube' ? _ytRed : _scOrange;

class WinampPlayer extends ConsumerStatefulWidget {
  const WinampPlayer({super.key});

  @override
  ConsumerState<WinampPlayer> createState() => _WinampPlayerState();
}

class _WinampPlayerState extends ConsumerState<WinampPlayer> {
  bool _isPlaying = false;
  bool _embedExpanded = true;

  void _startCurrentTrack() {
    final queue = ref.read(queueProvider);
    ref.read(queueProvider.notifier).logCurrentPlay();
    if (queue.currentItem?.platform.toLowerCase() == 'soundcloud') {
      unawaited(
        ref
            .read(queueProvider.notifier)
            .prepareSoundCloudPlaylist(startIndex: queue.currentIndex),
      );
    }
    setState(() => _isPlaying = true);
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(queueProvider);
    final current = queue.currentItem;
    final reduceMotion = ref.watch(accessibilityProvider).reduceMotion;

    // Live region: announce track changes to screen readers
    final _view = View.of(context);
    ref.listen(queueProvider.select((s) => s.currentItem), (prev, next) {
      if (next != null && next.id != prev?.id) {
        SemanticsService.sendAnnouncement(
          _view,
          "Now playing: ${next.title ?? 'Unknown track'} by ${next.artistName}",
          TextDirection.ltr,
        );
      }
    });

    // Fetch beat/amplitude analysis for the current SC track (null for other platforms)
    final analysisAsync =
        (current?.platform == 'soundcloud' && current?.trackId != null)
        ? ref.watch(
            trackAnalysisProvider((current!.platform, current.trackId!)),
          )
        : null;

    if (!queue.isLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
          ),
        ),
      );
    }

    if (queue.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('PLAYER'),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Your queue is empty.\nTap  ⊕  on any feed card to add tracks.',
                style: GoogleFonts.dmMono(
                  fontSize: 11,
                  color: _gray,
                  height: 1.7,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel('PLAYER'),
        const SizedBox(height: 10),

        // ── Now-playing card ──────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artwork + info
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ArtworkTile(url: current?.artworkUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current?.title ?? 'Unknown Track',
                          style: GoogleFonts.archivo(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          current?.artistName ?? '',
                          style: GoogleFonts.dmMono(fontSize: 10, color: _gray),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        if (current != null)
                          _PlatformChip(platform: current.platform),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Controls row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlBtn(
                    icon: Icons.skip_previous,
                    onTap: () {
                      ref.read(queueProvider.notifier).previous();
                      _startCurrentTrack();
                    },
                    enabled: queue.hasPrev,
                    semanticLabel: 'Previous track',
                  ),
                  const SizedBox(width: 10),
                  _PlayPauseBtn(
                    isPlaying: _isPlaying,
                    trackTitle: current?.title,
                    onTap: () {
                      if (_isPlaying) {
                        setState(() => _isPlaying = false);
                      } else {
                        _startCurrentTrack();
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  _ControlBtn(
                    icon: Icons.skip_next,
                    onTap: () {
                      ref.read(queueProvider.notifier).advance();
                      _startCurrentTrack();
                    },
                    enabled: queue.hasNext,
                    semanticLabel: 'Next track',
                  ),
                  const SizedBox(width: 18),
                  _ControlBtn(
                    icon: Icons.shuffle,
                    onTap: () =>
                        ref.read(queueProvider.notifier).toggleShuffle(),
                    enabled: true,
                    active: queue.isShuffle,
                    semanticLabel: queue.isShuffle
                        ? 'Shuffle on'
                        : 'Shuffle off',
                  ),
                  const Spacer(),
                  Semantics(
                    label: _embedExpanded
                        ? 'Hide player embed'
                        : 'Show player embed',
                    button: true,
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _embedExpanded = !_embedExpanded),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Text(
                            _embedExpanded ? 'HIDE' : 'SHOW',
                            style: GoogleFonts.dmMono(
                              fontSize: 9,
                              color: _lightGray,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Visualizer — data-driven when analysis is available
              if (current != null) ...[
                const SizedBox(height: 12),
                TrackVisualizerWidget(
                  analysis: analysisAsync?.valueOrNull,
                  playPositionStream: scPlayPositionStream,
                  isPlaying: _isPlaying,
                  durationMs: (current.durationSeconds ?? 0) * 1000,
                  reduceMotion: reduceMotion,
                  height: 36,
                ),
              ],

              // Embed
              if (_isPlaying && _embedExpanded && current != null) ...[
                const SizedBox(height: 12),
                Container(
                  height: current.platform == 'youtube' ? 200 : 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _border),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: _buildEmbed(current, queue),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Queue list ────────────────────────────────────────────────────
        _SectionLabel('QUEUE  (${queue.items.length})'),
        const SizedBox(height: 6),
        ...queue.items.asMap().entries.map(
          (e) => _QueueRow(
            item: e.value,
            index: e.key,
            isCurrent: e.key == queue.currentIndex,
            onTap: () {
              ref.read(queueProvider.notifier).setIndex(e.key);
              _startCurrentTrack();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmbed(QueueItem item, QueueState queue) {
    if (item.platform == 'youtube') {
      return YouTubeEmbed(
        key: ValueKey('youtube-${item.id}-${item.trackId ?? item.externalUrl}'),
        videoId: item.trackId ?? '',
        externalUrl: item.externalUrl,
      );
    }
    final scSource =
        queue.soundCloudPlaylistUrl ?? item.trackId ?? item.externalUrl;
    return SoundCloudEmbed(
      key: ValueKey('soundcloud-$scSource'),
      trackId: scSource,
    );
  }
}

// ── Queue row ──────────────────────────────────────────────────────────────

class _QueueRow extends ConsumerWidget {
  const _QueueRow({
    required this.item,
    required this.index,
    required this.isCurrent,
    required this.onTap,
  });

  final QueueItem item;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAnon = ref.watch(isAnonymousProvider);
    ref.watch(savedProvider);
    final isBookmarked =
        ref.read(savedProvider.notifier).matchForUrl(item.externalUrl) != null;

    final rowLabel = isCurrent
        ? '${item.title ?? 'Unknown'} by ${item.artistName ?? ''}, currently playing'
        : '${item.title ?? 'Unknown'} by ${item.artistName ?? ''}, position ${index + 1}';

    return Semantics(
      label: rowLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isCurrent ? _surface : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isCurrent ? _teal : _border,
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Position / playing indicator
              SizedBox(
                width: 18,
                child: isCurrent
                    ? const Icon(Icons.play_arrow, size: 14, color: _teal)
                    : Text(
                        '${index + 1}',
                        style: GoogleFonts.dmMono(
                          fontSize: 10,
                          color: _lightGray,
                        ),
                      ),
              ),
              const SizedBox(width: 8),

              // Tiny platform dot — decorative, excluded from semantics
              ExcludeSemantics(
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _platformDotColor(item.platform),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Track info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? 'Unknown',
                      style: GoogleFonts.archivo(
                        fontSize: 12,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: _black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.artistName != null)
                      Text(
                        item.artistName!,
                        style: GoogleFonts.dmMono(fontSize: 9, color: _gray),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Bookmark
              Semantics(
                label: isBookmarked ? 'Remove bookmark' : 'Bookmark track',
                button: true,
                child: GestureDetector(
                  onTap: () {
                    if (isAnon) {
                      showAuthGate(context, featureHint: 'to save tracks');
                      return;
                    }
                    final match = ref
                        .read(savedProvider.notifier)
                        .matchForUrl(item.externalUrl);
                    if (match != null) {
                      ref.read(savedProvider.notifier).unbookmark(match.id);
                    } else {
                      ref.read(savedProvider.notifier).bookmark(item);
                    }
                  },
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      size: 16,
                      color: isBookmarked ? _teal : _border,
                    ),
                  ),
                ),
              ),

              // Remove
              Semantics(
                label: 'Remove from queue',
                button: true,
                child: GestureDetector(
                  onTap: () =>
                      ref.read(queueProvider.notifier).removeItem(item.id),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.close, size: 14, color: _lightGray),
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

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _ArtworkTile extends StatelessWidget {
  const _ArtworkTile({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url!,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
    width: 72,
    height: 72,
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _border),
    ),
    child: const Icon(Icons.music_note, color: _lightGray, size: 28),
  );
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.platform});
  final String platform;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        platform.toUpperCase(),
        style: GoogleFonts.dmMono(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: _gray,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  const _ControlBtn({
    required this.icon,
    required this.onTap,
    required this.enabled,
    this.active = false,
    this.semanticLabel,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final bool active;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? _teal
        : enabled
        ? const Color(0xFF333333)
        : _border;
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}

class _PlayPauseBtn extends StatelessWidget {
  const _PlayPauseBtn({
    required this.isPlaying,
    required this.onTap,
    this.trackTitle,
  });
  final bool isPlaying;
  final VoidCallback onTap;
  final String? trackTitle;

  @override
  Widget build(BuildContext context) {
    final label = isPlaying
        ? 'Pause'
        : (trackTitle != null ? 'Play $trackTitle' : 'Play');
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
          child: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        label,
        style: GoogleFonts.dmMono(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFBBBBBB),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
