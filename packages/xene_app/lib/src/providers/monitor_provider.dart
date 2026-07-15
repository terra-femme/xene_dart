import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config_provider.dart';

/// Polls GET /monitor every 15 seconds and yields the latest stats map.
/// Auto-disposes when the monitor screen is not visible.
final monitorProvider = StreamProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async* {
  final configAsync = ref.watch(appConfigProvider);

  // Extract config values with fallbacks.
  final baseUrl =
      configAsync.whenData((config) => config.backendUrl).asData?.value ??
      kProductionBackendUrl;
  final connectTimeoutSeconds =
      configAsync
          .whenData((config) => config.monitorTimeoutConnectSeconds)
          .asData
          ?.value ??
      5;
  final receiveTimeoutSeconds =
      configAsync
          .whenData((config) => config.monitorTimeoutReceiveSeconds)
          .asData
          ?.value ??
      8;
  final pollIntervalSeconds =
      configAsync
          .whenData((config) => config.monitorPollIntervalSeconds)
          .asData
          ?.value ??
      15;

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: Duration(seconds: receiveTimeoutSeconds),
    ),
  );
  while (true) {
    try {
      final res = await dio.get<Map<String, dynamic>>('/monitor');
      if (res.data != null) yield res.data!;
    } catch (_) {
      yield {};
    }
    await Future<void>.delayed(Duration(seconds: pollIntervalSeconds));
  }
});
