import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dio_provider.dart';

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
      final dio = ref.read(authenticatedDioProvider);
      final resp = await dio.get<String>(
        '/connections/status',
        queryParameters: {'platform': 'soundcloud'},
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
    try {
      final dio = ref.read(authenticatedDioProvider);
      final resp = await dio.post<Map<String, dynamic>>(
        '/auth/soundcloud/nonce',
      );
      final authUrl = resp.data?['auth_url'] as String?;
      if (authUrl == null) {
        debugPrint('[scConnection] nonce endpoint returned no auth_url');
        return;
      }
      final uri = Uri.parse(authUrl);
      if (!await canLaunchUrl(uri)) return;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[scConnection] connect error: $e');
      return;
    }
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
      final dio = ref.read(authenticatedDioProvider);
      await dio.delete('/connections/soundcloud/disconnect');
      debugPrint('[scConnection] Disconnected from SoundCloud');
    } catch (e) {
      debugPrint('[scConnection] disconnect error: $e');
    }
    if (mounted)
      state = state.copyWith(status: ScConnectionStatus.disconnected);
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
