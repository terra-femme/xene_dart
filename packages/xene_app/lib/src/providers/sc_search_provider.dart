import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_provider.dart';

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
  Timer? _debounce;

  /// Debounced search — waits 500ms after the last call before hitting the backend.
  /// Prevents a request per keystroke when typing in the search field.
  void search(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      clear();
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _doSearch(q));
  }

  Future<void> _doSearch(String q) async {
    if (!mounted) return;

    debugPrint('[scSearchProvider] Searching SoundCloud for "$q"');
    state = state.copyWith(
      status: ScSearchStatus.loading,
      query: q,
      results: [],
    );

    try {
      final dio = ref.read(authenticatedDioProvider);
      final resp = await dio.get<Map<String, dynamic>>(
        '/discovery/sc_search',
        queryParameters: {'q': q},
      );

      if (!mounted) return;

      final collection = (resp.data?['collection'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      debugPrint(
        '[scSearchProvider] Got ${collection.length} results for "$q"',
      );
      state = state.copyWith(
        status: ScSearchStatus.results,
        results: collection,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = _formatError(e);
      debugPrint('[scSearchProvider] DioException: $msg');
      state = state.copyWith(status: ScSearchStatus.error, error: msg);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[scSearchProvider] Unexpected error: $e');
      state = state.copyWith(status: ScSearchStatus.error, error: e.toString());
    }
  }

  void clear() {
    _debounce?.cancel();
    state = const ScSearchState();
  }

  String _formatError(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;
    if (statusCode == 400 && data is Map && data['error'] is String) {
      return data['error'] as String;
    }
    if (statusCode != null) {
      return 'SoundCloud search failed ($statusCode).';
    }
    return 'Could not reach the backend. Try again.';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
