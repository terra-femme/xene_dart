import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:xene_domain/xene_domain.dart';

enum ActivePlatform { none, soundcloud, youtube }

bool canPlayInApp(FeedItem item) {
  switch (item.platform.toLowerCase()) {
    case 'soundcloud':
    case 'youtube':
      return true;
    default:
      return false;
  }
}

class PlayerState {
  PlayerState({
    this.currentTrack,
    this.isPlaying = false,
    this.activePlatform = ActivePlatform.none,
    this.isVisible = false,
  });

  final FeedItem? currentTrack;
  final bool isPlaying;
  final ActivePlatform activePlatform;
  final bool isVisible;

  PlayerState copyWith({
    FeedItem? currentTrack,
    bool? isPlaying,
    ActivePlatform? activePlatform,
    bool? isVisible,
  }) {
    return PlayerState(
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      activePlatform: activePlatform ?? this.activePlatform,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((
  ref,
) {
  return PlayerNotifier();
});

class PlayerNotifier extends StateNotifier<PlayerState> {
  PlayerNotifier() : super(PlayerState()) {
    _audioPlayer.playerStateStream.listen((state) {
      this.state = this.state.copyWith(isPlaying: state.playing);

      // Auto-hide when track finishes
      if (state.processingState == ProcessingState.completed) {
        stopAndHide();
      }
    });
  }

  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> playTrack(FeedItem item) async {
    print('[Player] Attempting to play track: ${item.title} (ID: ${item.id})');

    if (!canPlayInApp(item)) {
      print('[Player] Skipping unsupported in-app playback: ${item.platform}');
      return;
    }

    // Explicitly hide PiP before starting the delay to ensure the modal slides down first
    state = state.copyWith(isVisible: false);

    final platform = switch (item.platform.toLowerCase()) {
      'soundcloud' => ActivePlatform.soundcloud,
      'youtube' => ActivePlatform.youtube,
      _ => ActivePlatform.none,
    };

    // Stop current if switching
    if (state.activePlatform != platform &&
        state.activePlatform != ActivePlatform.none) {
      await _audioPlayer.stop();
    }

    // Set track data but keep invisible initially for the cascade effect
    state = state.copyWith(
      currentTrack: item,
      activePlatform: platform,
      isVisible: false,
    );

    // Cascade Delay: Wait for the modal to slide down ~90% (approx 350ms)
    // before making the PiP player visible and starting its slide-in.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) {
        state = state.copyWith(isVisible: true);
      }
    });

    // SoundCloud use case: The Widget handles playback, but we might still want to track state.
    // For now, we only use just_audio if we have a direct streamUrl.
    String? streamUrl = item.mediaUrl;

    if (streamUrl != null && streamUrl.isNotEmpty) {
      try {
        await _audioPlayer.setUrl(streamUrl);
        await _audioPlayer.play();
      } catch (e) {
        print('[Player] ERROR during playback: $e');
      }
    }
  }

  void stopAndHide() {
    _audioPlayer.stop();
    state = state.copyWith(
      isVisible: false,
      activePlatform: ActivePlatform.none,
      currentTrack: null,
    );
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
