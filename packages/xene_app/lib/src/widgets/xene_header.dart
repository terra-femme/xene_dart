import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_app/src/providers/feed_provider.dart';
import '../providers/soundcloud_connection_provider.dart';

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
    final atEnd =
        _navScrollController.offset >=
        _navScrollController.position.maxScrollExtent - 4;
    if (atEnd != _isAtEnd) setState(() => _isAtEnd = atEnd);
  }

  void _checkScrollable() {
    if (!_navScrollController.hasClients) return;
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
          try {
            context.go(path);
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
                  color: const Color(0xFF4CAF50),
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.check_circle,
                size: 16,
                color: Color(0xFF4CAF50),
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
                  color: const Color(0xFFA3A3A3),
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
                  color: Color(0xFFA3A3A3),
                ),
              ),
            ],
          ),
        );
      }

      return GestureDetector(
        onTap: () => ref.read(soundcloudConnectionProvider.notifier).connect(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CONNECT SOUNDCLOUD',
                style: GoogleFonts.teko(
                  color: const Color(0xFFA3A3A3),
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
            context.go('/artists');
            return;
          }
          if (value == 'network') {
            context.go('/network');
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
                  color: const Color(0xFF00A88F),
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: Color(0xFF00A88F),
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
                            navButton('HOME', '/'),
                            devMenuButton(),
                            navButton('FOLLOWING', '/following'),
                            navButton('PROFILE', '/profile'),
                            soundcloudButton(),
                            navButton('SETTINGS', '/settings'),
                          ],
                        ),
                      ),

                      // Fade + chevron — hides when scrolled to end
                      if (!_isAtEnd)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 48,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0x00FFFFFF), Colors.white],
                                  ),
                                ),
                              ),
                              Container(
                                color: Colors.white,
                                padding: const EdgeInsets.only(left: 4),
                                alignment: Alignment.center,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF888888),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.chevron_right,
                                    size: 14,
                                    color: Color(0xFF888888),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
    return MouseRegion(
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
                  : const Color(0xFFA3A3A3),
              fontSize: 18,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.7,
            ),
            maxLines: 1,
            child: Text(widget.label),
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
