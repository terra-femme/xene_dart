import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kBackendUrl = 'http://localhost:8080';
const _kUserId = 'local_user';

/// Fetches the artist identity graph from GET /discovery/graph.
final graphProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = Dio();
  final resp = await dio.get<Map<String, dynamic>>(
    '$_kBackendUrl/discovery/graph',
    options: Options(headers: {'X-User-Id': _kUserId}),
  );
  return resp.data ?? {'nodes': [], 'links': []};
});

/// Fetches LLM provider availability from GET /discovery/status.
final discoveryStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final dio = Dio();
    final resp = await dio.get<Map<String, dynamic>>(
      '$_kBackendUrl/discovery/status',
    );
    return resp.data ?? {'has_providers': false, 'providers': []};
  } catch (_) {
    return {'has_providers': false, 'providers': []};
  }
});
