import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';

import '../models/user_media_item.dart';
import '../platform/autoplay_listener_stub.dart'
    if (dart.library.html) '../platform/autoplay_listener_web.dart';
import 'auth_provider.dart';
import 'dio_provider.dart';
import 'history_provider.dart';

class QueueState {
  const QueueState({
    this.items = const [],
    this.currentIndex = 0,
    this.isShuffle = false,
    this.isLoaded = false,
    this.soundCloudPlaylistUrl,
    this.isPreparingSoundCloudPlaylist = false,
  });

  final List<QueueItem> items;
  final int currentIndex;
  final bool isShuffle;
  final bool isLoaded;
  final String? soundCloudPlaylistUrl;
  final bool isPreparingSoundCloudPlaylist;

  QueueItem? get currentItem => items.isNotEmpty && currentIndex < items.length
      ? items[currentIndex]
      : null;

  bool get hasNext => items.length > 1;
  bool get hasPrev => currentIndex > 0;

  QueueState copyWith({
    List<QueueItem>? items,
    int? currentIndex,
    bool? isShuffle,
    bool? isLoaded,
    String? soundCloudPlaylistUrl,
    bool clearSoundCloudPlaylistUrl = false,
    bool? isPreparingSoundCloudPlaylist,
  }) => QueueState(
    items: items ?? this.items,
    currentIndex: currentIndex ?? this.currentIndex,
    isShuffle: isShuffle ?? this.isShuffle,
    isLoaded: isLoaded ?? this.isLoaded,
    soundCloudPlaylistUrl: clearSoundCloudPlaylistUrl
        ? null
        : soundCloudPlaylistUrl ?? this.soundCloudPlaylistUrl,
    isPreparingSoundCloudPlaylist:
        isPreparingSoundCloudPlaylist ?? this.isPreparingSoundCloudPlaylist,
  );
}

final queueProvider = StateNotifierProvider<QueueNotifier, QueueState>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  final isAnon = ref.watch(isAnonymousProvider);
  return QueueNotifier(dio: dio, isAnon: isAnon, ref: ref);
});

class QueueNotifier extends StateNotifier<QueueState> {
  QueueNotifier({required Dio dio, required bool isAnon, required Ref ref})
    : _dio = dio,
      _isAnon = isAnon,
      _ref = ref,
      super(const QueueState()) {
    if (!isAnon) {
      _load();
      setupAutoplayListener(_onTrackEnded);
    }
  }

  final Dio _dio;
  final bool _isAnon;
  final Ref _ref;
  final _rng = Random();

  Future<void> _load() async {
    try {
      final resp = await _dio.get<List<dynamic>>('/user/queue');
      final items = (resp.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(QueueItem.fromJson)
          .toList();
      state = state.copyWith(items: items, isLoaded: true);
    } catch (_) {
      state = state.copyWith(isLoaded: true);
    }
  }

  Future<void> addItem(FeedItem feedItem) async {
    if (_isAnon) return;
    if (state.items.any((i) => i.externalUrl == feedItem.externalUrl)) return;

    final optimisticItem = QueueItem(
      id: 'pending_${feedItem.platform}_${feedItem.externalUrl.hashCode}_${DateTime.now().microsecondsSinceEpoch}',
      platform: feedItem.platform.toLowerCase(),
      externalUrl: feedItem.externalUrl,
      position: state.items.length,
      trackId: feedItem.id.isNotEmpty ? feedItem.id : null,
      title: feedItem.title,
      artistName: feedItem.artistName.isNotEmpty ? feedItem.artistName : null,
      artworkUrl: feedItem.artworkUrl,
      durationSeconds: feedItem.durationSeconds,
    );
    final previousItems = state.items;
    state = state.copyWith(
      items: [...state.items, optimisticItem],
      clearSoundCloudPlaylistUrl: optimisticItem.platform == 'soundcloud',
    );

    try {
      final body = {
        'platform': feedItem.platform.toLowerCase(),
        'external_url': feedItem.externalUrl,
        if (feedItem.id.isNotEmpty) 'track_id': feedItem.id,
        if (feedItem.title != null) 'title': feedItem.title,
        if (feedItem.artistName.isNotEmpty) 'artist_name': feedItem.artistName,
        if (feedItem.artworkUrl != null) 'artwork_url': feedItem.artworkUrl,
        if (feedItem.durationSeconds != null)
          'duration_seconds': feedItem.durationSeconds,
      };
      final resp = await _dio.post<Map<String, dynamic>>(
        '/user/queue',
        data: body,
      );
      final newItem = QueueItem.fromJson(resp.data!);
      state = state.copyWith(
        items: state.items
            .map((item) => item.id == optimisticItem.id ? newItem : item)
            .toList(),
        clearSoundCloudPlaylistUrl: newItem.platform == 'soundcloud',
      );
    } on DioException catch (e) {
      // 409 = already in queue — silently ignore
      if (e.response?.statusCode == 409) {
        await _load();
        return;
      }
      state = state.copyWith(items: previousItems);
      return;
    } catch (_) {
      state = state.copyWith(items: previousItems);
      return;
    }
  }

  Future<void> removeItem(String id) async {
    if (_isAnon) return;
    final prevItems = state.items;
    final newItems = prevItems.where((i) => i.id != id).toList();
    // Optimistic update
    state = state.copyWith(
      items: newItems,
      currentIndex: state.currentIndex.clamp(
        0,
        (newItems.length - 1).clamp(0, 9999),
      ),
      clearSoundCloudPlaylistUrl: prevItems.any(
        (item) => item.id == id && item.platform == 'soundcloud',
      ),
    );
    try {
      await _dio.delete('/user/queue/$id');
    } catch (_) {
      // Rollback on failure
      state = state.copyWith(items: prevItems);
    }
  }

  Future<void> prepareSoundCloudPlaylist({int? startIndex}) async {
    if (_isAnon || state.isPreparingSoundCloudPlaylist) return;
    final hasSoundCloud = state.items.any(
      (item) => item.platform.toLowerCase() == 'soundcloud',
    );
    if (!hasSoundCloud) return;

    state = state.copyWith(
      isPreparingSoundCloudPlaylist: true,
      clearSoundCloudPlaylistUrl: true,
    );
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/user/queue/sc_playlist',
        data: {if (startIndex != null) 'start_index': startIndex},
      );
      final playlistUrl = resp.data?['playlist_url'] as String?;
      if (playlistUrl != null && playlistUrl.isNotEmpty) {
        state = state.copyWith(soundCloudPlaylistUrl: playlistUrl);
      }
    } on DioException {
      state = state.copyWith(clearSoundCloudPlaylistUrl: true);
    } finally {
      state = state.copyWith(isPreparingSoundCloudPlaylist: false);
    }
  }

  void setIndex(int index) {
    if (index < 0 || index >= state.items.length) return;
    state = state.copyWith(currentIndex: index);
  }

  void advance() {
    final items = state.items;
    if (items.isEmpty) return;
    final next = state.isShuffle
        ? _rng.nextInt(items.length)
        : (state.currentIndex + 1) % items.length;
    state = state.copyWith(currentIndex: next);
  }

  void advanceAutoplay() {
    final items = state.items;
    if (items.isEmpty) return;
    if (state.isShuffle) {
      advance();
      return;
    }

    final orderedIndices = [
      ..._indicesForPlatform('soundcloud'),
      ..._indicesForPlatform('youtube'),
      ...items
          .asMap()
          .entries
          .where((entry) {
            final platform = entry.value.platform.toLowerCase();
            return platform != 'soundcloud' && platform != 'youtube';
          })
          .map((entry) => entry.key),
    ];

    final currentOrderIndex = orderedIndices.indexOf(state.currentIndex);
    if (currentOrderIndex < 0) {
      advance();
      return;
    }

    final current = state.currentItem;
    if (current?.platform.toLowerCase() == 'soundcloud' &&
        state.soundCloudPlaylistUrl != null) {
      final nextNonSoundCloud = orderedIndices.firstWhere(
        (index) => items[index].platform.toLowerCase() != 'soundcloud',
        orElse: () => orderedIndices.first,
      );
      state = state.copyWith(currentIndex: nextNonSoundCloud);
      return;
    }

    final nextOrderIndex = (currentOrderIndex + 1) % orderedIndices.length;
    state = state.copyWith(currentIndex: orderedIndices[nextOrderIndex]);
  }

  Iterable<int> _indicesForPlatform(String platform) => state.items
      .asMap()
      .entries
      .where((entry) => entry.value.platform.toLowerCase() == platform)
      .map((entry) => entry.key);

  void previous() {
    if (state.items.isEmpty) return;
    final prev = (state.currentIndex - 1).clamp(0, state.items.length - 1);
    state = state.copyWith(currentIndex: prev);
  }

  void toggleShuffle() => state = state.copyWith(isShuffle: !state.isShuffle);

  void logCurrentPlay() {
    final current = state.currentItem;
    if (current == null) return;
    _ref.read(historyProvider.notifier).logPlay(current);
  }

  void _onTrackEnded() {
    advanceAutoplay();
    logCurrentPlay();
  }
}
