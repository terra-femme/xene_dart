import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kBackendUrl = 'http://127.0.0.1:8080';
const _kUserId = 'local_user';

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

    debugPrint('[followingProvider] Fetching SC following candidates${force ? ' (force)' : ''}');
    state = state.copyWith(status: FollowingStatus.loading);

    try {
      final dio = Dio();
      final url = '$_kBackendUrl/connections/soundcloud/following${force ? '?force=true' : ''}';
      final resp = await dio.get<Map<String, dynamic>>(
        url,
        options: Options(headers: {'X-User-Id': _kUserId}),
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
      state = state.copyWith(status: FollowingStatus.error, error: e.toString());
    }
  }

  void reset() {
    state = const FollowingState();
  }
}
