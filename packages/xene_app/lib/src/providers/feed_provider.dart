import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';

final feedProvider = AsyncNotifierProvider<FeedNotifier, List<FeedItem>>(FeedNotifier.new);

class FeedNotifier extends AsyncNotifier<List<FeedItem>> {
  late final Dio _dio;

  @override
  Future<List<FeedItem>> build() async {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://didactic-giggle-jjwg55rgq7p6hjpp-8080.app.github.dev',
      // Codespaces proxies can be slow; give them time
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));
    return _fetchFeed(page: 1);
  }

  Future<List<FeedItem>> _fetchFeed({required int page}) async {
    try {
      final response = await _dio.get('/feed/merged', queryParameters: {
        'page': page,
        'limit': 30,
      });
      
      final data = response.data as List;
      return data.map((json) => FeedItem.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      // Re-throwing allows the UI to show the specific error message
      rethrow;
    }
  }
}