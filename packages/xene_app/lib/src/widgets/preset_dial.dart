import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_app/src/providers/preset_provider.dart';

class PresetDial extends StatefulWidget {
  const PresetDial({
    super.key,
    required this.slots,
    required this.activeSlug,
    required this.onChanged,
    this.tickCount = 12,
    this.knobSize = 92,
  });

  final List<PresetSlot> slots;
  final String activeSlug;
  final ValueChanged<PresetSlot> onChanged;
  final int tickCount;
  final double knobSize;

  @override
  State<PresetDial> createState() => _PresetDialState();
}

class _PresetDialState extends State<PresetDial>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  double _currentAngle = 0;
  int _lastTickIndex = 0;
  bool _isLongPressing = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1, end: 1.22).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );
    _syncFromActiveSlug();
  }

  @override
  void didUpdateWidget(covariant PresetDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSlug != widget.activeSlug ||
        oldWidget.slots != widget.slots) {
      _syncFromActiveSlug();
    }
  }

  @override
  void dispose() {
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
  }

  double get _segmentSize => (2 * math.pi) / widget.tickCount;

  void _handleTap() {
    final slots = widget.slots;
    if (slots.isEmpty) return;

    final sorted = List<PresetSlot>.from(slots)
      ..sort((a, b) => a.notchIndex.compareTo(b.notchIndex));
    final currentSlotIndex = sorted.indexWhere(
      (slot) => slot.slug == widget.activeSlug,
    );
    final nextSlot = sorted[(currentSlotIndex + 1) % sorted.length];
    _selectSlot(nextSlot);
    HapticFeedback.lightImpact();
  }

  void _handleRotationUpdate(Offset localPosition) {
    final center = Offset(widget.knobSize / 2, widget.knobSize / 2);
    final relativePoint = localPosition - center;

    final rawAngle = math.atan2(relativePoint.dy, relativePoint.dx);
    var normalizedAngle = (rawAngle + (math.pi / 2)) % (2 * math.pi);
    if (normalizedAngle < 0) normalizedAngle += 2 * math.pi;

    setState(() => _currentAngle = normalizedAngle);
    _checkHapticTick(normalizedAngle);
  }

  void _checkHapticTick(double angle) {
    final tickIndex = (angle / _segmentSize).round() % widget.tickCount;
    if (tickIndex == _lastTickIndex) return;

    final slot = _slotsByTick[tickIndex];
    if (slot == null) return;

    HapticFeedback.mediumImpact();
    _selectSlot(slot);
  }

  void _selectSlot(PresetSlot slot) {
    setState(() {
      _lastTickIndex = slot.notchIndex;
      _currentAngle = slot.notchIndex * _segmentSize;
    });
    widget.onChanged(slot);
  }

  void _handleRotationEnd() {
    setState(() {
      _currentAngle = _lastTickIndex * _segmentSize;
      _isLongPressing = false;
    });
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slots.isEmpty) return const SizedBox.shrink();

    final activeSlot = _activeSlot;
    final outerSize = widget.knobSize + 40;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (_isLongPressing)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.black12),
            ),
          ),
        GestureDetector(
          onTap: _handleTap,
          onPanUpdate: (details) {
            if (!_isDragging) setState(() => _isDragging = true);
            _handleRotationUpdate(details.localPosition);
          },
          onPanEnd: (_) {
            setState(() => _isDragging = false);
            _handleRotationEnd();
          },
          onLongPressStart: (_) {
            setState(() => _isLongPressing = true);
            _scaleController.forward();
            HapticFeedback.heavyImpact();
          },
          onLongPressMoveUpdate: (details) {
            _handleRotationUpdate(details.localPosition);
          },
          onLongPressEnd: (_) => _handleRotationEnd(),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: SizedBox(
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
            ),
          ),
        ),
        Positioned(
          bottom: -34,
          child: AnimatedSwitcher(
            duration: (_isLongPressing || _isDragging)
                ? Duration.zero
                : const Duration(milliseconds: 250),
            child: Builder(
              builder: (_) {
                // Always use the local tick index when a slot sits there —
                // avoids the provider round-trip delay on regular pan too.
                final displaySlot = _slotsByTick.containsKey(_lastTickIndex)
                    ? _slotsByTick[_lastTickIndex]!
                    : activeSlot;
                return Text(
                  displaySlot.name.toUpperCase(),
                  key: ValueKey(displaySlot.slug),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.teko(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: displaySlot.themeColor,
                    letterSpacing: 2,
                  ),
                );
              },
            ),
          ),
        ),
      ],
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
