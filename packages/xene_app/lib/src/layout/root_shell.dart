import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xene_app/src/layout/xene_layout_metrics.dart';
import 'package:xene_app/src/providers/accessibility_provider.dart';
import 'package:xene_app/src/providers/nav_swipe_provider.dart';
import 'package:xene_app/src/widgets/xene_header.dart';
import 'package:xene_app/src/widgets/xene_sidebar.dart';
import 'package:xene_app/src/widgets/xene_draggable_sheet.dart';
import 'package:xene_app/src/widgets/logo_pip_player.dart';
import 'package:xene_app/src/widgets/loading_overlay.dart';

/// Persistent application chrome for the 7 primary swipe routes.
///
/// This is the single shell that `StatefulShellRoute` keeps mounted across
/// navigation. Because the chrome is built once and only the active branch is
/// swapped, the whole class of "subtree reactivation during a layout pass"
/// bugs — the `_RenderLayoutBuilder was mutated` crash — is structurally
/// eliminated: nothing is torn down and re-activated on a page change.
///
/// Chrome is *conditional* (decision: preserve today's look). The feed branch
/// (index 0) gets the sidebar + draggable sheet + PiP player; the other six
/// primary pages get the header only. The header, loading overlay, and content
/// offset are uniform across all branches.
class RootShell extends ConsumerWidget {
  const RootShell({super.key, required this.navigationShell});

  /// The shell driving branch selection. Provided to descendants (e.g.
  /// [XeneHeader]) via [ShellScope] so nav taps can call [goBranch].
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isFeed = navigationShell.currentIndex == 0;

    // Full-screen shell ⇒ MediaQuery is the correct metrics source. We do NOT
    // wrap this subtree in a top-level LayoutBuilder: a LayoutBuilder builds
    // its child during the layout phase, and the original crash funneled
    // through exactly that. MediaQuery gives identical metrics in the build
    // phase, where marking descendants dirty is legal.
    final mediaQuery = MediaQuery.of(context);
    final metrics = XeneLayoutMetrics.fromConstraints(
      constraints: BoxConstraints.tight(mediaQuery.size),
      safePadding: mediaQuery.padding,
      viewInsets: mediaQuery.viewInsets,
      textScaleFactor: mediaQuery.textScaler.scale(1),
    );
    final double topOffset = metrics.headerHeight;

    return ShellScope(
      navigationShell: navigationShell,
      child: XeneLayoutScope(
        metrics: metrics,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              // 1. Content area: header-height spacer, then the (optional)
              //    sidebar beside the swipeable branch content.
              Column(
                children: [
                  SizedBox(height: topOffset),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isFeed) const XeneSidebar(),
                        Expanded(
                          child: _ShellSwipeWrapper(
                            navigationShell: navigationShell,
                            child: Container(
                              color: Colors.white,
                              child: navigationShell,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // 2. Fixed header (floating over the spacer band).
              const Positioned(top: 0, left: 0, right: 0, child: XeneHeader()),

              // 3. Overlays. The draggable sheet is feed-only chrome, but the
              //    PiP player must persist across every swipe branch — gating it
              //    on `isFeed` is what made it vanish when the user swiped off
              //    the feed. RootShell stays mounted across branch switches, so
              //    keeping the player here (always) keeps the SoundCloud/YouTube
              //    iframe alive and playing until the user closes/gestures it
              //    away. It self-hides when nothing is playing.
              if (isFeed) const XeneDraggableSheet(),
              const LogoPipPlayer(),

              // 4. Loading overlay (topmost — covers everything on first load).
              const LoadingOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Exposes the active [StatefulNavigationShell] to descendants so widgets like
/// [XeneHeader] can switch branches without a global mutable nav state.
///
/// Returns `null` from [maybeOf] when looked up outside the shell (e.g. on a
/// top-level secondary route such as `/settings`, which is pushed *over* the
/// shell and therefore is not a descendant of it). Callers fall back to plain
/// `go`/`push` in that case.
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.navigationShell,
    required super.child,
  });

  final StatefulNavigationShell navigationShell;

  static StatefulNavigationShell? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>()?.navigationShell;

  @override
  bool updateShouldNotify(ShellScope oldWidget) =>
      navigationShell != oldWidget.navigationShell;
}

/// Renders the branch navigators with a directional horizontal slide.
///
/// All branches stay mounted (state retention) but inactive ones are kept
/// [Offstage] with their [TickerMode] disabled, so off-screen pages don't burn
/// CPU on tickers/animations (this is also what keeps the feed's auto-scroll
/// crawl from running — and crashing — while it isn't the visible page).
///
/// Wire this as `StatefulShellRoute(navigatorContainerBuilder: ...)`. The
/// `children` are the per-branch [Navigator] widgets supplied by go_router.
class AnimatedBranchContainer extends ConsumerStatefulWidget {
  const AnimatedBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  ConsumerState<AnimatedBranchContainer> createState() =>
      _AnimatedBranchContainerState();
}

class _AnimatedBranchContainerState
    extends ConsumerState<AnimatedBranchContainer>
    with SingleTickerProviderStateMixin {
  static const _slideDuration = Duration(milliseconds: 260);

  late final AnimationController _controller;
  late int _previousIndex;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.currentIndex;
    _controller = AnimationController(
      vsync: this,
      duration: _slideDuration,
      value: 1.0, // start settled (no entrance animation on first build)
    );
    _controller.addStatusListener((status) {
      // Once the slide finishes, rebuild so the outgoing branch drops back to
      // Offstage (and its ticker is muted) instead of lingering off-screen.
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _previousIndex = oldWidget.currentIndex;
      final reduceMotion = ref.read(accessibilityProvider).reduceMotion;
      if (reduceMotion) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    // Higher index ⇒ "forward": the new page enters from the right.
    final bool forward = widget.currentIndex >= _previousIndex;

    return Stack(
      children: [
        for (int i = 0; i < widget.children.length; i++)
          _buildBranch(i, width, forward),
      ],
    );
  }

  Widget _buildBranch(int index, double width, bool forward) {
    final bool isCurrent = index == widget.currentIndex;
    final bool isOutgoing =
        index == _previousIndex && index != widget.currentIndex;
    final bool isSettled = !_controller.isAnimating && _controller.value == 1.0;

    // Inactive, non-transitioning branches: mounted but invisible and muted.
    if (!isCurrent && !(isOutgoing && !isSettled)) {
      return Offstage(
        offstage: true,
        child: TickerMode(enabled: false, child: widget.children[index]),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      child: TickerMode(enabled: isCurrent, child: widget.children[index]),
      builder: (context, child) {
        final double t = Curves.easeOutCubic.transform(_controller.value);
        final double dx = isCurrent
            // Incoming: from right (forward) / left (back) → center.
            ? (forward ? 1.0 : -1.0) * (1.0 - t) * width
            // Outgoing: center → left (forward) / right (back).
            : (forward ? -1.0 : 1.0) * t * width;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// Magazine-style horizontal swipe between the primary branches.
///
/// Drag gives finger-following feedback; on commit it calls
/// [StatefulNavigationShell.goBranch] and lets [AnimatedBranchContainer] render
/// the directional slide. Hidden easter egg — no visible affordance.
class _ShellSwipeWrapper extends ConsumerStatefulWidget {
  const _ShellSwipeWrapper({
    required this.navigationShell,
    required this.child,
  });

  final StatefulNavigationShell navigationShell;
  final Widget child;

  @override
  ConsumerState<_ShellSwipeWrapper> createState() => _ShellSwipeWrapperState();
}

class _ShellSwipeWrapperState extends ConsumerState<_ShellSwipeWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _offset = 0;
  double _animStart = 0;
  bool _dragging = false;

  // Raw (un-damped) horizontal distance since drag started. Distance-based
  // commit fallback for web/desktop where mouse drags are low-velocity.
  double _rawDrag = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
    );
    _ctrl.addListener(() {
      setState(() => _offset = _animStart + (0 - _animStart) * _ctrl.value);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _snapBack() {
    _ctrl.stop();
    _animStart = _offset;
    _ctrl.duration = const Duration(milliseconds: 210);
    _ctrl.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _offset = 0);
    });
  }

  void _commitNavigate(int targetIdx) {
    // Reset drag feedback immediately; the shell's AnimatedBranchContainer
    // renders the directional slide for the branch change.
    _ctrl.stop();
    setState(() => _offset = 0);
    widget.navigationShell.goBranch(targetIdx);
  }

  @override
  Widget build(BuildContext context) {
    final swipeBlocked = ref.watch(navSwipeBlockedProvider);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        if (swipeBlocked) return;
        _ctrl.stop();
        _dragging = true;
        _rawDrag = 0;
      },
      onHorizontalDragUpdate: (details) {
        if (swipeBlocked || !_dragging) return;
        _rawDrag += details.delta.dx;
        setState(() => _offset += details.delta.dx * 0.35);
      },
      onHorizontalDragEnd: (details) {
        if (swipeBlocked) {
          _dragging = false;
          _snapBack();
          return;
        }
        if (!_dragging) return;
        _dragging = false;

        final v = details.primaryVelocity ?? 0;
        final sw = MediaQuery.of(context).size.width;

        // Commit on a fast flick (mobile) OR a long-enough drag (web mouse).
        final commitByVelocity = v.abs() >= 300;
        final commitByDistance = _rawDrag.abs() / sw >= 0.28;
        if (!commitByVelocity && !commitByDistance) {
          _snapBack();
          return;
        }

        // Prefer velocity sign; fall back to raw drag for slow web drags.
        final goBack = v.abs() >= 50 ? v > 0 : _rawDrag > 0;
        final currentIdx = widget.navigationShell.currentIndex;
        final targetIdx = goBack ? currentIdx - 1 : currentIdx + 1;
        if (targetIdx < 0 || targetIdx >= kSwipeNavRoutes.length) {
          _snapBack();
          return;
        }
        _commitNavigate(targetIdx);
      },
      onHorizontalDragCancel: () {
        _dragging = false;
        _snapBack();
      },
      child: Transform.translate(
        offset: Offset(_offset, 0),
        child: widget.child,
      ),
    );
  }
}
