import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xene_domain/xene_domain.dart';
import '../providers/game_provider.dart';
import '../providers/soundcloud_connection_provider.dart';
import '../widgets/soundcloud_embed.dart';

class PartyScreen extends ConsumerStatefulWidget {
  const PartyScreen({super.key, required this.partyId});
  final String partyId;

  @override
  ConsumerState<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends ConsumerState<PartyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(partyDetailProvider(widget.partyId));

    final partyName = detailAsync.valueOrNull?.name.toUpperCase() ?? 'PARTY';

    return Column(
      children: [
        // Party name + invite button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  partyName,
                  style: GoogleFonts.teko(
                    fontSize: 24,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (detailAsync.valueOrNull != null) ...[
                _InviteButton(party: detailAsync.value!),
                const SizedBox(width: 16),
                _LeaveButton(partyId: widget.partyId),
              ],
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: Colors.black,
          unselectedLabelColor: const Color(0xFFA3A3A3),
          indicatorColor: Colors.black,
          indicatorWeight: 1.5,
          labelStyle: GoogleFonts.teko(fontSize: 15, letterSpacing: 0.8),
          tabs: const [
            Tab(text: 'THIS WEEK'),
            Tab(text: 'LEADERBOARD'),
            Tab(text: 'ARCHIVE'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _WeeklyTracksTab(partyId: widget.partyId),
              _LeaderboardTab(partyId: widget.partyId),
              _ArchiveTab(partyId: widget.partyId),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Invite button ─────────────────────────────────────────────────────────────

class _InviteButton extends StatelessWidget {
  const _InviteButton({required this.party});
  final PartyDetail party;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showInviteSheet(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'INVITE',
            style: GoogleFonts.teko(
              fontSize: 14,
              letterSpacing: 0.5,
              color: const Color(0xFFA3A3A3),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.share, size: 15, color: Color(0xFFA3A3A3)),
        ],
      ),
    );
  }

  void _showInviteSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _InviteSheet(party: party),
    );
  }
}

// ── Leave button ─────────────────────────────────────────────────────────────

class _LeaveButton extends ConsumerWidget {
  const _LeaveButton({required this.partyId});
  final String partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _confirmLeave(context, ref),
      child: Text(
        'LEAVE',
        style: GoogleFonts.teko(
          fontSize: 14,
          letterSpacing: 0.5,
          color: const Color(0xFFD32F2F),
        ),
      ),
    );
  }

  void _confirmLeave(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Leave party?', style: GoogleFonts.teko(fontSize: 20)),
        content: Text(
          'You can rejoin anytime with the invite code.',
          style: GoogleFonts.dmMono(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('CANCEL', style: GoogleFonts.teko(color: Colors.black)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(gamePartiesProvider.notifier).leaveParty(partyId);
              if (context.mounted) context.go('/game');
            },
            child: Text(
              'LEAVE',
              style: GoogleFonts.teko(color: const Color(0xFFD32F2F)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Invite sheet ──────────────────────────────────────────────────────────────

class _InviteSheet extends StatelessWidget {
  const _InviteSheet({required this.party});
  final PartyDetail party;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'INVITE TO ${party.name.toUpperCase()}',
            style: GoogleFonts.teko(fontSize: 20, letterSpacing: 1),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              party.inviteCode,
              style: GoogleFonts.dmMono(fontSize: 36, letterSpacing: 8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share this code — anyone can enter it to join',
            style: GoogleFonts.dmMono(
              fontSize: 11,
              color: const Color(0xFFA3A3A3),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _SheetButton(
                  label: 'COPY CODE',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: party.inviteCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SheetButton(
                  label: 'COPY LINK',
                  outlined: true,
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(
                        text: 'https://xene.app/join/${party.inviteCode}',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Weekly tracks tab ─────────────────────────────────────────────────────────

// StateProviders so _WeeklyTracksTab stays a ConsumerWidget (avoids widget-type
// reconciliation issues on Flutter web when switching between widget base classes).
final _weeklyFlatViewProvider = StateProvider.family.autoDispose<bool, String>(
  (_, __) => false,
);
final _weeklyExportingProvider = StateProvider.family.autoDispose<bool, String>(
  (_, __) => false,
);
final _archiveExportingProvider = StateProvider.family
    .autoDispose<bool, (String, String)>((_, __) => false);

String _soundCloudExportErrorMessage(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'] as String?;
      final serverMsg = data['error'] as String?;
      return detail ?? serverMsg ?? 'HTTP ${e.response?.statusCode}';
    }
    if (data != null) return data.toString();
    return e.message ?? 'HTTP ${e.response?.statusCode}';
  }
  return 'Could not create playlist, try again';
}

class _WeeklyTracksTab extends ConsumerWidget {
  const _WeeklyTracksTab({required this.partyId});
  final String partyId;

  Future<void> _exportToSc(
    BuildContext context,
    WidgetRef ref,
    String weekStart,
  ) async {
    final scState = ref.read(soundcloudConnectionProvider);
    if (!scState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect your SoundCloud account first')),
      );
      return;
    }
    ref.read(_weeklyExportingProvider(partyId).notifier).state = true;
    try {
      final url = await ref
          .read(weeklyTracksProvider(partyId).notifier)
          .exportToScPlaylist(weekStart);
      if (!context.mounted) return;
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!context.mounted) return;
      final msg = _soundCloudExportErrorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      ref.read(_weeklyExportingProvider(partyId).notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(weeklyTracksProvider(partyId));
    final votesAsync = ref.watch(weekVotesProvider(partyId));
    final showFlat = ref.watch(_weeklyFlatViewProvider(partyId));
    final exporting = ref.watch(_weeklyExportingProvider(partyId));

    return tracksAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(
        child: Text(
          'Failed to load tracks',
          style: GoogleFonts.dmMono(color: const Color(0xFFA3A3A3)),
        ),
      ),
      data: (state) {
        final votes = votesAsync.valueOrNull;
        final tally = votes?.tally;
        final notifier = ref.read(weeklyTracksProvider(partyId).notifier);
        final allTracks = state.memberTracks
            .expand((mt) => mt.tracks.map((t) => (member: mt.member, track: t)))
            .toList();

        return Column(
          children: [
            _WeekStatusBar(state: state, votes: votes),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  _ViewToggleButton(
                    label: 'BY MEMBER',
                    active: !showFlat,
                    onTap: () =>
                        ref
                                .read(_weeklyFlatViewProvider(partyId).notifier)
                                .state =
                            false,
                  ),
                  const SizedBox(width: 16),
                  _ViewToggleButton(
                    label: 'ALL TRACKS',
                    active: showFlat,
                    onTap: () =>
                        ref
                                .read(_weeklyFlatViewProvider(partyId).notifier)
                                .state =
                            true,
                  ),
                  const Spacer(),
                  if (showFlat && allTracks.isNotEmpty)
                    exporting
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFFFF5500),
                            ),
                          )
                        : GestureDetector(
                            onTap: () =>
                                _exportToSc(context, ref, state.weekStart),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.queue_music,
                                  size: 14,
                                  color: Color(0xFFFF5500),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'SC PLAYLIST',
                                  style: GoogleFonts.teko(
                                    fontSize: 13,
                                    letterSpacing: 0.5,
                                    color: const Color(0xFFFF5500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: showFlat
                  ? allTracks.isEmpty
                        ? Center(
                            child: Text(
                              'No tracks this week',
                              style: GoogleFonts.dmMono(
                                color: const Color(0xFFA3A3A3),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            itemCount: allTracks.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox.shrink(),
                            itemBuilder: (_, i) {
                              final item = allTracks[i];
                              return _TrackRow(
                                track: item.track,
                                isOwner: item.member.isMe,
                                isWeekClosed: state.isWeekClosed,
                                memberUsername: item.member.username,
                                onDelete: () =>
                                    notifier.deleteTrack(item.track.id),
                              );
                            },
                          )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      itemCount: state.memberTracks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (_, i) {
                        final mt = state.memberTracks[i];
                        return _MemberSection(
                          partyId: partyId,
                          memberTracks: mt,
                          weekStart: state.weekStart,
                          isWeekClosed: state.isWeekClosed,
                          isCurrentWeek: state.isCurrentWeek,
                          isResultsVisible: state.isResultsVisible,
                          voteCount: tally?[mt.member.userId],
                          notifier: notifier,
                        );
                      },
                    ),
            ),
            if (!state.isWeekClosed)
              _VoteBar(
                partyId: partyId,
                state: state,
                votes: votes,
                votesNotifier: ref.read(weekVotesProvider(partyId).notifier),
              ),
          ],
        );
      },
    );
  }
}

// ── Week status bar ───────────────────────────────────────────────────────────

class _WeekStatusBar extends StatefulWidget {
  const _WeekStatusBar({required this.state, this.votes});
  final WeeklyTracksState state;
  final WeekVotes? votes;

  @override
  State<_WeekStatusBar> createState() => _WeekStatusBarState();
}

class _WeekStatusBarState extends State<_WeekStatusBar> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    if (!mounted) return;
    final deadline = _fridayDeadline(widget.state.weekStart);
    final now = DateTime.now().toUtc();
    setState(() {
      _remaining = now.isBefore(deadline)
          ? deadline.difference(now)
          : Duration.zero;
    });
  }

  DateTime _fridayDeadline(String weekStart) {
    final parts = weekStart.split('-');
    final monday = DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final friday = monday.add(const Duration(days: 4));
    return DateTime.utc(friday.year, friday.month, friday.day, 21);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final votes = widget.votes;
    final memberCount = widget.state.memberTracks.length;
    final voteCount = votes?.totalVoters ?? 0;

    if (widget.state.isResultsVisible) {
      return Container(
        color: const Color(0xFFF5F5F5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(
          'RESULTS — WEEK OF ${widget.state.weekStart}',
          style: GoogleFonts.teko(
            fontSize: 13,
            letterSpacing: 1,
            color: Colors.black,
          ),
        ),
      );
    }

    if (widget.state.isWeekClosed) {
      return Container(
        color: const Color(0xFFF5F5F5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(
          'VOTING CLOSED — RESULTS REVEAL IN 5 MIN',
          style: GoogleFonts.teko(
            fontSize: 13,
            letterSpacing: 1,
            color: const Color(0xFFA3A3A3),
          ),
        ),
      );
    }

    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60);
    final s = _remaining.inSeconds.remainder(60);
    final countdown =
        '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';

    return Container(
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'CLOSES $countdown',
              style: GoogleFonts.teko(fontSize: 13, letterSpacing: 1),
            ),
          ),
          Text(
            '$voteCount / $memberCount voted',
            style: GoogleFonts.dmMono(
              fontSize: 11,
              color: const Color(0xFFA3A3A3),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Member section ────────────────────────────────────────────────────────────

class _MemberSection extends StatelessWidget {
  const _MemberSection({
    required this.partyId,
    required this.memberTracks,
    required this.weekStart,
    required this.isWeekClosed,
    required this.notifier,
    this.isCurrentWeek = false,
    this.isResultsVisible = false,
    this.voteCount,
  });

  final String partyId;
  final MemberTracks memberTracks;
  final String weekStart;
  final bool isWeekClosed;
  final bool isCurrentWeek;
  final WeeklyTracksNotifier notifier;
  final bool isResultsVisible;
  final int? voteCount;

  @override
  Widget build(BuildContext context) {
    final member = memberTracks.member;
    final tracks = memberTracks.tracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              member.username.toUpperCase(),
              style: GoogleFonts.teko(
                fontSize: 16,
                letterSpacing: 0.5,
                color: member.isMe ? Colors.black : const Color(0xFF555555),
                fontWeight: member.isMe ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (member.isMe)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '(you)',
                  style: GoogleFonts.dmMono(
                    fontSize: 10,
                    color: const Color(0xFFA3A3A3),
                  ),
                ),
              ),
            const Spacer(),
            if (isResultsVisible && voteCount != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '$voteCount ${voteCount == 1 ? 'vote' : 'votes'}',
                  style: GoogleFonts.teko(
                    fontSize: 15,
                    color: voteCount! > 0
                        ? const Color(0xFFFF5500)
                        : const Color(0xFFA3A3A3),
                  ),
                ),
              ),
            Text(
              '${tracks.length}/5',
              style: GoogleFonts.teko(
                fontSize: 15,
                color: const Color(0xFFA3A3A3),
              ),
            ),
            if (member.isMe && isCurrentWeek && tracks.length < 5) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showSubmitSheet(context),
                child: Text(
                  '+ ADD',
                  style: GoogleFonts.teko(
                    fontSize: 14,
                    color: Colors.black,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.black,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (tracks.isEmpty)
          Text(
            'No tracks submitted this week',
            style: GoogleFonts.dmMono(
              fontSize: 11,
              color: const Color(0xFFA3A3A3),
            ),
          )
        else
          ...tracks.map(
            (t) => _TrackRow(
              track: t,
              isOwner: member.isMe,
              isWeekClosed: isWeekClosed,
              onDelete: () => notifier.deleteTrack(t.id),
            ),
          ),
      ],
    );
  }

  void _showSubmitSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TrackSubmitSheet(
        partyId: partyId,
        slotsUsed: memberTracks.tracks.length,
        notifier: notifier,
      ),
    );
  }
}

// ── Track row ─────────────────────────────────────────────────────────────────

class _TrackRow extends StatefulWidget {
  const _TrackRow({
    required this.track,
    required this.isOwner,
    required this.isWeekClosed,
    required this.onDelete,
    this.memberUsername,
  });

  final PartyTrack track;
  final bool isOwner;
  final bool isWeekClosed;
  final VoidCallback onDelete;
  final String? memberUsername;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                if (t.scArtworkUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: CachedNetworkImage(
                      imageUrl: t.scArtworkUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          const _ArtworkPlaceholder(size: 40),
                    ),
                  )
                else
                  const _ArtworkPlaceholder(size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.scTitle,
                        style: GoogleFonts.dmMono(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.memberUsername != null ||
                          t.scDurationSeconds != null)
                        Text(
                          [
                            if (widget.memberUsername != null)
                              widget.memberUsername!,
                            if (t.scDurationSeconds != null)
                              _durationLabel(t.scDurationSeconds!),
                          ].join(' · '),
                          style: GoogleFonts.dmMono(
                            fontSize: 10,
                            color: const Color(0xFFA3A3A3),
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.isOwner && !widget.isWeekClosed)
                  GestureDetector(
                    onTap: widget.onDelete,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: Color(0xFFA3A3A3),
                      ),
                    ),
                  ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: const Color(0xFFA3A3A3),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 140,
              child: SoundCloudEmbed(trackId: t.scTrackId, isVisual: false),
            ),
          ),
        const Divider(height: 1, color: Color(0xFFF0F0F0)),
      ],
    );
  }

  String _durationLabel(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFF0F0F0),
      child: const Icon(Icons.music_note, size: 18, color: Color(0xFFA3A3A3)),
    );
  }
}

// ── Vote bar ──────────────────────────────────────────────────────────────────

class _VoteBar extends StatelessWidget {
  const _VoteBar({
    required this.partyId,
    required this.state,
    required this.votes,
    required this.votesNotifier,
  });

  final String partyId;
  final WeeklyTracksState state;
  final WeekVotes? votes;
  final WeekVotesNotifier votesNotifier;

  @override
  Widget build(BuildContext context) {
    final alreadyVoted = votes?.myVote != null;
    final hasMyTracks = state.memberTracks.any(
      (mt) => mt.member.isMe && mt.tracks.isNotEmpty,
    );

    if (alreadyVoted) {
      return Container(
        color: const Color(0xFFF5F5F5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Text(
          'YOUR VOTE IS IN — RESULTS FRIDAY 9:05 PM UTC',
          style: GoogleFonts.teko(
            fontSize: 13,
            letterSpacing: 1,
            color: const Color(0xFF4CAF50),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasMyTracks)
            Text(
              'Submit at least 1 track to unlock voting',
              style: GoogleFonts.dmMono(
                fontSize: 11,
                color: const Color(0xFFA3A3A3),
              ),
            )
          else
            GestureDetector(
              onTap: () => _showVoteSheet(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  'CAST YOUR VOTE',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.teko(
                    fontSize: 17,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showVoteSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _VoteSheet(state: state, notifier: votesNotifier),
    );
  }
}

// ── Vote sheet ────────────────────────────────────────────────────────────────

class _VoteSheet extends StatefulWidget {
  const _VoteSheet({required this.state, required this.notifier});
  final WeeklyTracksState state;
  final WeekVotesNotifier notifier;

  @override
  State<_VoteSheet> createState() => _VoteSheetState();
}

class _VoteSheetState extends State<_VoteSheet> {
  String? _selectedUserId;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_selectedUserId == null) {
      setState(() => _error = 'Pick someone to vote for');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.notifier.castVote(_selectedUserId!);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not cast vote, try again';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final others = widget.state.memberTracks
        .where((mt) => !mt.member.isMe)
        .toList();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VOTE FOR BEST SET',
            style: GoogleFonts.teko(fontSize: 22, letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          Text(
            'Who submitted the strongest tracks this week?',
            style: GoogleFonts.dmMono(
              fontSize: 11,
              color: const Color(0xFFA3A3A3),
            ),
          ),
          const SizedBox(height: 16),
          ...others.map((mt) {
            final selected = _selectedUserId == mt.member.userId;
            return GestureDetector(
              onTap: () => setState(() => _selectedUserId = mt.member.userId),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? Colors.black : const Color(0xFFE5E5E5),
                    width: selected ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mt.member.username.toUpperCase(),
                            style: GoogleFonts.teko(
                              fontSize: 18,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '${mt.tracks.length} track${mt.tracks.length == 1 ? '' : 's'}',
                            style: GoogleFonts.dmMono(
                              fontSize: 10,
                              color: const Color(0xFFA3A3A3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.check_circle,
                        size: 18,
                        color: Colors.black,
                      ),
                  ],
                ),
              ),
            );
          }),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: GoogleFonts.dmMono(
                fontSize: 11,
                color: const Color(0xFFD32F2F),
              ),
            ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _loading ? null : _submit,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _loading || _selectedUserId == null
                    ? const Color(0xFFA3A3A3)
                    : Colors.black,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _loading ? 'SUBMITTING...' : 'CONFIRM VOTE',
                textAlign: TextAlign.center,
                style: GoogleFonts.teko(
                  fontSize: 17,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Track submit sheet ────────────────────────────────────────────────────────

class _TrackSubmitSheet extends ConsumerStatefulWidget {
  const _TrackSubmitSheet({
    required this.partyId,
    required this.slotsUsed,
    required this.notifier,
  });
  final String partyId;
  final int slotsUsed;
  final WeeklyTracksNotifier notifier;

  @override
  ConsumerState<_TrackSubmitSheet> createState() => _TrackSubmitSheetState();
}

class _TrackSubmitSheetState extends ConsumerState<_TrackSubmitSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  ScTrackResult? _selected;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.notifier.submitTrack({
        'sc_track_id': _selected!.id,
        'sc_track_url': _selected!.permalinkUrl,
        'sc_title': _selected!.title,
        'sc_artwork_url': _selected!.artworkUrl,
        'sc_duration_seconds': _selected!.durationSeconds,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not add track, try again';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchAsync = _query.trim().length >= 2
        ? ref.watch(scTrackSearchProvider(_query.trim()))
        : null;

    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final slotsLeft = 5 - widget.slotsUsed;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ADD A TRACK',
                style: GoogleFonts.teko(fontSize: 20, letterSpacing: 1),
              ),
              const Spacer(),
              Text(
                '$slotsLeft slot${slotsLeft == 1 ? '' : 's'} left',
                style: GoogleFonts.dmMono(
                  fontSize: 11,
                  color: const Color(0xFFA3A3A3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            style: GoogleFonts.dmMono(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search SoundCloud tracks...',
              hintStyle: GoogleFonts.dmMono(
                fontSize: 12,
                color: const Color(0xFFA3A3A3),
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE5E5E5)),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.black),
              ),
            ),
            onChanged: (v) {
              if (v.trim().length >= 2) {
                setState(() => _query = v.trim());
              }
            },
          ),
          const SizedBox(height: 8),
          if (searchAsync != null)
            searchAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, __) => Text(
                'Search failed',
                style: GoogleFonts.dmMono(
                  fontSize: 11,
                  color: const Color(0xFFA3A3A3),
                ),
              ),
              data: (results) => ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (_, i) {
                    final r = results[i];
                    final isSelected = _selected?.id == r.id;
                    return GestureDetector(
                      onTap: () => setState(() => _selected = r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFF5F5F5)
                              : Colors.white,
                          border: Border(
                            bottom: BorderSide(color: const Color(0xFFF0F0F0)),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (r.artworkUrl != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: CachedNetworkImage(
                                  imageUrl: r.artworkUrl!,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    width: 36,
                                    height: 36,
                                    color: const Color(0xFFF0F0F0),
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 36,
                                height: 36,
                                color: const Color(0xFFF0F0F0),
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.title,
                                    style: GoogleFonts.dmMono(fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${r.username} · ${r.durationLabel}',
                                    style: GoogleFonts.dmMono(
                                      fontSize: 10,
                                      color: const Color(0xFFA3A3A3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.black,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: GoogleFonts.dmMono(
                fontSize: 11,
                color: const Color(0xFFD32F2F),
              ),
            ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: (_selected == null || _loading) ? null : _submit,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: (_selected == null || _loading)
                    ? const Color(0xFFA3A3A3)
                    : Colors.black,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _loading ? 'ADDING...' : 'ADD TO PARTY',
                textAlign: TextAlign.center,
                style: GoogleFonts.teko(
                  fontSize: 17,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Leaderboard tab ───────────────────────────────────────────────────────────

class _LeaderboardTab extends ConsumerWidget {
  const _LeaderboardTab({required this.partyId});
  final String partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(leaderboardProvider(partyId));

    return boardAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => Center(
        child: Text(
          'Failed to load leaderboard',
          style: GoogleFonts.dmMono(color: const Color(0xFFA3A3A3)),
        ),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return Center(
            child: Text(
              'NO SCORES YET',
              style: GoogleFonts.teko(
                fontSize: 22,
                color: const Color(0xFFA3A3A3),
                letterSpacing: 2,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          itemCount: entries.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Color(0xFFF0F0F0)),
          itemBuilder: (_, i) {
            final e = entries[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.teko(
                        fontSize: 20,
                        color: i == 0
                            ? const Color(0xFFFF5500)
                            : const Color(0xFFA3A3A3),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.member.username.toUpperCase(),
                          style: GoogleFonts.teko(
                            fontSize: 18,
                            letterSpacing: 0.3,
                            fontWeight: e.member.isMe
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        Text(
                          '${e.weekWins} win${e.weekWins == 1 ? '' : 's'}',
                          style: GoogleFonts.dmMono(
                            fontSize: 10,
                            color: const Color(0xFFA3A3A3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${e.totalVotes}',
                        style: GoogleFonts.teko(
                          fontSize: 24,
                          color: i == 0
                              ? const Color(0xFFFF5500)
                              : Colors.black,
                        ),
                      ),
                      Text(
                        'pts',
                        style: GoogleFonts.dmMono(
                          fontSize: 9,
                          color: const Color(0xFFA3A3A3),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Archive tab ───────────────────────────────────────────────────────────────

class _ArchiveTab extends ConsumerStatefulWidget {
  const _ArchiveTab({required this.partyId});
  final String partyId;

  @override
  ConsumerState<_ArchiveTab> createState() => _ArchiveTabState();
}

class _ArchiveTabState extends ConsumerState<_ArchiveTab> {
  String? _selectedWeek;

  String _prevWeekStart() {
    final now = DateTime.now().toUtc();
    final thisMonday = now.subtract(Duration(days: now.weekday - 1));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    return '${lastMonday.year.toString().padLeft(4, '0')}-'
        '${lastMonday.month.toString().padLeft(2, '0')}-'
        '${lastMonday.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _selectedWeek = _prevWeekStart();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Text(
                'WEEK OF',
                style: GoogleFonts.teko(
                  fontSize: 13,
                  letterSpacing: 1,
                  color: const Color(0xFFA3A3A3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _selectedWeek ?? '',
                style: GoogleFonts.dmMono(fontSize: 12),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _ArchiveWeekView(
            partyId: widget.partyId,
            week: _selectedWeek ?? '',
          ),
        ),
      ],
    );
  }
}

class _ArchiveWeekView extends ConsumerWidget {
  const _ArchiveWeekView({required this.partyId, required this.week});
  final String partyId;
  final String week;

  Future<void> _exportToSc(BuildContext context, WidgetRef ref) async {
    final scState = ref.read(soundcloudConnectionProvider);
    if (!scState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect your SoundCloud account first')),
      );
      return;
    }

    final key = (partyId, week);
    ref.read(_archiveExportingProvider(key).notifier).state = true;
    try {
      final url = await ref
          .read(weeklyTracksProvider(partyId).notifier)
          .exportToScPlaylist(week);
      if (!context.mounted) return;
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!context.mounted) return;
      final msg = _soundCloudExportErrorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      ref.read(_archiveExportingProvider(key).notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (week.isEmpty) return const SizedBox.shrink();

    final stateAsync = ref.watch(archiveTracksProvider((partyId, week)));
    final notifier = ref.read(weeklyTracksProvider(partyId).notifier);
    final exporting = ref.watch(_archiveExportingProvider((partyId, week)));

    return stateAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => Center(
        child: Text(
          'No data for this week',
          style: GoogleFonts.dmMono(color: const Color(0xFFA3A3A3)),
        ),
      ),
      data: (state) {
        final allTracks = state.memberTracks
            .expand((mt) => mt.tracks)
            .toList(growable: false);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  Text(
                    '${allTracks.length} TRACKS',
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      color: const Color(0xFFA3A3A3),
                    ),
                  ),
                  const Spacer(),
                  if (allTracks.isNotEmpty)
                    exporting
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFFFF5500),
                            ),
                          )
                        : GestureDetector(
                            onTap: () => _exportToSc(context, ref),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.queue_music,
                                  size: 14,
                                  color: Color(0xFFFF5500),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'SC PLAYLIST',
                                  style: GoogleFonts.teko(
                                    fontSize: 13,
                                    letterSpacing: 0.5,
                                    color: const Color(0xFFFF5500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                itemCount: state.memberTracks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (_, i) {
                  final mt = state.memberTracks[i];
                  return _MemberSection(
                    partyId: partyId,
                    memberTracks: mt,
                    weekStart: week,
                    isWeekClosed: true,
                    notifier: notifier,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  const _ViewToggleButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? Colors.black : const Color(0xFFD0D0D0),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.teko(
            fontSize: 13,
            letterSpacing: 0.8,
            color: active ? Colors.white : const Color(0xFFA3A3A3),
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.outlined = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: outlined ? Colors.white : Colors.black,
          border: outlined ? Border.all(color: Colors.black) : null,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.teko(
            fontSize: 17,
            letterSpacing: 1.5,
            color: outlined ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}
