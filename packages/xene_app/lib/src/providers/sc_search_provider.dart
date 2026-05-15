import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kBackendUrl = 'http://localhost:8080';

enum ScSearchStatus { idle, loading, results, error }

class ScSearchState {
  const ScSearchState({
    this.status = ScSearchStatus.idle,
    this.query = '',
    this.results = const [],
    this.error,
  });

  final ScSearchStatus status;
  final String query;
  final List<Map<String, dynamic>> results;
  final String? error;

  ScSearchState copyWith({
    ScSearchStatus? status,
    String? query,
    List<Map<String, dynamic>>? results,
    String? error,
  }) {
    return ScSearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      results: results ?? this.results,
      error: error,
    );
  }
}

final scSearchProvider = StateNotifierProvider<ScSearchNotifier, ScSearchState>(
  ScSearchNotifier.new,
);

class ScSearchNotifier extends StateNotifier<ScSearchState> {
  ScSearchNotifier(this.ref) : super(const ScSearchState());

  final Ref ref;

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      clear();
      return;
    }

    debugPrint('[scSearchProvider] Searching SoundCloud for "$q"');
    state = state.copyWith(
      status: ScSearchStatus.loading,
      query: q,
      results: [],
    );

    try {
      final resp = await _getSearchResults(q);
      final collection = (resp.data?['collection'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      debugPrint('[scSearchProvider] Got ${collection.length} results for "$q"');
      state = state.copyWith(
        status: ScSearchStatus.results,
        results: collection,
      );
    } on DioException catch (e) {
      final msg = _formatSearchError(e);
      debugPrint('[scSearchProvider] DioException: $msg');
      state = state.copyWith(status: ScSearchStatus.error, error: msg);
    } catch (e) {
      debugPrint('[scSearchProvider] Unexpected error: $e');
      state = state.copyWith(status: ScSearchStatus.error, error: e.toString());
    }
  }

  void clear() {
    state = const ScSearchState();
  }

  Future<Response<Map<String, dynamic>>> _getSearchResults(String q) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: _kBackendUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    try {
      return await dio.get<Map<String, dynamic>>(
        '/discovery/sc_search',
        queryParameters: {'q': q},
      );
    } on DioException catch (e) {
      if (!_shouldRetry(e)) rethrow;

      debugPrint(
        '[scSearchProvider] Retrying SoundCloud search after ${e.type}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      return dio.get<Map<String, dynamic>>(
        '/discovery/sc_search',
        queryParameters: {'q': q},
      );
    }
  }

  bool _shouldRetry(DioException e) {
    return e.response == null &&
        (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.unknown);
  }

  String _formatSearchError(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    if (statusCode == 400 && data is Map && data['error'] is String) {
      return data['error'] as String;
    }

    if (statusCode != null) {
      return 'SoundCloud search failed ($statusCode).';
    }

    return 'Could not reach the local backend. Try again once it finishes '
        'reloading.';
  }
}
