import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

const _kBackendUrl = 'http://localhost:8080';
const _kUserId = 'local_user';
const _kPollInterval = Duration(seconds: 3);
const _kPollTimeout = Duration(minutes: 5);

enum ScConnectionStatus { unknown, connected, disconnected }

class ScConnectionState {
  const ScConnectionState({
    this.status = ScConnectionStatus.unknown,
    this.isPolling = false,
  });

  final ScConnectionStatus status;
  final bool isPolling;

  bool get connected => status == ScConnectionStatus.connected;
  bool get disconnected => status == ScConnectionStatus.disconnected;

  ScConnectionState copyWith({ScConnectionStatus? status, bool? isPolling}) =>
      ScConnectionState(
        status: status ?? this.status,
        isPolling: isPolling ?? this.isPolling,
      );
}

final soundcloudConnectionProvider =
    StateNotifierProvider<ScConnectionNotifier, ScConnectionState>(
  ScConnectionNotifier.new,
);

class ScConnectionNotifier extends StateNotifier<ScConnectionState> {
  ScConnectionNotifier(this.ref) : super(const ScConnectionState()) {
    Future.microtask(checkStatus);
  }

  final Ref ref;
  Timer? _pollTimer;
  Timer? _pollTimeout;

  Future<void> checkStatus() async {
    try {
      final dio = Dio();
      final resp = await dio.get<String>(
        '$_kBackendUrl/connections/status',
        queryParameters: {'platform': 'soundcloud', 'user_id': _kUserId},
        options: Options(responseType: ResponseType.plain),
      );
      final body = jsonDecode(resp.data ?? '{}') as Map<String, dynamic>;
      final connected = body['connected'] == true;
      if (mounted) {
        state = state.copyWith(
          status: connected
              ? ScConnectionStatus.connected
              : ScConnectionStatus.disconnected,
        );
      }
    } catch (e) {
      debugPrint('[scConnection] checkStatus error: $e');
      if (mounted) {
        state = state.copyWith(status: ScConnectionStatus.disconnected);
      }
    }
  }

  Future<void> connect() async {
    final uri = Uri.parse('$_kBackendUrl/auth/soundcloud');
    if (!await canLaunchUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (state.isPolling) return;
    state = state.copyWith(isPolling: true);
    _pollTimer = Timer.periodic(_kPollInterval, (_) async {
      await checkStatus();
      if (state.connected) _stopPolling();
    });
    _pollTimeout = Timer(_kPollTimeout, _stopPolling);
  }

  Future<void> disconnect() async {
    try {
      final dio = Dio();
      await dio.delete(
        '$_kBackendUrl/connections/soundcloud/disconnect',
        options: Options(headers: {'X-User-Id': _kUserId}),
      );
      debugPrint('[scConnection] Disconnected from SoundCloud');
    } catch (e) {
      debugPrint('[scConnection] disconnect error: $e');
    }
    if (mounted) state = state.copyWith(status: ScConnectionStatus.disconnected);
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimeout?.cancel();
    _pollTimer = null;
    _pollTimeout = null;
    if (mounted) state = state.copyWith(isPolling: false);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimeout?.cancel();
    super.dispose();
  }
}
