import 'package:flutter/material.dart';
import 'feed_screen.dart';
import 'artists_screen.dart';
import 'network_screen.dart';
import '../widgets/bottom_player.dart';

/// ELI5: The "Home Base." 
/// This screen has the buttons at the bottom that let you jump 
/// between the Feed, your Artist list, and the Network map.
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const FeedScreen(),
    const ArtistsScreen(),
    const NetworkScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomPlayer(), // The player stays above the tabs!
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: Colors.black,
            selectedItemColor: const Color(0xFFFF5500),
            unselectedItemColor: const Color.fromARGB(61, 255, 255, 255),
            showSelectedLabels: true,
            showUnselectedLabels: true,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.feed_outlined), label: 'FEED'),
              BottomNavigationBarItem(icon: Icon(Icons.library_music_outlined), label: 'ARTISTS'),
              BottomNavigationBarItem(icon: Icon(Icons.hub_outlined), label: 'NETWORK'),
            ],
          ),
        ],
      ),
    );
  }
}
