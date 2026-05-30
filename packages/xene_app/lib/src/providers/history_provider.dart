import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';

import '../models/user_media_item.dart';
import 'auth_provider.dart';
import 'dio_provider.dart';

final historyProvider =
    StateNotifierProvider<HistoryNotifier, List<HistoryItem>>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  final isAnon = ref.watch(isAnonymousProvider);
  return HistoryNotifier(dio: dio, isAnon: isAnon);
});

class HistoryNotifier extends StateNotifier<List<HistoryItem>> {
  HistoryNotifier({required dio, required bool isAnon})
      : _dio = dio,
        _isAnon = isAnon,
        super([]) {
    if (!isAnon) _load();
  }

  final _dio;
  final bool _isAnon;

  Future<void> _load() async {
    try {
      final resp = await _dio.get<List<dynamic>>('/user/history');
      final items = (resp.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(HistoryItem.fromJson)
          .toList();
      state = items;
    } catch (_) {}
  }

  Future<void> logPlay(QueueItem item) async {
    await _logPlayBody(item.toPostBody());
  }

  Future<void> logFeedPlay(FeedItem item) async {
    await _logPlayBody({
      'platform': item.platform.toLowerCase(),
      'external_url': item.externalUrl,
      if (item.id.isNotEmpty) 'track_id': item.id,
      if (item.title != null) 'title': item.title,
      if (item.artistName.isNotEmpty) 'artist_name': item.artistName,
      if (item.artworkUrl != null) 'artwork_url': item.artworkUrl,
      if (item.durationSeconds != null)
        'duration_seconds': item.durationSeconds,
    });
  }

  Future<void> _logPlayBody(Map<String, dynamic> body) async {
    if (_isAnon) return;
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/user/history',
        data: body,
      );
      final logged = HistoryItem.fromJson(resp.data!);
      state = [logged, ...state];
    } catch (_) {}
  }
}
