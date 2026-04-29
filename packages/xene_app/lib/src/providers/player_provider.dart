import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:xene_domain/xene_domain.dart';

/// ELI5: The "Music Engine." 
/// This is the machine that actually plays the songs. 
/// Every other part of the app just tells this machine what to do.
final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier();
});

class PlayerState {
  PlayerState({
    this.currentTrack,
    this.isPlaying = false,
  });

  final FeedItem? currentTrack;
  final bool isPlaying;

  PlayerState copyWith({
    FeedItem? currentTrack,
    bool? isPlaying,
  }) {
    return PlayerState(
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}

class PlayerNotifier extends StateNotifier<PlayerState> {
  PlayerNotifier() : super(PlayerState()) {
    // Listen to the actual audio player to keep our state in sync
    _audioPlayer.playerStateStream.listen((state) {
      this.state = this.state.copyWith(
        isPlaying: state.playing,
      );
    });
  }

  final AudioPlayer _audioPlayer = AudioPlayer();

  /// ELI5: Loading a "Disc" into the player and hitting play.
  Future<void> playTrack(FeedItem item) async {
    state = state.copyWith(currentTrack: item);
    
    // For SoundCloud, we'd normally need a stream URL. 
    // In this scaffold, we'll try to play the mediaUrl if it exists.
    if (item.mediaUrl != null) {
      try {
        await _audioPlayer.setUrl(item.mediaUrl!);
        await _audioPlayer.play();
      } catch (e) {
        print('Error playing audio: $e');
      }
    }
  }

  Future<void> togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
