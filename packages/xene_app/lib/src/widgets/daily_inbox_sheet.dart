import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xene_domain/xene_domain.dart';

import '../providers/auth_provider.dart';
import '../providers/daily_inbox_provider.dart';
import '../providers/dio_provider.dart';
import '../theme/xene_theme.dart';
import 'auth_gate_sheet.dart';

void showDailyInbox(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _DailyInboxSheet(),
  );
}

// ── Sheet root ────────────────────────────────────────────────────────────────

class _DailyInboxSheet extends ConsumerWidget {
  const _DailyInboxSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxAsync = ref.watch(dailyInboxProvider);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 40,
              height: 3,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Sheet header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Text(
                  'DAILY DIGEST',
                  style: GoogleFonts.teko(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                    color: Colors.black,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.close,
                    size: 20,
                    color: XeneTheme.muted,
                  ),
                ),
              ],
            ),
          ),

          inboxAsync.when(
            loading: () => const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: XeneTheme.teal,
                ),
              ),
            ),
            error: (_, __) => Expanded(
              child: Center(
                child: Text(
                  'Could not load today\'s digest',
                  style: GoogleFonts.teko(color: XeneTheme.muted, fontSize: 16),
                ),
              ),
            ),
            data: (msg) {
              if (msg == null) {
                return Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.inbox_outlined,
                          size: 40,
                          color: XeneTheme.mutedLight,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nothing dropped yet today',
                          style: GoogleFonts.teko(
                            color: XeneTheme.muted,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Check back later',
                          style: GoogleFonts.dmMono(
                            color: XeneTheme.mutedLight,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Expanded(child: _InboxBody(msg: msg));
            },
          ),
        ],
      ),
    );
  }
}

// ── Body with urgency banner + station list ───────────────────────────────────

class _InboxBody extends StatefulWidget {
  const _InboxBody({required this.msg});
  final DailyInboxMessage msg;

  @override
  State<_InboxBody> createState() => _InboxBodyState();
}

class _InboxBodyState extends State<_InboxBody> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.msg.timeRemaining;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _remaining = widget.msg.timeRemaining);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _formatRemaining(Duration d) {
    if (d == Duration.zero) return 'Expired';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Urgency banner
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFFCC80), width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: XeneTheme.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      color: const Color(0xFF7B3F00),
                      height: 1.5,
                    ),
                    children: [
                      TextSpan(
                        text: 'Expires in ${_formatRemaining(_remaining)}. ',
                        style: GoogleFonts.dmMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: XeneTheme.warning,
                        ),
                      ),
                      const TextSpan(
                        text:
                            'This roundup is only available for 24 hours — browse, save, and show the tracks some love on the platform before it\'s gone.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Station list + beta footer
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: widget.msg.stations.length + 1,
            itemBuilder: (context, i) {
              if (i < widget.msg.stations.length) {
                return _StationSection(station: widget.msg.stations[i]);
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  '[check the feed to ensure the list didn\'t miss any on your radar - if it did, submit the issue as a bug and we\'ll get right on it!]',
                  style: GoogleFonts.dmMono(
                    fontSize: 10,
                    color: XeneTheme.mutedLight,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Station section ───────────────────────────────────────────────────────────

class _StationSection extends StatelessWidget {
  const _StationSection({required this.station});
  final DailyInboxStation station;

  Color _parseColor(String hex) {
    try {
      final cleaned = hex.replaceAll('#', '');
      return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {
      return XeneTheme.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(station.themeColor);
    final trackCount = station.tracks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Station header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                station.name,
                style: GoogleFonts.teko(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.4,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$trackCount new',
                style: GoogleFonts.dmMono(
                  fontSize: 10,
                  color: XeneTheme.mutedLight,
                ),
              ),
            ],
          ),
        ),

        // Track list
        ...station.tracks.map(
          (track) => _TrackRow(track: track, stationColor: color),
        ),

        Divider(
          height: 1,
          thickness: 1,
          indent: 16,
          endIndent: 16,
          color: XeneTheme.borderLight,
        ),
      ],
    );
  }
}

// ── Track row ─────────────────────────────────────────────────────────────────

class _TrackRow extends ConsumerStatefulWidget {
  const _TrackRow({required this.track, required this.stationColor});
  final DailyInboxTrack track;
  final Color stationColor;

  @override
  ConsumerState<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends ConsumerState<_TrackRow> {
  bool _saving = false;
  bool _saved = false;

  Future<void> _save() async {
    final isAnon = ref.read(isAnonymousProvider);
    if (isAnon) {
      if (mounted) {
        showAuthGate(
          context,
          featureHint: 'to save tracks from the daily digest',
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final dio = ref.read(authenticatedDioProvider);
      await dio.post(
        '/user/saved',
        data: {
          'platform': widget.track.platform,
          'external_url': widget.track.externalUrl,
          'title': widget.track.title,
          'artist_name': widget.track.artistName,
          'artwork_url': widget.track.artworkUrl,
          'duration_seconds': widget.track.durationSeconds,
        },
      );
      if (mounted) setState(() => _saved = true);
    } catch (_) {
      // Already saved or network error — treat as saved
      if (mounted) setState(() => _saved = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(widget.track.externalUrl);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Artwork thumbnail
          if (track.artworkUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: track.artworkUrl!,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _artworkPlaceholder(),
              ),
            )
          else
            _artworkPlaceholder(),

          const SizedBox(width: 10),

          // Text + actions
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Artist name
                Text(
                  track.artistName,
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                // Track title
                Text(
                  track.title,
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: XeneTheme.textDark,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                // Duration + actions row
                Row(
                  children: [
                    if (track.durationLabel.isNotEmpty) ...[
                      Text(
                        track.durationLabel,
                        style: GoogleFonts.dmMono(
                          fontSize: 10,
                          color: XeneTheme.mutedLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Save button (SC + YT only)
                    if (track.isSaveable)
                      _ActionChip(
                        label: _saved ? 'SAVED' : 'SAVE',
                        icon: _saved ? Icons.bookmark : Icons.bookmark_border,
                        color: _saved ? XeneTheme.teal : XeneTheme.muted,
                        onTap: _saving || _saved ? null : _save,
                      ),
                    const SizedBox(width: 6),
                    // Open on platform
                    _ActionChip(
                      label: 'OPEN',
                      icon: Icons.open_in_new,
                      color: widget.stationColor,
                      onTap: _open,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _artworkPlaceholder() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: XeneTheme.surface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(
        Icons.music_note,
        size: 18,
        color: XeneTheme.mutedLight,
      ),
    );
  }
}

// ── Small action chip ─────────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: GoogleFonts.dmMono(
                  fontSize: 9,
                  color: color,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
