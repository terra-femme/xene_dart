import 'package:flutter/material.dart';

class PlatformBadge extends StatelessWidget {
  const PlatformBadge({super.key, required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (platform.toLowerCase()) {
      case 'soundcloud':
        color = const Color(0xFFFF5500);
      case 'youtube':
        color = const Color(0xFFFF0000);
      case 'bandcamp':
        color = const Color(0xFF629AA9);
      case 'beatport':
        color = const Color(0xFF01FF95);
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        platform.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
