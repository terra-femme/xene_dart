import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'channel_models.dart';

class ChannelDial extends ConsumerStatefulWidget {
  const ChannelDial({super.key});

  @override
  ConsumerState<ChannelDial> createState() => _ChannelDialState();
}

class _ChannelDialState extends ConsumerState<ChannelDial> with SingleTickerProviderStateMixin {
  // The current rotation angle in RADIANS
  double _currentAngle = 0.0;
  
  // Track the last "tick" index to trigger haptics
  int _lastTickIndex = 0;

  // Animation controller for the "Pop-out" scale effect
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  // --- TUNING VARIABLES ---
  final int _tickCount = 12; // 12 Major slots
  final double _baseKnobSize = 110.0; // Reduced from 140
  bool _isLongPressing = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTap() {
    // Tap to cycle to next preset
    final nextIndex = (_lastTickIndex + 1) % _tickCount;
    _updateSelection(nextIndex);
    HapticFeedback.lightImpact();
  }

  void _updateSelection(int index) {
    final segmentSize = (2 * math.pi) / _tickCount;
    setState(() {
      _lastTickIndex = index;
      _currentAngle = index * segmentSize;
    });
    ref.read(activeChannelProvider.notifier).state = availableChannels[index];
  }

  void _handleRotationUpdate(Offset localPosition) {
    final center = Offset(_baseKnobSize / 2, _baseKnobSize / 2);
    final relativePoint = localPosition - center;

    double rawAngle = math.atan2(relativePoint.dy, relativePoint.dx);
    double normalizedAngle = (rawAngle + (math.pi / 2)) % (2 * math.pi);
    if (normalizedAngle < 0) normalizedAngle += 2 * math.pi;

    setState(() {
      _currentAngle = normalizedAngle;
    });

    _checkHapticTick(normalizedAngle);
  }

  void _checkHapticTick(double angle) {
    final segmentSize = (2 * math.pi) / _tickCount;
    // Snapping logic: Use round() for "51% closer" behavior
    int tickIndex = (angle / segmentSize).round() % _tickCount;

    if (tickIndex != _lastTickIndex) {
      HapticFeedback.mediumImpact();
      ref.read(activeChannelProvider.notifier).state = availableChannels[tickIndex];
      _lastTickIndex = tickIndex;
    }
  }

  void _handleRotationEnd() {
    final segmentSize = (2 * math.pi) / _tickCount;
    final targetAngle = _lastTickIndex * segmentSize;

    setState(() {
      _currentAngle = targetAngle;
      _isLongPressing = false;
    });
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final activeChannel = ref.watch(activeChannelProvider);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // 1. BLUR OVERLAY (Only when long pressing)
        if (_isLongPressing)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.black12),
            ),
          ),

        // 2. THE DIAL COMPONENT
        GestureDetector(
          onTap: _handleTap,
          // Standard Pan (Circular Gesture)
          onPanUpdate: (details) => _handleRotationUpdate(details.localPosition),
          onPanEnd: (_) => _handleRotationEnd(),
          // Long Press (Pop-out Tuning)
          onLongPressStart: (details) {
            setState(() => _isLongPressing = true);
            _scaleController.forward();
            HapticFeedback.heavyImpact();
          },
          onLongPressMoveUpdate: (details) => _handleRotationUpdate(details.localPosition),
          onLongPressEnd: (_) => _handleRotationEnd(),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: SizedBox(
              width: _baseKnobSize + 40,
              height: _baseKnobSize + 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // STATIC TICKS PAINTER
                  CustomPaint(
                    size: Size(_baseKnobSize + 40, _baseKnobSize + 40),
                    painter: DialTicksPainter(tickCount: _tickCount),
                  ),

                  // THE ROTATING KNOB
                  Transform.rotate(
                    angle: _currentAngle,
                    child: Container(
                      width: _baseKnobSize - 30,
                      height: _baseKnobSize - 30,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 15,
                            spreadRadius: 2,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Indicator Dot (Black)
                          Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              margin: const EdgeInsets.only(top: 15),
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
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
        ),

        // 3. POP-OUT LABEL (When Active)
        Positioned(
          bottom: -30,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // THE GLOW (Blurred text behind the main text)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Text(
                    activeChannel.name,
                    key: ValueKey('${activeChannel.id}_glow'),
                    style: GoogleFonts.teko(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                      color: activeChannel.themeColor.withOpacity(0.7),
                    ),
                  ),
                ),
                // THE SHARP TEXT
                Text(
                  activeChannel.name,
                  key: ValueKey(activeChannel.id),
                  style: GoogleFonts.teko(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    color: activeChannel.themeColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DialTicksPainter extends CustomPainter {
  final int tickCount;
  DialTicksPainter({required this.tickCount});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    final majorPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final minorPaint = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1.0;

    // 12 Major Ticks + Minor Ticks between them
    for (int i = 0; i < 60; i++) {
      final angle = (i * 6) * math.pi / 180;
      final isMajor = i % 5 == 0;
      
      final tickLength = isMajor ? 12.0 : 6.0;
      final paint = isMajor ? majorPaint : minorPaint;
      
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
