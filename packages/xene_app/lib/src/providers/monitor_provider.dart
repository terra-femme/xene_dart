import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8080',
);

/// Polls GET /monitor every 15 seconds and yields the latest stats map.
/// Auto-disposes when the monitor screen is not visible.
final monitorProvider = StreamProvider.autoDispose<Map<String, dynamic>>((ref) async* {
  final dio = Dio(BaseOptions(baseUrl: _kBackendUrl));
  while (true) {
    try {
      final res = await dio.get<Map<String, dynamic>>('/monitor');
      if (res.data != null) yield res.data!;
    } catch (_) {
      yield {};
    }
    await Future<void>.delayed(const Duration(seconds: 15));
  }
});
