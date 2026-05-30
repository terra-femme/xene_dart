import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';

import '../models/user_media_item.dart';
import 'auth_provider.dart';
import 'dio_provider.dart';

final savedProvider = StateNotifierProvider<SavedNotifier, List<SavedItem>>((
  ref,
) {
  final dio = ref.watch(authenticatedDioProvider);
  final isAnon = ref.watch(isAnonymousProvider);
  return SavedNotifier(dio: dio, isAnon: isAnon);
});

class SavedNotifier extends StateNotifier<List<SavedItem>> {
  SavedNotifier({required dio, required bool isAnon})
    : _dio = dio,
      _isAnon = isAnon,
      super([]) {
    if (!isAnon) _load();
  }

  final _dio;
  final bool _isAnon;

  Future<void> _load() async {
    try {
      final resp = await _dio.get<List<dynamic>>('/user/saved');
      final items = (resp.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(SavedItem.fromJson)
          .toList();
      state = items;
    } catch (_) {}
  }

  Future<void> bookmark(QueueItem item) async {
    if (_isAnon) return;
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/user/saved',
        data: item.toPostBody(),
      );
      final saved = SavedItem.fromJson(resp.data!);
      state = [saved, ...state.where((s) => s.id != saved.id)];
    } catch (_) {
      // 409 = already saved — silently ignore
    }
  }

  Future<void> bookmarkFeedItem(FeedItem item) async {
    await bookmark(
      QueueItem(
        id: item.id,
        platform: item.platform.toLowerCase(),
        externalUrl: item.externalUrl,
        position: 0,
        trackId: item.id.isNotEmpty ? item.id : null,
        title: item.title,
        artistName: item.artistName.isNotEmpty ? item.artistName : null,
        artworkUrl: item.artworkUrl,
        durationSeconds: item.durationSeconds,
      ),
    );
  }

  bool isBookmarked(String externalUrl) {
    final normalized = _bookmarkUrlKey(externalUrl);
    return state.any((s) => _bookmarkUrlKey(s.externalUrl) == normalized);
  }

  SavedItem? matchForUrl(String externalUrl) {
    final normalized = _bookmarkUrlKey(externalUrl);
    for (final item in state) {
      if (_bookmarkUrlKey(item.externalUrl) == normalized) return item;
    }
    return null;
  }

  Future<void> unbookmark(String id) async {
    if (_isAnon) return;
    final prev = state;
    state = state.where((s) => s.id != id).toList();
    try {
      await _dio.delete('/user/saved/$id');
    } catch (_) {
      state = prev;
    }
  }

  Future<String?> exportToScPlaylist() async {
    if (_isAnon) return null;
    final resp = await _dio.post<Map<String, dynamic>>('/user/saved/export_sc');
    return resp.data?['playlist_url'] as String?;
  }

  String _bookmarkUrlKey(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    final filteredQuery = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((key, _) => key.startsWith('utm_'));
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          queryParameters: filteredQuery.isEmpty ? null : filteredQuery,
          fragment: '',
        )
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }
}
