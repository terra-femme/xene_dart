import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:xene_domain/xene_domain.dart';

/// ELI5: The "Newsroom" provider. 
/// It's a special department that is responsible for fetching 
/// and updating the feed list.
final feedProvider = AsyncNotifierProvider<FeedNotifier, List<FeedItem>>(FeedNotifier.new);

class FeedNotifier extends AsyncNotifier<List<FeedItem>> {
  final _dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080')); // Local Dart Frog for now

  @override
  Future<List<FeedItem>> build() async {
    // Initial load: Fetch the first page of the merged feed
    return _fetchFeed(page: 1);
  }

  Future<List<FeedItem>> _fetchFeed({required int page}) async {
    try {
      // In a real app, we would get these from an ArtistProvider or similar
      // For the MVP scaffold, we're just making the call.
      final response = await _dio.get('/feed/merged', queryParameters: {
        'page': page,
        'limit': 30,
      });

      final data = response.data as List;
      return data.map((json) => FeedItem.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e, stack) {
      _logger.severe('Feed fetch failed', e, stack);
      return [];
    }
  }

  /// ELI5: Getting more items when you scroll to the bottom.
  Future<void> fetchMore() async {
    final currentItems = state.value ?? [];
    final nextPage = (currentItems.length / 30).floor() + 1;
    
    state = const AsyncLoading();
    
    final newItems = await _fetchFeed(page: nextPage);
    state = AsyncData([...currentItems, ...newItems]);
  }
}
