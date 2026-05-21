import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'dio_provider.dart';

/// Fetches the artist identity graph from GET /discovery/graph.
final graphProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(currentUserIdProvider); // ensure auth guard fires
  final dio = ref.watch(authenticatedDioProvider);
  final resp = await dio.get<Map<String, dynamic>>('/discovery/graph');
  return resp.data ?? {'nodes': [], 'links': []};
});

/// Fetches LLM provider availability from GET /discovery/status.
final discoveryStatusProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  try {
    final dio = ref.watch(authenticatedDioProvider);
    final resp = await dio.get<Map<String, dynamic>>('/discovery/status');
    return resp.data ?? {'has_providers': false, 'providers': []};
  } catch (_) {
    return {'has_providers': false, 'providers': []};
  }
});
