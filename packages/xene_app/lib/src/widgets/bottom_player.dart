import 'package:flutter/material.dart';

class BottomPlayer extends StatelessWidget {
  const BottomPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Color(0xFF333333), width: 1)),
      ),
      child: const Center(
        child: Text(
          'PLAYER CONTROLS', 
          style: TextStyle(
            color: Colors.white, 
            letterSpacing: 2,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}