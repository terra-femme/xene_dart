import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';
import 'dio_provider.dart';
import 'feed_provider.dart';

@immutable
class PresetSource {
  const PresetSource({
    required this.id,
    required this.displayName,
    required this.enabled,
    this.artistId,
    this.soundcloudUsername,
    this.soundcloudUrl,
    this.bandcampUrl,
    this.youtubeUrl,
    this.manuallyVerified = false,
  });

  final String id;
  final String displayName;
  final bool enabled;
  final String? artistId;
  final String? soundcloudUsername;
  final String? soundcloudUrl;
  final String? bandcampUrl;
  final String? youtubeUrl;
  final bool manuallyVerified;

  factory PresetSource.fromJson(Map<String, dynamic> json) {
    final artist = json['artist'] as Map<String, dynamic>?;
    return PresetSource(
      id: json['id'] as String? ?? '',
      displayName:
          artist?['name'] as String? ??
          json['displayName'] as String? ??
          'Unknown',
      enabled: json['enabled'] != false,
      artistId: json['artistId'] as String?,
      soundcloudUsername:
          artist?['soundcloudUsername'] as String? ??
          json['soundcloudUsername'] as String?,
      soundcloudUrl:
          artist?['soundcloudUrl'] as String? ??
          json['soundcloudUrl'] as String?,
      bandcampUrl:
          artist?['bandcampUrl'] as String? ?? json['bandcampUrl'] as String?,
      youtubeUrl:
          artist?['youtubeUrl'] as String? ?? json['youtubeUrl'] as String?,
      manuallyVerified: (artist?['manuallyVerified'] as bool?) ?? false,
    );
  }
}

@immutable
class PresetSourcesState {
  const PresetSourcesState({
    this.slug,
    this.sources = const [],
    this.previewItems = const [],
    this.loadingSources = false,
    this.loadingPreview = false,
    this.loadingRefreshAll = false,
    this.error,
  });

  final String? slug;
  final List<PresetSource> sources;
  final List<FeedItem> previewItems;
  final bool loadingSources;
  final bool loadingPreview;
  final bool loadingRefreshAll;
  final String? error;

  PresetSourcesState copyWith({
    String? slug,
    List<PresetSource>? sources,
    List<FeedItem>? previewItems,
    bool? loadingSources,
    bool? loadingPreview,
    bool? loadingRefreshAll,
    String? error,
  }) {
    return PresetSourcesState(
      slug: slug ?? this.slug,
      sources: sources ?? this.sources,
      previewItems: previewItems ?? this.previewItems,
      loadingSources: loadingSources ?? this.loadingSources,
      loadingPreview: loadingPreview ?? this.loadingPreview,
      loadingRefreshAll: loadingRefreshAll ?? this.loadingRefreshAll,
      error: error,
    );
  }
}

final presetSourcesProvider =
    StateNotifierProvider<PresetSourcesNotifier, PresetSourcesState>(
      PresetSourcesNotifier.new,
    );

class PresetSourcesNotifier extends StateNotifier<PresetSourcesState> {
  PresetSourcesNotifier(this.ref) : super(const PresetSourcesState());

  final Ref ref;
  Dio? _dio;

  Dio _getDio() {
    _dio ??= ref.read(authenticatedDioProvider);
    return _dio!;
  }

  Future<void> load(String slug) async {
    if (slug.isEmpty) return;
    state = state.copyWith(
      slug: slug,
      loadingSources: true,
      previewItems: state.slug == slug ? state.previewItems : const [],
    );
    try {
      final dio = _getDio();
      final response = await dio.get<List<dynamic>>(
        '/presets/templates/$slug/sources',
      );
      final sources = (response.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(PresetSource.fromJson)
          .toList();
      state = state.copyWith(
        slug: slug,
        sources: sources,
        loadingSources: false,
      );
    } catch (e) {
      state = state.copyWith(loadingSources: false, error: _message(e));
    }
  }

  Future<void> addSoundCloudSource(
    String slug,
    Map<String, dynamic> candidate,
  ) async {
    final dio = _dio ??= _getDio();
    await dio.post<Map<String, dynamic>>(
      '/presets/templates/$slug/sources',
      data: candidate,
    );
    await load(slug);
  }

  Future<void> removeSource(String slug, String sourceId) async {
    final dio = _dio ??= _getDio();
    await dio.delete<void>(
      '/presets/templates/$slug/sources',
      queryParameters: {'source_id': sourceId},
    );
    await load(slug);
  }

  Future<Map<String, dynamic>?> refreshSource(
    String slug,
    String sourceId,
  ) async {
    final dio = _dio ??= _getDio();
    final response = await dio.post<Map<String, dynamic>>(
      '/presets/templates/$slug/sources/$sourceId/refresh_feed',
    );
    await load(slug);
    ref.invalidate(feedProvider);
    ref.invalidate(archiveFetchProvider);
    return response.data;
  }

  /// POST /presets/templates/{slug}/refresh_all — bulk-refresh every enabled
  /// source in the preset. SC+YT run in parallel server-side; BC is sequential.
  /// Returns the aggregate summary from the backend.
  Future<Map<String, dynamic>?> refreshAll(String slug) async {
    if (slug.isEmpty) return null;
    state = state.copyWith(loadingRefreshAll: true, error: null);
    try {
      final dio = _getDio();
      debugPrint(
        '[presetSources] refreshAll POST /presets/templates/$slug/refresh_all',
      );
      final response = await dio.post<Map<String, dynamic>>(
        '/presets/templates/$slug/refresh_all',
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
      debugPrint(
        '[presetSources] refreshAll done: '
        'refreshed=${response.data?['sources_refreshed']} '
        'elapsed=${response.data?['elapsed_ms']}ms',
      );
      ref.invalidate(feedProvider);
      ref.invalidate(archiveFetchProvider);
      return response.data;
    } catch (e) {
      state = state.copyWith(error: _message(e));
      return null;
    } finally {
      state = state.copyWith(loadingRefreshAll: false);
    }
  }

  /// Patch artist platform links for a source.
  /// Also marks the artist as manually_verified on the backend.
  Future<void> patchSource(
    String slug,
    String sourceId, {
    String? bandcampUrl,
    String? youtubeUrl,
  }) async {
    final body = <String, dynamic>{
      if (bandcampUrl != null && bandcampUrl.isNotEmpty)
        'bandcamp_url': bandcampUrl,
      if (youtubeUrl != null && youtubeUrl.isNotEmpty)
        'youtube_url': youtubeUrl,
    };
    if (body.isEmpty) return;
    final dio = _dio ??= _getDio();
    await dio.patch<void>(
      '/presets/templates/$slug/sources/$sourceId',
      data: body,
    );
    await load(slug);
  }

  /// Save a manually curated article for the artist linked to this source.
  Future<void> addArticle(
    String slug,
    String sourceId, {
    required String title,
    required String url,
    String? snippet,
    String? source,
  }) async {
    final dio = _dio ??= _getDio();
    await dio.post<void>(
      '/presets/templates/$slug/sources/$sourceId/articles',
      data: {
        'title': title,
        'url': url,
        if (snippet != null && snippet.isNotEmpty) 'snippet': snippet,
        if (source != null && source.isNotEmpty) 'source': source,
      },
    );
  }

  Future<void> preview(String slug) async {
    state = state.copyWith(loadingPreview: true, error: null);
    try {
      final dio = _getDio();
      final response = await dio.get<List<dynamic>>(
        '/feed/merged',
        queryParameters: {'preset_id': slug, 'page': 1, 'limit': 40},
      );
      final items = (response.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(FeedItem.fromJson)
          .toList();
      state = state.copyWith(loadingPreview: false, previewItems: items);
    } catch (e) {
      state = state.copyWith(loadingPreview: false, error: _message(e));
    }
  }

  String _message(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
      return error.message ?? 'Request failed';
    }
    return error.toString();
  }
}
