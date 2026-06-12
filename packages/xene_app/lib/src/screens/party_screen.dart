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
import '../providers/dio_provider.dart';
import '../providers/game_provider.dart';
import '../theme/xene_theme.dart';
import '../providers/soundcloud_connection_provider.dart';
import '../widgets/soundcloud_embed.dart';

// Shared provider — drives both the header button icon and the drawer animation.
final partyDrawerProvider = StateProvider<bool>((ref) => false);

/// Hamburger / close button placed in the _InnerPageLayout header's trailing slot.
class PartyMenuBtn extends ConsumerWidget {
  const PartyMenuBtn({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(partyDrawerProvider);
    return GestureDetector(
      onTap: () => ref.read(partyDrawerProvider.notifier).state = !open,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            open ? Icons.close : Icons.menu,
            key: ValueKey(open),
            size: 20,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

class PartyScreen extends ConsumerStatefulWidget {
  const PartyScreen({super.key, required this.partyId});
  final String partyId;

  @override
  ConsumerState<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends ConsumerState<PartyScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drawerCtrl;

  static const _kDrawerWidth = 300.0;

  @override
  void initState() {
    super.initState();
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() => setState(() {}));
    // Reset shared drawer provider on mount so the header icon starts closed.
    // Must be post-frame — ref is not valid during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(partyDrawerProvider.notifier).state = false;
    });
  }

  @override
  void dispose() {
    _drawerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final partyName =
        ref
            .watch(partyDetailProvider(widget.partyId))
            .valueOrNull
            ?.name
            .toUpperCase() ??
        'PARTY';
    final t = _drawerCtrl.value;

    // Drive the animation from the shared provider — keeps header icon in sync.
    ref.listen<bool>(partyDrawerProvider, (_, next) {
      if (next) {
        _drawerCtrl.forward();
      } else {
        _drawerCtrl.reverse();
      }
    });

    return Stack(
      fit: StackFit.expand,
      children: [
        // Main content — THIS WEEK only
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
            const SizedBox(height: 4),
            Expanded(child: _WeeklyTracksTab(partyId: widget.partyId)),
          ],
        ),
        // Dim overlay — tapping closes the drawer
        if (t > 0)
          GestureDetector(
            onTap: () => ref.read(partyDrawerProvider.notifier).state = false,
            child: Container(color: Colors.black.withValues(alpha: 0.4 * t)),
          ),
        // Right-side drawer — slides in from the right
        Positioned(
          top: 0,
          bottom: 0,
          right: -_kDrawerWidth * (1 - t),
          width: _kDrawerWidth,
          child: _PartyDrawer(
            partyId: widget.partyId,
            onClose: () => ref.read(partyDrawerProvider.notifier).state = false,
          ),
        ),
      ],
    );
  }
}

// ── Party drawer (right slide-in) ─────────────────────────────────────────────

class _PartyDrawer extends ConsumerStatefulWidget {
  const _PartyDrawer({required this.partyId, required this.onClose});
  final String partyId;
  final VoidCallback onClose;

  @override
  ConsumerState<_PartyDrawer> createState() => _PartyDrawerState();
}

class _PartyDrawerState extends ConsumerState<_PartyDrawer> {
  int _tab = 0; // 0 = leaderboard, 1 = archive

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(partyDetailProvider(widget.partyId)).valueOrNull;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(-6, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drawer header: party name label
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Text(
                detail?.name.toUpperCase() ?? '',
                style: GoogleFonts.teko(
                  fontSize: 13,
                  letterSpacing: 1.5,
                  color: XeneTheme.mutedLight,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Member roster
            if (detail != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 5),
                child: Text(
                  'MEMBERS',
                  style: GoogleFonts.teko(
                    fontSize: 10,
                    letterSpacing: 2,
                    color: XeneTheme.mutedLight,
                  ),
                ),
              ),
              _MemberRoster(members: detail.members),
            ],
            const Divider(height: 1, color: XeneTheme.surfaceLight),
            const SizedBox(height: 10),
            // Tab toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _DrawerTabBtn(
                    label: 'LEADERBOARD',
                    active: _tab == 0,
                    onTap: () => setState(() => _tab = 0),
                  ),
                  const SizedBox(width: 20),
                  _DrawerTabBtn(
                    label: 'ARCHIVE',
                    active: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: XeneTheme.surfaceLight),
            // Tab content
            Expanded(
              child: _tab == 0
                  ? _LeaderboardTab(partyId: widget.partyId)
                  : _ArchiveTab(partyId: widget.partyId),
            ),
            // Actions: invite + leave
            if (detail != null) ...[
              const Divider(height: 1, color: XeneTheme.surfaceLight),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Row(
                  children: [
                    _InviteButton(party: detail),
                    const Spacer(),
                    _LeaveButton(partyId: widget.partyId),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DrawerTabBtn extends StatelessWidget {
  const _DrawerTabBtn({
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
      child: Text(
        label,
        style: GoogleFonts.teko(
          fontSize: 13,
          letterSpacing: 0.8,
          color: active ? Colors.black : const Color(0xFFA3A3A3),
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          decoration: active ? TextDecoration.underline : TextDecoration.none,
          decorationColor: Colors.black,
          decorationThickness: 1.5,
        ),
      ),
    );
  }
}

// ── Member roster ─────────────────────────────────────────────────────────────

class _MemberRoster extends StatelessWidget {
  const _MemberRoster({required this.members});
  final List<PartyMember> members;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: members.map((m) {
          final label = m.isMe ? '${m.username} (you)' : m.username;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: m.isMe ? Colors.black : XeneTheme.surfaceLight,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.dmMono(
                fontSize: 9,
                color: m.isMe ? Colors.white : const Color(0xFF555555),
                fontWeight: m.isMe ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          );
        }).toList(),
      ),
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
              color: XeneTheme.mutedLight,
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
      isDismissible: true,
      enableDrag: true,
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
              style: GoogleFonts.teko(color: XeneTheme.error),
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
              color: XeneTheme.surface,
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
              color: XeneTheme.mutedLight,
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
// true = scene mode (competitive), false = discovery mode (social).
final _partyGameModeProvider = StateProvider.family.autoDispose<bool, String>(
  (_, __) => true,
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
        final isSceneMode = ref.watch(_partyGameModeProvider(partyId));
        final sceneText = ref.watch(weekSceneProvider).valueOrNull;
        final hasAnyTracks = state.memberTracks.any(
          (mt) => mt.tracks.isNotEmpty,
        );

        // Filter each member's tracks to the active mode only.
        final filteredMemberTracks = state.memberTracks
            .map(
              (mt) => MemberTracks(
                member: mt.member,
                tracks: mt.tracks
                    .where((t) => isSceneMode ? t.isScenario : t.isDiscovery)
                    .toList(),
              ),
            )
            .toList();

        return Column(
          children: [
            _WeekStatusBar(state: state, votes: votes),
            if (sceneText != null) _SceneBanner(scene: sceneText),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  const Spacer(),
                  if (hasAnyTracks)
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
                                  '+ SC PLAYLIST',
                                  style: GoogleFonts.teko(
                                    fontSize: 13,
                                    letterSpacing: 0.5,
                                    color: XeneTheme.orange,
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
                  vertical: 8,
                ),
                itemCount: filteredMemberTracks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (_, i) {
                  final mt = filteredMemberTracks[i];
                  return _MemberSection(
                    partyId: partyId,
                    memberTracks: mt,
                    weekStart: state.weekStart,
                    isWeekClosed: state.isWeekClosed,
                    isCurrentWeek: state.isCurrentWeek,
                    isResultsVisible: state.isResultsVisible,
                    voteCount: isSceneMode ? (tally?[mt.member.userId]) : null,
                    notifier: notifier,
                    isSceneMode: isSceneMode,
                  );
                },
              ),
            ),
            if (isSceneMode && !state.isWeekClosed)
              _VoteBar(
                partyId: partyId,
                state: state,
                votes: votes,
                votesNotifier: ref.read(weekVotesProvider(partyId).notifier),
              ),
            _SceneDiscoveryToggle(partyId: partyId),
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
            color: XeneTheme.mutedLight,
          ),
        ),
      );
    }

    final d = _remaining.inDays;
    final h = _remaining.inHours.remainder(24);
    final m = _remaining.inMinutes.remainder(60);
    final s = _remaining.inSeconds.remainder(60);
    final hms =
        '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
    final countdown = d > 0 ? '${d}d $hms' : hms;

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
              color: XeneTheme.mutedLight,
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
    this.isSceneMode = true,
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
  final bool isSceneMode;
  final bool isResultsVisible;
  final int? voteCount;

  @override
  Widget build(BuildContext context) {
    final member = memberTracks.member;
    final tracks = memberTracks.tracks;
    final cap = isSceneMode ? 1 : 4;
    final canAdd = member.isMe && isCurrentWeek && tracks.length < cap;

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
                    color: XeneTheme.mutedLight,
                  ),
                ),
              ),
            const Spacer(),
            if (isResultsVisible && voteCount != null && isSceneMode)
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
              isWeekClosed ? '${tracks.length}' : '${tracks.length}/$cap',
              style: GoogleFonts.teko(
                fontSize: 15,
                color: XeneTheme.mutedLight,
              ),
            ),
            if (canAdd) ...[
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
            isSceneMode
                ? 'No scene track submitted yet'
                : 'No discoveries shared yet',
            style: GoogleFonts.dmMono(
              fontSize: 11,
              color: XeneTheme.mutedLight,
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
      isDismissible: true,
      enableDrag: true,
      builder: (_) => _TrackSubmitSheet(
        partyId: partyId,
        slotsUsed: memberTracks.tracks.length,
        notifier: notifier,
        trackType: isSceneMode ? 'scenario' : 'discovery',
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
  });

  final PartyTrack track;
  final bool isOwner;
  final bool isWeekClosed;
  final VoidCallback onDelete;

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
                      if (t.scDurationSeconds != null)
                        Text(
                          _durationLabel(t.scDurationSeconds!),
                          style: GoogleFonts.dmMono(
                            fontSize: 10,
                            color: XeneTheme.mutedLight,
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
                  color: XeneTheme.mutedLight,
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
      color: XeneTheme.surfaceLight,
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
      (mt) => mt.member.isMe && mt.tracks.any((t) => t.isScenario),
    );

    if (alreadyVoted) {
      return Container(
        color: const Color(0xFFF5F5F5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Text(
          'YOUR VOTE IS IN — RESULTS FRIDAY ${_revealTimeLocal(state.weekStart)}',
          style: GoogleFonts.teko(
            fontSize: 13,
            letterSpacing: 1,
            color: XeneTheme.success,
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
                color: XeneTheme.mutedLight,
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
      isDismissible: true,
      enableDrag: true,
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
        .where((mt) => !mt.member.isMe && mt.tracks.any((t) => t.isScenario))
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
              color: XeneTheme.mutedLight,
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
                    color: selected ? Colors.black : XeneTheme.borderHeavy,
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
                              color: XeneTheme.mutedLight,
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
              style: GoogleFonts.dmMono(fontSize: 11, color: XeneTheme.error),
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
    this.trackType = 'discovery',
  });
  final String partyId;
  final int slotsUsed;
  final WeeklyTracksNotifier notifier;
  final String trackType;

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

    // Check if another member has already submitted this track in this party.
    // Failures are silent — a failed check never blocks submission.
    try {
      final dio = ref.read(authenticatedDioProvider);
      final checkRes = await dio.get<Map<String, dynamic>>(
        '/game/parties/${widget.partyId}/tracks/check',
        queryParameters: {'sc_track_id': _selected!.id},
      );
      final data = checkRes.data ?? {};
      if (data['found'] == true && mounted) {
        final username = data['username'] as String? ?? 'Another member';
        final dateLabel = _formatSubmittedDate(data['submitted_at'] as String?);

        setState(() => _loading = false);

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            title: Text(
              'Already submitted',
              style: GoogleFonts.teko(fontSize: 20, letterSpacing: 0.5),
            ),
            content: Text(
              '$username already submitted that track'
              '${dateLabel.isNotEmpty ? ' on $dateLabel' : ''}.'
              ' Submit it anyway?',
              style: GoogleFonts.dmMono(fontSize: 12),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'CHOOSE ANOTHER',
                  style: GoogleFonts.teko(color: const Color(0xFFA3A3A3)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  'SUBMIT ANYWAY',
                  style: GoogleFonts.teko(color: Colors.black),
                ),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
        setState(() => _loading = true);
      }
    } catch (_) {
      // Pre-check failed — proceed to submit without blocking the user.
    }

    try {
      await widget.notifier.submitTrack({
        'sc_track_id': _selected!.id,
        'sc_track_url': _selected!.permalinkUrl,
        'sc_title': _selected!.title,
        'sc_artwork_url': _selected!.artworkUrl,
        'sc_duration_seconds': _selected!.durationSeconds,
        'track_type': widget.trackType,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = _extractSubmitError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchAsync = _query.trim().length >= 2
        ? ref.watch(scTrackSearchProvider(_query.trim()))
        : null;

    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final cap = widget.trackType == 'scenario' ? 1 : 4;
    final slotsLeft = cap - widget.slotsUsed;

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
                widget.trackType == 'scenario'
                    ? 'SUBMIT FOR THE SCENE'
                    : 'SHARE A DISCOVERY',
                style: GoogleFonts.teko(fontSize: 20, letterSpacing: 1),
              ),
              const Spacer(),
              Text(
                '$slotsLeft slot${slotsLeft == 1 ? '' : 's'} left',
                style: GoogleFonts.dmMono(
                  fontSize: 11,
                  color: XeneTheme.mutedLight,
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
                color: XeneTheme.mutedLight,
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              enabledBorder: const UnderlineInputBorder(
                borderSide: const BorderSide(color: XeneTheme.borderHeavy),
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
                  color: XeneTheme.mutedLight,
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
                            bottom: const BorderSide(
                              color: XeneTheme.surfaceLight,
                            ),
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
                                    color: XeneTheme.surfaceLight,
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 36,
                                height: 36,
                                color: XeneTheme.surfaceLight,
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
                                      color: XeneTheme.mutedLight,
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
              style: GoogleFonts.dmMono(fontSize: 11, color: XeneTheme.error),
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
    final winnersAsync = ref.watch(weeklyWinnersProvider(partyId));

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
        final winners = winnersAsync.valueOrNull ?? [];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _MonthlyWidget(winners: winners),
            const SizedBox(height: 20),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'NO SCORES YET',
                    style: GoogleFonts.teko(
                      fontSize: 22,
                      color: XeneTheme.mutedLight,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              )
            else
              ...entries.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                return Column(
                  children: [
                    Padding(
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
                                    color: XeneTheme.mutedLight,
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
                                  color: XeneTheme.mutedLight,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (i < entries.length - 1)
                      const Divider(height: 1, color: XeneTheme.surfaceLight),
                  ],
                );
              }),
          ],
        );
      },
    );
  }
}

// ── Monthly widget ────────────────────────────────────────────────────────────

const _kPalette = [
  Color(0xFFFF1744), // red
  Color(0xFFF50057), // pink
  Color(0xFFD500F9), // purple
  Color(0xFF651FFF), // deep purple
  Color(0xFF3D5AFE), // indigo
  Color(0xFF2979FF), // blue
  Color(0xFF00B0FF), // light blue
  Color(0xFF00E5FF), // cyan
  Color(0xFF1DE9B6), // teal
  Color(0xFF00E676), // green
  Color(0xFF76FF03), // light green
  Color(0xFFEEFF41), // lime
  Color(0xFFFFD600), // yellow
  Color(0xFFFFAB00), // amber
  Color(0xFFFF6D00), // orange
  Color(0xFFFF3D00), // deep orange
  Color(0xFFE040FB), // purple 200
  Color(0xFFFF4081), // pink 200
  Color(0xFF40C4FF), // light blue 200
  Color(0xFF69F0AE), // green 200
];

Color _colorForName(String name) {
  final hash = name.codeUnits.fold(0, (h, c) => h * 31 + c);
  return _kPalette[hash.abs() % _kPalette.length];
}

// Generates all Monday week-start strings whose Monday falls in [year, month].
List<String> _weeksInMonth(int year, int month) {
  final firstDay = DateTime.utc(year, month, 1);
  // Walk back to the Monday on or before the 1st.
  var monday = firstDay.subtract(Duration(days: firstDay.weekday - 1));
  final result = <String>[];
  while (true) {
    // Include this week only if its Monday is in the target month.
    if (monday.month == month && monday.year == year) {
      result.add(
        '${monday.year.toString().padLeft(4, '0')}-'
        '${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}',
      );
    }
    monday = monday.add(const Duration(days: 7));
    if (monday.month != month || monday.year != year) break;
  }
  return result;
}

class _MonthlyWidget extends StatelessWidget {
  const _MonthlyWidget({required this.winners});
  final List<WeekWinner> winners;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weeks = _weeksInMonth(now.year, now.month);
    final currentWeek = _currentWeekMonday();
    final winnerMap = {for (final w in winners) w.weekStart: w};

    const monthNames = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];
    final monthLabel = '${monthNames[now.month - 1]} ${now.year}';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            monthLabel,
            style: GoogleFonts.teko(
              fontSize: 13,
              letterSpacing: 2,
              color: const Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 10),
          ...weeks.asMap().entries.map((entry) {
            final i = entry.key;
            final weekStr = entry.value;
            final winner = winnerMap[weekStr];
            final isPast = weekStr.compareTo(currentWeek) < 0;
            final isCurrent = weekStr == currentWeek;
            final hasResult = winner != null;

            return Padding(
              padding: EdgeInsets.only(bottom: i < weeks.length - 1 ? 8 : 0),
              child: _WeekBar(
                weekNumber: i + 1,
                hasResult: hasResult,
                isPast: isPast,
                isCurrent: isCurrent,
                winnerName: winner?.winnerUsername,
              ),
            );
          }),
        ],
      ),
    );
  }

  String _currentWeekMonday() {
    final now = DateTime.now().toUtc();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return '${monday.year.toString().padLeft(4, '0')}-'
        '${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.weekNumber,
    required this.hasResult,
    required this.isPast,
    required this.isCurrent,
    this.winnerName,
  });

  final int weekNumber;
  final bool hasResult;
  final bool isPast;
  final bool isCurrent;
  final String? winnerName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              'W$weekNumber',
              style: GoogleFonts.teko(
                fontSize: 11,
                color: const Color(0xFF555555),
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: hasResult
                  ? _FilledBar(winnerName: winnerName!)
                  : _HatchedBar(isCurrent: isCurrent),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilledBar extends StatelessWidget {
  const _FilledBar({required this.winnerName});
  final String winnerName;

  @override
  Widget build(BuildContext context) {
    final color = _colorForName(winnerName);
    // Use a dark version for text when color is very light.
    final luminance = color.computeLuminance();
    final textColor = luminance > 0.55 ? const Color(0xFF111111) : Colors.white;

    return Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        winnerName.toUpperCase(),
        style: GoogleFonts.teko(
          fontSize: 13,
          letterSpacing: 1,
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _HatchedBar extends StatelessWidget {
  const _HatchedBar({required this.isCurrent});
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HatchPainter(isCurrent: isCurrent),
      child: Container(),
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter({required this.isCurrent});
  final bool isCurrent;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = isCurrent ? const Color(0xFF1E1E1E) : const Color(0xFF181818);
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);

    final linePaint = Paint()
      ..color = isCurrent ? const Color(0xFF2E2E2E) : const Color(0xFF222222)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const step = 10.0;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.isCurrent != isCurrent;
}

// ── Scene banner ──────────────────────────────────────────────────────────────

class _SceneBanner extends StatefulWidget {
  const _SceneBanner({required this.scene});
  final String scene;

  @override
  State<_SceneBanner> createState() => _SceneBannerState();
}

class _SceneBannerState extends State<_SceneBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    // Modular hook: pass a Duration here to delay reveal after a Lottie animation.
    // To add Lottie: play your Lottie widget for [delay], then call _reveal(delay).
    _reveal();
  }

  void _reveal([Duration delay = Duration.zero]) {
    Future.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          width: double.infinity,
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THIS WEEK\'S SCENE',
                style: GoogleFonts.teko(
                  fontSize: 11,
                  letterSpacing: 2,
                  color: const Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 2),
              Center(
                child: Text(
                  widget.scene.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.teko(
                    fontSize: 17,
                    letterSpacing: 0.5,
                    color: Colors.white,
                    height: 1.15,
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

// ── Scene / Discovery bottom toggle ───────────────────────────────────────────

class _SceneDiscoveryToggle extends ConsumerWidget {
  const _SceneDiscoveryToggle({required this.partyId});
  final String partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isScene = ref.watch(_partyGameModeProvider(partyId));

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: SizedBox(
        height: 38,
        child: Stack(
          children: [
            // Dark border container
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF333333)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Sliding white pill
            IgnorePointer(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: isScene
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            // Tap targets + labels
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        ref
                                .read(_partyGameModeProvider(partyId).notifier)
                                .state =
                            true,
                    child: Center(
                      child: Text(
                        'SCENE',
                        style: GoogleFonts.teko(
                          fontSize: 14,
                          letterSpacing: 1,
                          color: isScene
                              ? Colors.black
                              : const Color(0xFF666666),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        ref
                                .read(_partyGameModeProvider(partyId).notifier)
                                .state =
                            false,
                    child: Center(
                      child: Text(
                        'DISCOVERY',
                        style: GoogleFonts.teko(
                          fontSize: 14,
                          letterSpacing: 1,
                          color: !isScene
                              ? Colors.black
                              : const Color(0xFF666666),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final weeksAsync = ref.watch(partyWeeksProvider(widget.partyId));

    return weeksAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => Center(
        child: Text(
          'Could not load archive',
          style: GoogleFonts.dmMono(color: const Color(0xFFA3A3A3)),
        ),
      ),
      data: (weeks) {
        if (weeks.isEmpty) {
          return Center(
            child: Text(
              'NO ARCHIVE YET',
              style: GoogleFonts.teko(
                fontSize: 22,
                color: XeneTheme.mutedLight,
                letterSpacing: 2,
              ),
            ),
          );
        }

        final idx = _index.clamp(0, weeks.length - 1);
        final selectedWeek = weeks[idx];
        final canGoOlder = idx < weeks.length - 1;
        final canGoNewer = idx > 0;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: canGoOlder
                        ? () => setState(() => _index = idx + 1)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.chevron_left,
                        size: 20,
                        color: canGoOlder
                            ? Colors.black
                            : const Color(0xFFE0E0E0),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'WEEK OF $selectedWeek',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.teko(
                        fontSize: 13,
                        letterSpacing: 1,
                        color: XeneTheme.mutedLight,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: canGoNewer
                        ? () => setState(() => _index = idx - 1)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: canGoNewer
                            ? Colors.black
                            : const Color(0xFFE0E0E0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _ArchiveExpiryBanner(weekStart: selectedWeek),
            Expanded(
              child: _ArchiveWeekView(
                partyId: widget.partyId,
                week: selectedWeek,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Archive expiry banner ─────────────────────────────────────────────────────

class _ArchiveExpiryBanner extends StatelessWidget {
  const _ArchiveExpiryBanner({required this.weekStart});
  final String weekStart;

  @override
  Widget build(BuildContext context) {
    final expiry = _weekExpiresAt(weekStart);
    final daysLeft = expiry.difference(DateTime.now().toUtc()).inDays;

    if (daysLeft < 0 || daysLeft > 7) return const SizedBox.shrink();

    final label = daysLeft == 0
        ? 'today'
        : '$daysLeft day${daysLeft == 1 ? '' : 's'}';

    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF3E0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.access_time, size: 13, color: Color(0xFFE65100)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Tracks deleted in $label — export to SoundCloud to keep them',
              style: GoogleFonts.dmMono(
                fontSize: 10,
                color: const Color(0xFFE65100),
              ),
            ),
          ),
        ],
      ),
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
                      color: XeneTheme.mutedLight,
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
                                  '+ SC PLAYLIST',
                                  style: GoogleFonts.teko(
                                    fontSize: 13,
                                    letterSpacing: 0.5,
                                    color: XeneTheme.orange,
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

// Returns the UTC datetime when a week's data is purged (vote end + 31 days).
DateTime _weekExpiresAt(String weekStart) {
  final parts = weekStart.split('-');
  final monday = DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  return monday.add(const Duration(days: 35));
}

// Converts the Friday 21:05 UTC reveal deadline to the device's local time.
String _revealTimeLocal(String weekStart) {
  final parts = weekStart.split('-');
  final monday = DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  final friday = monday.add(const Duration(days: 4));
  final revealUtc = DateTime.utc(friday.year, friday.month, friday.day, 21, 5);
  final local = revealUtc.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final m = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $period';
}

String _formatSubmittedDate(String? isoDate) {
  if (isoDate == null) return '';
  try {
    final dt = DateTime.parse(isoDate).toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  } catch (_) {
    return '';
  }
}

String _extractSubmitError(Object e) {
  final s = e.toString();
  if (s.contains('"error"')) {
    final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(s);
    if (match != null) return match.group(1)!;
  }
  return 'Could not add track, try again';
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
