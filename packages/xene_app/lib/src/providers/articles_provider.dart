import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_app/src/providers/preset_provider.dart';

const _kUserId = 'local_user';
const _kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8080',
);

@immutable
class ArticleItem {
  const ArticleItem({
    required this.title,
    required this.url,
    required this.snippet,
    this.source,
    this.publishedAt,
    this.artistId,
  });

  final String title;
  final String url;
  final String snippet;
  final String? source;
  final DateTime? publishedAt;
  final String? artistId;

  factory ArticleItem.fromJson(Map<String, dynamic> json) {
    final pubAtRaw = json['published_at'] as String?;
    return ArticleItem(
      title: (json['title'] as String?)?.trim() ?? '',
      url: (json['url'] as String?)?.trim() ?? '',
      snippet: (json['snippet'] as String?)?.trim() ?? '',
      source: json['source'] as String?,
      publishedAt: pubAtRaw != null ? DateTime.tryParse(pubAtRaw) : null,
      artistId: json['artist_id'] as String?,
    );
  }
}

/// Fetches press articles for the currently active preset.
/// Auto-refetches whenever [activePresetSlugProvider] changes.
final presetArticlesProvider =
    FutureProvider.autoDispose<List<ArticleItem>>((ref) async {
  final slug = ref.watch(activePresetSlugProvider);
  debugPrint('[presetArticlesProvider] Fetching articles for preset=$slug');

  final dio = Dio(
    BaseOptions(
      baseUrl: _kBackendUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
        'X-User-Id': _kUserId,
      },
    ),
  );

  try {
    final response = await dio.get<List<dynamic>>(
      '/presets/articles',
      queryParameters: {'preset': slug, 'limit': 12},
    );
    final data = response.data ?? [];
    debugPrint(
      '[presetArticlesProvider] Raw response: ${data.length} items for preset=$slug',
    );
    final items = data
        .whereType<Map<String, dynamic>>()
        .map(ArticleItem.fromJson)
        .where((a) => a.title.isNotEmpty)
        .toList();
    debugPrint(
      '[presetArticlesProvider] Filtered to ${items.length} valid articles for preset=$slug',
    );
    return items;
  } catch (e) {
    debugPrint('[presetArticlesProvider] Error fetching articles for $slug: $e');
    return const [];
  }
});
