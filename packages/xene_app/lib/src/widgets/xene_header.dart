import 'dart:ui';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_app/src/providers/auth_provider.dart';
import 'package:xene_app/src/providers/daily_inbox_provider.dart';
import 'package:xene_app/src/widgets/bug_report_sheet.dart';
import 'package:xene_app/src/providers/feed_provider.dart';
import 'package:xene_app/src/theme/xene_theme.dart';
import 'package:xene_app/src/widgets/auth_gate_sheet.dart';
import 'package:xene_app/src/widgets/daily_inbox_sheet.dart';
import '../providers/soundcloud_connection_provider.dart';
import '../providers/nav_swipe_provider.dart';

const _forceDevMenu = bool.fromEnvironment('XENE_FORCE_DEV_MENU');

class XeneHeader extends ConsumerStatefulWidget {
  const XeneHeader({super.key});

  @override
  ConsumerState<XeneHeader> createState() => _XeneHeaderState();
}

class _XeneHeaderState extends ConsumerState<XeneHeader> {
  final ScrollController _navScrollController = ScrollController();
  bool _isAtEnd = false;
  int _seedDayOffset = 1;

  @override
  void initState() {
    super.initState();
    _navScrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScrollable());
  }

  void _onScroll() {
    if (!_navScrollController.position.hasContentDimensions) return;
    final atEnd =
        _navScrollController.offset >=
        _navScrollController.position.maxScrollExtent - 4;
    if (atEnd != _isAtEnd) setState(() => _isAtEnd = atEnd);
  }

  void _checkScrollable() {
    if (!mounted) return;
    if (!_navScrollController.hasClients ||
        !_navScrollController.position.hasContentDimensions) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkScrollable());
      return;
    }
    final isScrollable = _navScrollController.position.maxScrollExtent > 0;
    setState(() => _isAtEnd = !isScrollable);
  }

  @override
  void dispose() {
    _navScrollController.removeListener(_onScroll);
    _navScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scState = ref.watch(soundcloudConnectionProvider);
    final isAnon = ref.watch(isAnonymousProvider);
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final showDevMenu = isAdmin || (kDebugMode && _forceDevMenu);

    String location;
    try {
      location = GoRouterState.of(context).uri.toString();
    } catch (e) {
      location = '/';
    }

    final double topPadding = MediaQuery.of(context).padding.top;

    Widget navButton(String label, String path) {
      final isActive = location == path;
      return _HeaderNavButton(
        label: label,
        path: path,
        isActive: isActive,
        onTap: () {
          if (isAnon && path == '/following') {
            showAuthGate(
              context,
              featureHint: 'to track new releases from artists you follow',
            );
            return;
          }
          // Sync swipe-nav state so the slide animation goes the right direction
          // even when the user taps non-linearly (e.g. skips from HOME to ABOUT).
          final targetIdx = kSwipeNavRoutes.indexOf(path);
          if (targetIdx >= 0) {
            final currentIdx = ref.read(navIndexProvider);
            navGoingForward = targetIdx >= currentIdx;
            ref.read(navIndexProvider.notifier).state = targetIdx;
          }
          try {
            if (path == '/') {
              context.go(path);
            } else {
              context.push(path);
            }
          } catch (e) {
            // No-op in preview
          }
        },
      );
    }

    Widget soundcloudButton() {
      if (scState.connected) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SOUNDCLOUD',
                style: GoogleFonts.teko(
                  color: XeneTheme.success,
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.check_circle,
                size: 16,
                color: XeneTheme.success,
              ),
            ],
          ),
        );
      }

      if (scState.isPolling) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CONNECTING',
                style: GoogleFonts.teko(
                  color: XeneTheme.mutedLight,
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: XeneTheme.mutedLight,
                ),
              ),
            ],
          ),
        );
      }

      return GestureDetector(
        onTap: () {
          if (isAnon) {
            showAuthGate(
              context,
              featureHint:
                  'to link your SoundCloud and see releases from artists you follow',
            );
            return;
          }
          ref.read(soundcloudConnectionProvider.notifier).connect();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CONNECT SOUNDCLOUD',
                style: GoogleFonts.teko(
                  color: XeneTheme.mutedLight,
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.share, size: 18, color: Color(0xFFA3A3A3)),
            ],
          ),
        ),
      );
    }

    Widget devMenuButton() {
      return PopupMenuButton<String>(
        tooltip: 'Dev links',
        color: Colors.white,
        elevation: 4,
        offset: const Offset(0, 34),
        onSelected: (value) {
          if (value == 'artist') {
            context.push('/artists');
            return;
          }
          if (value == 'network') {
            context.push('/network');
            return;
          }
          if (value == 'presets') {
            context.push('/dev/presets');
            return;
          }
          if (value == 'monitor') {
            context.push('/dev/monitor');
            return;
          }
          if (value == 'test') {
            final seed = DateTime.now().add(Duration(days: _seedDayOffset));
            final seedStr = seed.toIso8601String().substring(0, 10);
            ref.read(feedProvider.notifier).fetchWithSeedDate(seedStr);
            setState(() => _seedDayOffset++);
          }
        },
        itemBuilder: (context) => [
          _devMenuItem('artist', 'ARTIST'),
          _devMenuItem('network', 'NETWORK'),
          _devMenuItem('presets', 'PRESET PLAYGROUND'),
          _devMenuItem('monitor', 'MONITOR'),
          _devMenuItem('test', 'TEST +${_seedDayOffset}D'),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'DEV',
                style: GoogleFonts.teko(
                  color: XeneTheme.tealDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: XeneTheme.tealDark,
              ),
            ],
          ),
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          height: topPadding + 56,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
          ),
          child: Column(
            children: [
              SizedBox(height: topPadding),
              SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      // Scrollable nav + fade overlay
                      Expanded(
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            // Scrollable nav row
                            SingleChildScrollView(
                              controller: _navScrollController,
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  if (showDevMenu) devMenuButton(),
                                  navButton('HOME', '/'),
                                  navButton('FEATURE', '/articles'),
                                  navButton('FOLLOWING', '/following'),
                                  navButton('GAME', '/game'),
                                  navButton('CHANNELS', '/channels'),
                                  navButton('PROFILE', '/profile'),
                                  navButton('SETTINGS', '/settings'),
                                  navButton('ABOUT', '/about'),
                                  _SubmitBugButton(),
                                  soundcloudButton(),
                                ],
                              ),
                            ),

                            // Fade + chevron — decorative scroll indicator
                          ],
                        ),
                      ),

                      // Fixed inbox badge — always visible, not in scroll
                      if (!_isAtEnd) const _NavOverflowChevron(),
                      _InboxBadgeButton(onTap: () => showDailyInbox(context)),
                    ],
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

PopupMenuItem<String> _devMenuItem(String value, String label) {
  return PopupMenuItem<String>(
    value: value,
    height: 34,
    child: Text(
      label,
      style: GoogleFonts.dmMono(
        fontSize: 11,
        color: Colors.black,
        letterSpacing: 1.0,
      ),
    ),
  );
}

// ── Submit Bug nav button ──────────────────────────────────────────────────────

class _SubmitBugButton extends StatefulWidget {
  const _SubmitBugButton();

  @override
  State<_SubmitBugButton> createState() => _SubmitBugButtonState();
}

class _SubmitBugButtonState extends State<_SubmitBugButton> {
  bool _isHovered = false;

  void _open() => showBugReportSheet(context);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: GoogleFonts.teko(
              color: _isHovered ? XeneTheme.orange : XeneTheme.mutedLight,
              fontSize: 18,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.7,
            ),
            maxLines: 1,
            child: const Text('SUBMIT BUG'),
          ),
        ),
      ),
    );
  }
}

// ── Nav button ─────────────────────────────────────────────────────────────────

class _HeaderNavButton extends StatefulWidget {
  const _HeaderNavButton({
    required this.label,
    required this.path,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final String path;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_HeaderNavButton> createState() => _HeaderNavButtonState();
}

class _HeaderNavButtonState extends State<_HeaderNavButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.label} navigation',
      selected: widget.isActive,
      button: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: GoogleFonts.teko(
                color: _isHovered || widget.isActive
                    ? Colors.black
                    : XeneTheme.mutedLight,
                fontSize: 18,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.7,
              ),
              maxLines: 1,
              child: ExcludeSemantics(child: Text(widget.label)),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Inbox badge button ────────────────────────────────────────────────────────

class _NavOverflowChevron extends StatelessWidget {
  const _NavOverflowChevron();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 28,
        height: 44,
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: XeneTheme.muted,
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.chevron_right,
              size: 14,
              color: XeneTheme.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _InboxBadgeButton extends ConsumerWidget {
  const _InboxBadgeButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxAsync = ref.watch(dailyInboxProvider);
    final hasInbox = inboxAsync.valueOrNull != null;
    final isRead = ref.watch(inboxReadProvider);

    final inboxLabel = hasInbox && !isRead
        ? 'Daily inbox, unread'
        : 'Daily inbox';
    return Semantics(
      label: inboxLabel,
      button: true,
      child: GestureDetector(
        onTap: () {
          ref.read(inboxReadProvider.notifier).state = true;
          onTap();
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.mail_outline,
                size: 22,
                color: hasInbox ? Colors.black : XeneTheme.mutedLight,
              ),
              if (hasInbox && !isRead)
                Positioned(
                  top: 7,
                  right: 7,
                  child: ExcludeSemantics(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: XeneTheme.orange,
                        shape: BoxShape.circle,
                      ),
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

@Preview(name: 'Header - Default')
Widget previewXeneHeader() {
  return const Material(child: XeneHeader());
}
