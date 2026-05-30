import 'package:dio/dio.dart' hide Response;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xene_app/src/providers/auth_provider.dart';
import 'package:xene_app/src/widgets/auth_gate_sheet.dart';

import '../models/user_media_item.dart';
import '../providers/history_provider.dart';
import '../providers/saved_provider.dart';
import '../providers/soundcloud_connection_provider.dart';
import '../widgets/winamp_player.dart';

final _savedExportingProvider = StateProvider<bool>((ref) => false);

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
      await Supabase.instance.client.auth.signInAnonymously();
      if (mounted) context.go('/');
    } catch (_) {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAnon = ref.watch(isAnonymousProvider);
    final user = ref.watch(currentUserProvider);

    if (isAnon) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _guestView(),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AccountHeader(
              email: user?.email ?? '',
              onSignOut: _signOut,
              signingOut: _signingOut,
            ),
            const Divider(color: Color(0xFFE0E0E0), height: 1),
            const SizedBox(height: 16),
            const WinampPlayer(),
            const SizedBox(height: 24),
            const _SavedSection(),
            const SizedBox(height: 20),
            const _HistorySection(),
          ],
        ),
      ),
    );
  }

  Widget _guestView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'BROWSING AS GUEST',
          style: GoogleFonts.teko(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: Colors.black,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Create a free account to access your player, save tracks, and build your listening history.',
          style: GoogleFonts.archivo(
            fontSize: 13,
            color: const Color(0xFF888888),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: () =>
                showAuthGate(context, featureHint: 'to unlock all features'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5500),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
            child: Text(
              'SIGN IN OR CREATE AN ACCOUNT',
              style: GoogleFonts.teko(
                fontSize: 16,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Account header ─────────────────────────────────────────────────────────

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.email,
    required this.onSignOut,
    required this.signingOut,
  });
  final String email;
  final VoidCallback onSignOut;
  final bool signingOut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACCOUNT',
                  style: GoogleFonts.teko(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  email,
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: const Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 34,
            child: OutlinedButton(
              onPressed: signingOut ? null : onSignOut,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: Color(0xFFE0E0E0)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
              child: signingOut
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      'SIGN OUT',
                      style: GoogleFonts.teko(
                        fontSize: 14,
                        letterSpacing: 1.2,
                        color: Colors.black,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Saved horizontal scroll (split by platform) ───────────────────────────

class _SavedSection extends ConsumerWidget {
  const _SavedSection();

  Future<void> _exportToSc(BuildContext context, WidgetRef ref) async {
    final scState = ref.read(soundcloudConnectionProvider);
    if (!scState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect your SoundCloud account first')),
      );
      return;
    }
    ref.read(_savedExportingProvider.notifier).state = true;
    try {
      final url = await ref.read(savedProvider.notifier).exportToScPlaylist();
      if (!context.mounted) return;
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!context.mounted) return;
      String msg = 'Could not create playlist, try again';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) {
          final detail = data['detail'] as String?;
          final serverMsg = data['error'] as String?;
          msg = detail ?? serverMsg ?? 'HTTP ${e.response?.statusCode}: $msg';
        } else if (data != null) {
          msg = data.toString();
        } else {
          msg = e.message ?? 'HTTP ${e.response?.statusCode}: $msg';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      ref.read(_savedExportingProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedProvider);
    final exporting = ref.watch(_savedExportingProvider);

    final scItems = saved.where((s) => s.platform == 'soundcloud').toList();
    final ytItems = saved.where((s) => s.platform == 'youtube').toList();
    final bcItems = saved.where((s) => s.platform == 'bandcamp').toList();

    if (saved.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SAVED',
              style: GoogleFonts.dmMono(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFBBBBBB),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Bookmark tracks from your queue with ★',
              style: GoogleFonts.dmMono(
                fontSize: 11,
                color: const Color(0xFF888888),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scItems.isNotEmpty) ...[
          _SavedPlatformSection(
            label: 'SOUNDCLOUD',
            items: scItems,
            exporting: exporting,
            onExport: () => _exportToSc(context, ref),
          ),
          const SizedBox(height: 20),
        ],
        if (ytItems.isNotEmpty) ...[
          _SavedPlatformSection(label: 'YOUTUBE', items: ytItems),
          const SizedBox(height: 20),
        ],
        if (bcItems.isNotEmpty)
          _SavedPlatformSection(label: 'BANDCAMP', items: bcItems),
      ],
    );
  }
}

class _SavedPlatformSection extends StatelessWidget {
  const _SavedPlatformSection({
    required this.label,
    required this.items,
    this.exporting = false,
    this.onExport,
  });

  final String label;
  final List<SavedItem> items;
  final bool exporting;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Text(
                label,
                style: GoogleFonts.dmMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFBBBBBB),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${items.length})',
                style: GoogleFonts.dmMono(
                  fontSize: 9,
                  color: const Color(0xFFCCCCCC),
                ),
              ),
              if (onExport != null) ...[
                const Spacer(),
                exporting
                    ? const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0xFFFF5500),
                        ),
                      )
                    : GestureDetector(
                        onTap: onExport,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.queue_music,
                              size: 12,
                              color: Color(0xFFFF5500),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'SC PLAYLIST',
                              style: GoogleFonts.teko(
                                fontSize: 12,
                                letterSpacing: 0.5,
                                color: const Color(0xFFFF5500),
                              ),
                            ),
                          ],
                        ),
                      ),
              ],
            ],
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            itemBuilder: (context, i) => _SavedCard(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _SavedCard extends ConsumerWidget {
  const _SavedCard({required this.item});
  final SavedItem item;

  static const _scOrange = Color(0xFFFF5500);
  static const _ytRed = Color(0xFFFF4444);
  static const _bcBlue = Color(0xFF1DA0C3);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = switch (item.platform) {
      'youtube' => _ytRed,
      'bandcamp' => _bcBlue,
      _ => _scOrange,
    };

    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              image: item.artworkUrl != null
                  ? DecorationImage(
                      image: NetworkImage(item.artworkUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: item.artworkUrl == null
                ? Center(child: Icon(Icons.music_note, color: color, size: 20))
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            item.title ?? 'Unknown',
            style: GoogleFonts.archivo(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            item.artistName ?? '',
            style: GoogleFonts.dmMono(
              fontSize: 9,
              color: const Color(0xFF888888),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            children: [
              Text(
                '${item.daysRemaining}d',
                style: GoogleFonts.dmMono(
                  fontSize: 8,
                  color: const Color(0xFFAAAAAA),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse(item.externalUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: Icon(Icons.open_in_new, size: 12, color: color),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () =>
                    ref.read(savedProvider.notifier).unbookmark(item.id),
                child: const Icon(
                  Icons.close,
                  size: 12,
                  color: Color(0xFFCCCCCC),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── History horizontal scroll ──────────────────────────────────────────────

class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          label: 'HISTORY',
          count: history.length,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        ),
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Tracks you play will appear here',
              style: GoogleFonts.dmMono(
                fontSize: 11,
                color: const Color(0xFF888888),
              ),
            ),
          )
        else
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: history.length,
              itemBuilder: (context, i) => _HistoryCard(item: history[i]),
            ),
          ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});
  final HistoryItem item;

  static const _scOrange = Color(0xFFFF5500);
  static const _ytRed = Color(0xFFFF4444);

  @override
  Widget build(BuildContext context) {
    final color = item.platform == 'youtube' ? _ytRed : _scOrange;

    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse(item.externalUrl),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  item.platform.toUpperCase(),
                  style: GoogleFonts.dmMono(
                    fontSize: 8,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.title ?? 'Unknown',
              style: GoogleFonts.archivo(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Text(
              item.artistName ?? '',
              style: GoogleFonts.dmMono(
                fontSize: 9,
                color: const Color(0xFF888888),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared ──────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.count,
    required this.padding,
  });
  final String label;
  final int count;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.dmMono(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFBBBBBB),
              letterSpacing: 1.2,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Text(
              '($count)',
              style: GoogleFonts.dmMono(
                fontSize: 9,
                color: const Color(0xFFCCCCCC),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
