import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// EDUCATIONAL NOTE:
/// A [Channel] represents a curated set of artists/music.
/// We use a fixed ID for logic and a Display Name for the "Pop Out" UI.
class Channel {
  final String id;
  final String name;
  final List<String> mockArtists;
  final Color themeColor;

  const Channel({
    required this.id,
    required this.name,
    required this.mockArtists,
    required this.themeColor,
  });
}

/// The 12 main "Clockwork" channels for our hardware dial.
/// Positioned at 30° intervals around the 360° circle.
final List<Channel> availableChannels = [
  const Channel(
    id: 'custom',
    name: 'CUSTOM',
    mockArtists: ['YOUR', 'SOUND', 'GOES', 'HERE'],
    themeColor: Color(0xFF222222), // Hardware Black
  ),
  const Channel(
    id: 'locked_1',
    name: 'PRESET 1',
    mockArtists: ['LOCKED'],
    themeColor: Colors.grey,
  ),
  const Channel(
    id: 'locked_2',
    name: 'PRESET 2',
    mockArtists: ['LOCKED'],
    themeColor: Colors.grey,
  ),
  const Channel(
    id: 'dnb',
    name: 'DNB',
    mockArtists: ['R3IDY', 'SPINDLE', 'YAMATAI', 'NOISIA'],
    themeColor: Color(0xFFFF5500), // Xene Orange
  ),
  const Channel(
    id: 'locked_3',
    name: 'PRESET 3',
    mockArtists: ['LOCKED'],
    themeColor: Colors.grey,
  ),
  const Channel(
    id: 'locked_4',
    name: 'PRESET 4',
    mockArtists: ['LOCKED'],
    themeColor: Colors.grey,
  ),
  const Channel(
    id: 'rnb',
    name: 'RNB',
    mockArtists: ['ERYKAH', 'DANGELO', 'MOONCHILD', 'J DILLA'],
    themeColor: Color(0xFFFFD700), // Gold
  ),
  const Channel(
    id: 'locked_5',
    name: 'PRESET 5',
    mockArtists: ['LOCKED'],
    themeColor: Colors.grey,
  ),
  const Channel(
    id: 'locked_6',
    name: 'PRESET 6',
    mockArtists: ['LOCKED'],
    themeColor: Colors.grey,
  ),
  const Channel(
    id: 'ukg',
    name: 'UKG',
    mockArtists: ['CONDUCTA', 'BKLAVA', 'P-LO', 'ZED BIAS'],
    themeColor: Color(0xFF8A2BE2), // Blue Violet
  ),
  const Channel(
    id: 'locked_7',
    name: 'PRESET 7',
    mockArtists: ['LOCKED'],
    themeColor: Colors.grey,
  ),
  const Channel(
    id: 'locked_8',
    name: 'PRESET 8',
    mockArtists: ['LOCKED'],
    themeColor: Colors.grey,
  ),
];

/// STATE MANAGEMENT EDUCATION:
/// We use a [StateProvider] to sync the Dial (Input) and the Feed (Output).
final activeChannelProvider = StateProvider<Channel>((ref) => availableChannels[0]);
