import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dio_provider.dart';

enum FollowingStatus { initial, loading, loaded, error }

class FollowingState {
  const FollowingState({
    this.status = FollowingStatus.initial,
    this.collection = const [],
    this.totalCount = 0,
    this.syncedAt,
    this.error,
  });

  final FollowingStatus status;
  final List<Map<String, dynamic>> collection;
  final int totalCount;
  final String? syncedAt;
  final String? error;

  FollowingState copyWith({
    FollowingStatus? status,
    List<Map<String, dynamic>>? collection,
    int? totalCount,
    String? syncedAt,
    String? error,
  }) {
    return FollowingState(
      status: status ?? this.status,
      collection: collection ?? this.collection,
      totalCount: totalCount ?? this.totalCount,
      syncedAt: syncedAt ?? this.syncedAt,
      error: error,
    );
  }
}

final followingProvider =
    StateNotifierProvider<FollowingNotifier, FollowingState>(
      FollowingNotifier.new,
    );

class FollowingNotifier extends StateNotifier<FollowingState> {
  FollowingNotifier(this.ref) : super(const FollowingState());

  final Ref ref;

  Future<void> fetch({bool force = false}) async {
    if (state.status == FollowingStatus.loading) return;

    debugPrint(
      '[followingProvider] Fetching SC following candidates${force ? ' (force)' : ''}',
    );
    state = state.copyWith(status: FollowingStatus.loading);

    try {
      final dio = ref.read(authenticatedDioProvider);
      final resp = await dio.get<Map<String, dynamic>>(
        '/connections/soundcloud/following',
        queryParameters: force ? {'force': 'true'} : null,
      );
      final data = resp.data ?? {};
      final collection = (data['collection'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      debugPrint('[followingProvider] Loaded ${collection.length} candidates');

      state = state.copyWith(
        status: FollowingStatus.loaded,
        collection: collection,
        totalCount: data['total_count'] as int? ?? collection.length,
        syncedAt: data['synced_at'] as String?,
      );
    } on DioException catch (e) {
      final msg = 'SC API error ${e.response?.statusCode}: ${e.message}';
      debugPrint('[followingProvider] DioException: $msg');
      state = state.copyWith(status: FollowingStatus.error, error: msg);
    } catch (e) {
      debugPrint('[followingProvider] Unexpected error: $e');
      state = state.copyWith(
        status: FollowingStatus.error,
        error: e.toString(),
      );
    }
  }

  void reset() {
    state = const FollowingState();
  }
}
