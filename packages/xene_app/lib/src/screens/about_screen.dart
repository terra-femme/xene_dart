import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'ABOUT',
        style: GoogleFonts.teko(
          fontSize: 32,
          color: const Color(0xFFA3A3A3),
          letterSpacing: 2,
        ),
      ),
    );
  }
}
