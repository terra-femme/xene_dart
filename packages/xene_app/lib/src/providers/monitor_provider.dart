import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config_provider.dart';
import 'dio_provider.dart';

/// Thrown when /monitor rejects the caller rather than failing to answer.
///
/// Distinct from a transport failure because it is **not transient** — polling
/// will never clear it. The screen renders this instead of claiming the backend
/// is offline.
class MonitorAccessDenied implements Exception {
  const MonitorAccessDenied(this.statusCode);

  final int statusCode;

  @override
  String toString() => statusCode == 403
      ? 'Admin access required — this account is not an admin.'
      : 'Not signed in — /monitor requires a real (non-anonymous) session.';
}

/// Polls GET /monitor every 15 seconds and yields the latest stats map.
/// Auto-disposes when the monitor screen is not visible.
///
/// Uses [authenticatedDioProvider] — /monitor is gated by `requireRealUser` plus
/// a `profiles.role == 'admin'` check (routes/monitor.dart), so a bare Dio gets
/// a 401 on every poll and the screen shows a misleading "backend may be
/// offline". Note the shared client owns `connectTimeout`; only `receiveTimeout`
/// can be set per request, which is the one that matters for a poll (a request
/// must not outlive its interval).
final monitorProvider = StreamProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async* {
  final dio = ref.watch(authenticatedDioProvider);
  final configAsync = ref.watch(appConfigProvider);

  // Extract config values with fallbacks.
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

  while (true) {
    try {
      final res = await dio.get<Map<String, dynamic>>(
        '/monitor',
        options: Options(
          receiveTimeout: Duration(seconds: receiveTimeoutSeconds),
        ),
      );
      if (res.data != null) yield res.data!;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        // Terminating the stream is deliberate: retrying cannot fix an
        // authorization failure, and yielding {} would hide it behind the
        // screen's generic offline message.
        throw MonitorAccessDenied(status!);
      }
      yield {};
    } catch (_) {
      yield {};
    }
    await Future<void>.delayed(Duration(seconds: pollIntervalSeconds));
  }
});
