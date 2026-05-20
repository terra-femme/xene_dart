import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_app/src/layout/xene_responsive_debug.dart';
import 'package:xene_app/src/providers/preset_provider.dart';

// PROTECTED UI SURFACE - DO NOT REFACTOR CASUALLY.
//
// This dial's long-press overlay, label ownership, release-settle delay, and
// sizing anchors are deliberate. They prevent clipping, article overlap, and
// label disappearance during preset preview/commit. Any coding agent or
// developer must not rewrite this into normal sidebar layout, remove the overlay
// timing, or alter label anchoring unless the user explicitly asks for changes
// to the preset dial interaction.

class PresetDial extends StatefulWidget {
  const PresetDial({
    super.key,
    required this.slots,
    required this.activeSlug,
    required this.onChanged,
    this.tickCount = 12,
    this.knobSize = 92,
    this.reservedWidth,
    this.reservedHeight,
    this.onOverlayChanged,
  });

  final List<PresetSlot> slots;
  final String activeSlug;
  final ValueChanged<PresetSlot> onChanged;
  final int tickCount;
  final double knobSize;
  final double? reservedWidth;
  final double? reservedHeight;
  final ValueChanged<bool>? onOverlayChanged;

  @override
  State<PresetDial> createState() => _PresetDialState();
}

class _PresetDialState extends State<PresetDial>
    with SingleTickerProviderStateMixin {
  static const double _scalePeak = 1.22;

  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _interactiveDialKey = GlobalKey();

  double _currentAngle = 0;
  int _lastTickIndex = 0;
  PresetSlot?
  _displaySlot; // locally-owned, never driven by provider during interaction
  bool _isLongPressing = false;
  bool _isDragging = false;
  bool _isReleaseSettling = false;
  Timer? _longPressTimer;
  Timer? _overlayRemovalTimer;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1, end: _scalePeak).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );
    _scaleController
      ..addListener(_markOverlayNeedsBuild)
      ..addStatusListener(_handleScaleStatus);
    _syncFromActiveSlug();
  }

  @override
  void didUpdateWidget(covariant PresetDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Never let provider rebuilds overwrite local state during an active
    // gesture or the short release settle window.
    if (_isDragging || _isLongPressing || _isReleaseSettling) return;
    if (oldWidget.activeSlug != widget.activeSlug ||
        oldWidget.slots != widget.slots) {
      _syncFromActiveSlug();
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _overlayRemovalTimer?.cancel();
    _removeOverlay();
    _scaleController
      ..removeListener(_markOverlayNeedsBuild)
      ..removeStatusListener(_handleScaleStatus);
    _scaleController.dispose();
    super.dispose();
  }

  PresetSlot get _activeSlot {
    return widget.slots.firstWhere(
      (slot) => slot.slug == widget.activeSlug,
      orElse: () => widget.slots.first,
    );
  }

  Map<int, PresetSlot> get _slotsByTick {
    return {for (final slot in widget.slots) slot.notchIndex: slot};
  }

  void _syncFromActiveSlug() {
    if (widget.slots.isEmpty) return;
    final slot = _activeSlot;
    final nextIndex = slot.notchIndex.clamp(0, widget.tickCount - 1);
    _lastTickIndex = nextIndex;
    _currentAngle = nextIndex * _segmentSize;
    _displaySlot = slot;
  }

  double get _segmentSize => (2 * math.pi) / widget.tickCount;
  double get _outerSize => widget.knobSize + 40;
  double get _reservedWidth =>
      widget.reservedWidth ?? math.max(150.0, _outerSize);
  double get _reservedHeight => widget.reservedHeight ?? _outerSize + 34;

  double get _renderedInteractiveOuterSize {
    final renderObject = _interactiveDialKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return math.min(renderObject.size.width, renderObject.size.height);
    }
    return _outerSize;
  }

  void _markOverlayNeedsBuild() {
    _overlayEntry?.markNeedsBuild();
  }

  void _handleScaleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_isLongPressing) {
      _scheduleOverlayRemoval();
    }
  }

  void _scheduleOverlayRemoval() {
    _overlayRemovalTimer?.cancel();
    // Release invariant: keep the overlay alive briefly after scale-down so
    // preset/article provider refreshes cannot expose or cover the in-layout
    // label mid-transition. Do not remove this delay without visual QA.
    _overlayRemovalTimer = Timer(const Duration(milliseconds: 350), () {
      _overlayRemovalTimer = null;
      _removeOverlay();
      if (!mounted || !_isReleaseSettling) return;
      setState(() => _isReleaseSettling = false);
    });
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    widget.onOverlayChanged?.call(true);

    // Interaction invariant: the expanded dial/label belongs in this overlay,
    // not in sidebar layout boxes. Moving it back into layout reintroduces
    // clipping, article overlap, and release-time label flicker.
    _overlayEntry = OverlayEntry(
      builder: (context) {
        final overlayExpanded =
            _isLongPressing || _scaleController.value > 0.01;
        return Positioned.fill(
          child: IgnorePointer(
            child: Stack(
              children: [
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                CompositedTransformFollower(
                  link: _layerLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.topCenter,
                  followerAnchor: Alignment.topCenter,
                  child: Material(
                    type: MaterialType.transparency,
                    child: _buildDialFrame(expanded: overlayExpanded),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    widget.onOverlayChanged?.call(false);
  }

  void _handleTap() {
    final slots = widget.slots;
    if (slots.isEmpty) return;

    final sorted = List<PresetSlot>.from(slots)
      ..sort((a, b) => a.notchIndex.compareTo(b.notchIndex));
    // Use local _lastTickIndex as the current position — not widget.activeSlug —
    // so rapid taps advance correctly even if the provider hasn't caught up yet.
    final currentSlotIndex = sorted.indexWhere(
      (slot) => slot.notchIndex == _lastTickIndex,
    );
    final nextSlot = sorted[(currentSlotIndex + 1) % sorted.length];
    _selectSlot(nextSlot);
    HapticFeedback.lightImpact();
  }

  void _beginLongPress() {
    if (_isLongPressing) return;
    _overlayRemovalTimer?.cancel();
    _overlayRemovalTimer = null;
    setState(() {
      _isLongPressing = true;
      _isReleaseSettling = false;
    });
    _showOverlay();
    _scaleController.forward();
    HapticFeedback.heavyImpact();
  }

  // Returns the occupied slot whose notch is angularly closest to [angle].
  PresetSlot? _nearestSlot(double angle) {
    if (_slotsByTick.isEmpty) return null;
    final rawTick = angle / _segmentSize;
    PresetSlot? nearest;
    double minDist = double.infinity;
    for (final entry in _slotsByTick.entries) {
      final diff = (entry.key.toDouble() - rawTick).abs();
      final wrapped = math.min(diff, widget.tickCount.toDouble() - diff);
      if (wrapped < minDist) {
        minDist = wrapped;
        nearest = entry.value;
      }
    }
    return nearest;
  }

  void _handleRotationUpdate(Offset localPosition) {
    final outerSize = _renderedInteractiveOuterSize;
    final center = Offset(outerSize / 2, outerSize / 2);
    final relativePoint = localPosition - center;

    final rawAngle = math.atan2(relativePoint.dy, relativePoint.dx);
    var normalizedAngle = (rawAngle + (math.pi / 2)) % (2 * math.pi);
    if (normalizedAngle < 0) normalizedAngle += 2 * math.pi;

    // Update knob angle AND nearest-preset label in one setState so the
    // label is never frozen between occupied ticks.
    final nearest = _nearestSlot(normalizedAngle);
    setState(() {
      _currentAngle = normalizedAngle;
      if (nearest != null && nearest.slug != _displaySlot?.slug) {
        _displaySlot = nearest;
      }
    });
    _markOverlayNeedsBuild();

    _checkHapticTick(normalizedAngle);
  }

  void _checkHapticTick(double angle) {
    final tickIndex = (angle / _segmentSize).round() % widget.tickCount;
    if (tickIndex == _lastTickIndex) return;

    final slot = _slotsByTick[tickIndex];
    if (slot == null) return;

    HapticFeedback.mediumImpact();
    if (_isLongPressing) {
      // Preview only — commit deferred to pointer-up so the feed
      // doesn't reload on every tick crossing during dial rotation.
      setState(() {
        _lastTickIndex = slot.notchIndex;
        _currentAngle = slot.notchIndex * _segmentSize;
        _displaySlot = slot;
      });
      _markOverlayNeedsBuild();
    } else {
      _selectSlot(slot);
    }
  }

  void _selectSlot(PresetSlot slot) {
    setState(() {
      _lastTickIndex = slot.notchIndex;
      _currentAngle = slot.notchIndex * _segmentSize;
      _displaySlot = slot; // set before provider update so label is instant
    });
    widget.onChanged(slot);
  }

  void _handleRotationEnd() {
    final wasLongPressing = _isLongPressing;
    final settledSlot = _slotsByTick[_lastTickIndex];
    final nearest = _nearestSlot(_currentAngle);
    setState(() {
      _currentAngle = _lastTickIndex * _segmentSize;
      _displaySlot = nearest ?? settledSlot ?? _displaySlot;
      _isLongPressing = false;
      _isReleaseSettling = wasLongPressing;
    });
    _markOverlayNeedsBuild();
    _scaleController.reverse();
    // Commit once on release — prevents feed reload on every tick during long-press.
    if (wasLongPressing &&
        settledSlot != null &&
        settledSlot.slug != widget.activeSlug) {
      widget.onChanged(settledSlot);
    }
  }

  Widget _buildDialGraphic({required bool expanded}) {
    final outerSize = _outerSize;
    final dial = SizedBox(
      width: outerSize,
      height: outerSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(outerSize, outerSize),
            painter: PresetDialTicksPainter(
              tickCount: widget.tickCount,
              activeTicks: _slotsByTick.keys.toSet(),
            ),
          ),
          Transform.rotate(
            angle: _currentAngle,
            child: Container(
              width: widget.knobSize - 26,
              height: widget.knobSize - 26,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 15,
                    spreadRadius: 2,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 13),
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!expanded) return dial;
    return ScaleTransition(scale: _scaleAnimation, child: dial);
  }

  Widget _buildDialLabel({required bool expanded}) {
    final label = _displaySlot ?? _activeSlot;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: FittedBox(
        key: ValueKey(label.slug),
        fit: BoxFit.scaleDown,
        child: Text(
          label.name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: GoogleFonts.teko(
            fontSize: expanded ? 28 : 24,
            fontWeight: FontWeight.bold,
            color: label.themeColor,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildDialFrame({required bool expanded}) {
    final outerSize = _outerSize;
    final frameWidth = expanded
        ? math.max(_reservedWidth, 220.0)
        : _reservedWidth;

    // Anchor invariant: keep the frame height and label bottom fixed while the
    // dial grows upward/outward. A taller expanded frame makes the label appear
    // to slide into the articles dock.
    return SizedBox(
      width: frameWidth,
      height: _reservedHeight,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: expanded ? -16 : 0,
            width: outerSize,
            height: outerSize,
            child: _buildDialGraphic(expanded: expanded),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(child: _buildDialLabel(expanded: expanded)),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveDial() {
    final outerSize = _outerSize;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        _longPressTimer?.cancel();
        _longPressTimer = Timer(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          _beginLongPress();
        });
      },
      onPointerMove: (event) {
        if (_isLongPressing) _handleRotationUpdate(event.localPosition);
      },
      onPointerUp: (_) {
        _longPressTimer?.cancel();
        _longPressTimer = null;
        if (_isLongPressing) _handleRotationEnd();
      },
      onPointerCancel: (_) {
        _longPressTimer?.cancel();
        _longPressTimer = null;
        if (_isLongPressing) _handleRotationEnd();
      },
      child: GestureDetector(
        onTap: _handleTap,
        onPanUpdate: (details) {
          if (_isLongPressing) return;
          if (!_isDragging) setState(() => _isDragging = true);
          _handleRotationUpdate(details.localPosition);
        },
        onPanEnd: (_) {
          if (_isLongPressing) return;
          setState(() => _isDragging = false);
          _handleRotationEnd();
        },
        onPanCancel: () {
          if (_isLongPressing) return;
          setState(() => _isDragging = false);
          _handleRotationEnd();
        },
        child: SizedBox(
          key: _interactiveDialKey,
          width: outerSize,
          height: outerSize,
          child: _buildDialGraphic(expanded: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slots.isEmpty) return const SizedBox.shrink();

    final outerSize = _outerSize;
    XeneResponsiveDebug.values('PresetDial.geometry', {
      'knobSize': widget.knobSize,
      'outerSize': outerSize,
      'reservedWidth': _reservedWidth,
      'reservedHeight': _reservedHeight,
      'tickCount': widget.tickCount,
    });

    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: _reservedWidth,
        height: _reservedHeight,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0,
              width: outerSize,
              height: outerSize,
              child: _buildInteractiveDial(),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(child: _buildDialLabel(expanded: false)),
            ),
          ],
        ),
      ),
    );
  }
}

class PresetDialTicksPainter extends CustomPainter {
  const PresetDialTicksPainter({
    required this.tickCount,
    required this.activeTicks,
  });

  final int tickCount;
  final Set<int> activeTicks;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final majorPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final inactiveMajorPaint = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final minorPaint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;

    for (var i = 0; i < 60; i++) {
      final angle = (i * 6) * math.pi / 180;
      final tickIndex = i ~/ 5;
      final isMajor = i % 5 == 0;
      final isEnabledMajor = isMajor && activeTicks.contains(tickIndex);
      final paint = isEnabledMajor
          ? majorPaint
          : isMajor
          ? inactiveMajorPaint
          : minorPaint;
      final tickLength = isEnabledMajor
          ? 12.0
          : isMajor
          ? 8.0
          : 5.0;
      final innerRadius = radius - 10;
      final outerRadius = innerRadius - tickLength;

      final start = Offset(
        center.dx + innerRadius * math.cos(angle - math.pi / 2),
        center.dy + innerRadius * math.sin(angle - math.pi / 2),
      );
      final end = Offset(
        center.dx + outerRadius * math.cos(angle - math.pi / 2),
        center.dy + outerRadius * math.sin(angle - math.pi / 2),
      );

      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PresetDialTicksPainter oldDelegate) {
    return tickCount != oldDelegate.tickCount ||
        activeTicks.length != oldDelegate.activeTicks.length ||
        !activeTicks.containsAll(oldDelegate.activeTicks);
  }
}
