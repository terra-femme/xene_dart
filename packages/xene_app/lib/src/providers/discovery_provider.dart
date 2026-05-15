import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kBackendUrl = 'http://localhost:8080';
const _kUserId = 'local_user';

enum DiscoveryStatus { idle, loading, result, saving, saved, error }

class DiscoveryState {
  const DiscoveryState({
    this.status = DiscoveryStatus.idle,
    this.result,
    this.savedArtist,
    this.error,
  });

  final DiscoveryStatus status;
  final Map<String, dynamic>? result;
  final Map<String, dynamic>? savedArtist;
  final String? error;

  DiscoveryState copyWith({
    DiscoveryStatus? status,
    Map<String, dynamic>? result,
    Map<String, dynamic>? savedArtist,
    String? error,
  }) {
    return DiscoveryState(
      status: status ?? this.status,
      result: result ?? this.result,
      savedArtist: savedArtist ?? this.savedArtist,
      error: error,
    );
  }
}

final discoveryProvider =
    StateNotifierProvider<DiscoveryNotifier, DiscoveryState>(
  DiscoveryNotifier.new,
);

class DiscoveryNotifier extends StateNotifier<DiscoveryState> {
  DiscoveryNotifier(this.ref) : super(const DiscoveryState());

  final Ref ref;

  /// Run the LLM identity walk for an artist.
  Future<void> autoDiscover(String name, {String? scProfileUrl}) async {
    debugPrint('[discoveryProvider.autoDiscover] ▶ CALLED name="$name" scProfileUrl="$scProfileUrl"');
    debugPrint('[discoveryProvider.autoDiscover] current state before call = ${state.status}');

    if (state.status == DiscoveryStatus.loading) {
      debugPrint('[discoveryProvider.autoDiscover] ✗ SKIPPED — already loading');
      return;
    }

    state = const DiscoveryState(status: DiscoveryStatus.loading);
    debugPrint('[discoveryProvider.autoDiscover] state → loading');

    try {
      final dio = Dio();
      final queryParams = <String, String>{'name': name};
      if (scProfileUrl != null && scProfileUrl.isNotEmpty) {
        queryParams['sc_profile_url'] = scProfileUrl;
      }

      final url = '$_kBackendUrl/discovery/auto_discover';
      debugPrint('[discoveryProvider.autoDiscover] → GET $url params=$queryParams');

      final resp = await dio.get<Map<String, dynamic>>(
        url,
        queryParameters: queryParams,
      );

      debugPrint('[discoveryProvider.autoDiscover] ← HTTP ${resp.statusCode}');
      debugPrint('[discoveryProvider.autoDiscover] response keys = ${resp.data?.keys.toList()}');
      debugPrint('[discoveryProvider.autoDiscover] name=${resp.data?['name']} soundcloud_url=${resp.data?['soundcloud_url']} soundcloud_username=${resp.data?['soundcloud_username']}');
      debugPrint('[discoveryProvider.autoDiscover] identity_confidence=${resp.data?['identity_confidence']} coverage_level=${resp.data?['coverage_level']}');

      final result = resp.data ?? {};
      if (result.isEmpty) {
        debugPrint('[discoveryProvider.autoDiscover] ⚠ WARNING — response data is empty map');
      }

      state = state.copyWith(status: DiscoveryStatus.result, result: result);
      debugPrint('[discoveryProvider.autoDiscover] state → result');
    } on DioException catch (e) {
      final body = e.response?.data?.toString() ?? 'no body';
      final msg = 'Discovery error ${e.response?.statusCode}: ${e.message}';
      debugPrint('[discoveryProvider.autoDiscover] ✗ DioException: $msg');
      debugPrint('[discoveryProvider.autoDiscover] response body: $body');
      state = state.copyWith(status: DiscoveryStatus.error, error: msg);
    } catch (e, st) {
      debugPrint('[discoveryProvider.autoDiscover] ✗ Unexpected error: $e');
      debugPrint('[discoveryProvider.autoDiscover] stacktrace: $st');
      state = state.copyWith(status: DiscoveryStatus.error, error: e.toString());
    }
  }

  /// Save the confirmed discovery result to the artists table.
  Future<void> saveDiscovery(Map<String, dynamic> result) async {
    debugPrint('[discoveryProvider.saveDiscovery] ▶ CALLED name=${result['name']}');
    debugPrint('[discoveryProvider.saveDiscovery] current state = ${state.status}');
    debugPrint('[discoveryProvider.saveDiscovery] posting keys = ${result.keys.toList()}');

    if (state.status == DiscoveryStatus.saving) {
      debugPrint('[discoveryProvider.saveDiscovery] ✗ SKIPPED — already saving');
      return;
    }

    state = state.copyWith(status: DiscoveryStatus.saving);
    debugPrint('[discoveryProvider.saveDiscovery] state → saving');

    try {
      final dio = Dio();
      final url = '$_kBackendUrl/discovery/save_discovery';
      debugPrint('[discoveryProvider.saveDiscovery] → POST $url');

      final resp = await dio.post<Map<String, dynamic>>(
        url,
        data: result,
        options: Options(
          headers: {
            'X-User-Id': _kUserId,
            'Content-Type': 'application/json',
          },
        ),
      );

      debugPrint('[discoveryProvider.saveDiscovery] ← HTTP ${resp.statusCode}');
      debugPrint('[discoveryProvider.saveDiscovery] saved keys = ${resp.data?.keys.toList()}');
      debugPrint('[discoveryProvider.saveDiscovery] saved id=${resp.data?['id']} name=${resp.data?['name']}');

      final saved = resp.data ?? {};
      state = state.copyWith(status: DiscoveryStatus.saved, savedArtist: saved);
      debugPrint('[discoveryProvider.saveDiscovery] state → saved ✓');
    } on DioException catch (e) {
      final body = e.response?.data?.toString() ?? 'no body';
      final msg = 'Save error ${e.response?.statusCode}: ${e.message}';
      debugPrint('[discoveryProvider.saveDiscovery] ✗ DioException: $msg');
      debugPrint('[discoveryProvider.saveDiscovery] response body: $body');
      state = state.copyWith(status: DiscoveryStatus.error, error: msg);
    } catch (e, st) {
      debugPrint('[discoveryProvider.saveDiscovery] ✗ Unexpected error: $e');
      debugPrint('[discoveryProvider.saveDiscovery] stacktrace: $st');
      state = state.copyWith(status: DiscoveryStatus.error, error: e.toString());
    }
  }

  void reset() {
    state = const DiscoveryState();
  }
}
