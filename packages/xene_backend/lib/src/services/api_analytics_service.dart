import 'dart:collection';

import 'package:dio/dio.dart';

class ApiAnalyticsService {
  ApiAnalyticsService();

  static const _maxRecentCalls = 80;

  final DateTime _startedAt = DateTime.now().toUtc();
  final _providers = <String, _ProviderStats>{};
  final _recentCalls = ListQueue<_ApiCallEntry>();

  Dio trackDio(Dio dio, String provider) {
    dio.interceptors.add(_ApiAnalyticsInterceptor(this, provider));
    return dio;
  }

  void recordLlmCall({
    required String provider,
    required String context,
    required int inputTokens,
    required int outputTokens,
    required bool grounded,
    required int keyIndex,
  }) {
    final stats = _statsFor(provider);
    stats.calls++;
    stats.successes++;
    stats.inputTokens += inputTokens;
    stats.outputTokens += outputTokens;
    if (grounded) stats.groundedCalls++;
    stats.lastStatusCode = 200;
    stats.lastSeenAt = DateTime.now().toUtc();

    _pushRecent(
      _ApiCallEntry(
        timestamp: stats.lastSeenAt!,
        provider: provider,
        method: 'LLM',
        path: context,
        statusCode: 200,
        durationMs: null,
        throttled: false,
        transient: false,
        error: null,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        grounded: grounded,
        keyIndex: keyIndex,
      ),
    );
  }

  void recordLlmError({
    required String provider,
    required String context,
    required Object error,
    bool throttled = false,
  }) {
    final stats = _statsFor(provider);
    stats.calls++;
    stats.failures++;
    if (throttled) stats.throttles++;
    stats.lastSeenAt = DateTime.now().toUtc();
    stats.lastError = _shortError(error);

    _pushRecent(
      _ApiCallEntry(
        timestamp: stats.lastSeenAt!,
        provider: provider,
        method: 'LLM',
        path: context,
        statusCode: null,
        durationMs: null,
        throttled: throttled,
        transient: throttled,
        error: stats.lastError,
        inputTokens: null,
        outputTokens: null,
        grounded: null,
        keyIndex: null,
      ),
    );
  }

  Map<String, dynamic> get stats {
    final providers =
        _providers.entries.map((entry) {
          final p = entry.value;
          return {
            'provider': entry.key,
            'calls': p.calls,
            'successes': p.successes,
            'failures': p.failures,
            'throttles': p.throttles,
            'transientErrors': p.transientErrors,
            'inFlight': p.inFlight,
            'avgLatencyMs': p.completedHttpCalls == 0
                ? 0
                : (p.totalLatencyMs / p.completedHttpCalls).round(),
            'lastStatusCode': p.lastStatusCode,
            'lastError': p.lastError,
            'lastSeenAt': p.lastSeenAt?.toIso8601String(),
            'inputTokens': p.inputTokens,
            'outputTokens': p.outputTokens,
            'groundedCalls': p.groundedCalls,
            'statusCodes': [
              for (final status in p.statusCodes.entries)
                {'status': status.key, 'count': status.value},
            ],
          };
        }).toList()..sort(
          (a, b) =>
              ((b['calls'] as int?) ?? 0).compareTo((a['calls'] as int?) ?? 0),
        );

    final totals = {
      'calls': _providers.values.fold<int>(0, (sum, p) => sum + p.calls),
      'successes': _providers.values.fold<int>(
        0,
        (sum, p) => sum + p.successes,
      ),
      'failures': _providers.values.fold<int>(0, (sum, p) => sum + p.failures),
      'throttles': _providers.values.fold<int>(
        0,
        (sum, p) => sum + p.throttles,
      ),
      'inFlight': _providers.values.fold<int>(0, (sum, p) => sum + p.inFlight),
    };

    return {
      'startedAt': _startedAt.toIso8601String(),
      'totals': totals,
      'providers': providers,
      'recentCalls': _recentCalls
          .toList()
          .reversed
          .map((e) => e.toJson())
          .toList(),
    };
  }

  void _onRequest(String provider) {
    final stats = _statsFor(provider);
    stats.inFlight++;
  }

  void _onResponse({
    required String provider,
    required RequestOptions options,
    required int? statusCode,
    required int durationMs,
  }) {
    final stats = _statsFor(provider);
    if (stats.inFlight > 0) stats.inFlight--;
    stats.calls++;
    stats.completedHttpCalls++;
    stats.totalLatencyMs += durationMs;
    stats.lastStatusCode = statusCode;
    stats.lastSeenAt = DateTime.now().toUtc();

    if (statusCode != null) {
      stats.statusCodes[statusCode] = (stats.statusCodes[statusCode] ?? 0) + 1;
    }

    final throttled = _isThrottledStatus(statusCode);
    final transient = _isTransientStatus(statusCode);
    if (throttled) stats.throttles++;
    if (transient) stats.transientErrors++;
    if (statusCode != null && statusCode >= 200 && statusCode < 400) {
      stats.successes++;
    } else {
      stats.failures++;
      stats.lastError = statusCode == null ? 'No status' : 'HTTP $statusCode';
    }

    _pushRecent(
      _ApiCallEntry(
        timestamp: stats.lastSeenAt!,
        provider: provider,
        method: options.method,
        path: _pathFor(options),
        statusCode: statusCode,
        durationMs: durationMs,
        throttled: throttled,
        transient: transient,
        error: stats.lastError,
        inputTokens: null,
        outputTokens: null,
        grounded: null,
        keyIndex: null,
      ),
    );
  }

  void _onError({
    required String provider,
    required RequestOptions options,
    required int? statusCode,
    required int durationMs,
    required Object error,
  }) {
    final stats = _statsFor(provider);
    if (stats.inFlight > 0) stats.inFlight--;
    stats.calls++;
    stats.failures++;
    stats.completedHttpCalls++;
    stats.totalLatencyMs += durationMs;
    stats.lastStatusCode = statusCode;
    stats.lastSeenAt = DateTime.now().toUtc();
    stats.lastError = _shortError(error);

    if (statusCode != null) {
      stats.statusCodes[statusCode] = (stats.statusCodes[statusCode] ?? 0) + 1;
    }

    final throttled = _isThrottledStatus(statusCode) || _looksLikeQuota(error);
    final transient = throttled || _isTransientStatus(statusCode);
    if (throttled) stats.throttles++;
    if (transient) stats.transientErrors++;

    _pushRecent(
      _ApiCallEntry(
        timestamp: stats.lastSeenAt!,
        provider: provider,
        method: options.method,
        path: _pathFor(options),
        statusCode: statusCode,
        durationMs: durationMs,
        throttled: throttled,
        transient: transient,
        error: stats.lastError,
        inputTokens: null,
        outputTokens: null,
        grounded: null,
        keyIndex: null,
      ),
    );
  }

  _ProviderStats _statsFor(String provider) =>
      _providers.putIfAbsent(provider, _ProviderStats.new);

  void _pushRecent(_ApiCallEntry entry) {
    while (_recentCalls.length >= _maxRecentCalls) {
      _recentCalls.removeFirst();
    }
    _recentCalls.add(entry);
  }

  static bool _isThrottledStatus(int? statusCode) =>
      statusCode == 429 || statusCode == 403;

  static bool _isTransientStatus(int? statusCode) =>
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  static bool _looksLikeQuota(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('quota') ||
        msg.contains('rate limit') ||
        msg.contains('ratelimit') ||
        msg.contains('too many requests') ||
        msg.contains('resource_exhausted');
  }

  static String _pathFor(RequestOptions options) {
    final path = options.uri.path.isEmpty ? options.path : options.uri.path;
    return path.length > 80 ? '${path.substring(0, 77)}...' : path;
  }

  static String _shortError(Object error) {
    final raw = error.toString().replaceAll(RegExp(r'\s+'), ' ');
    return raw.length > 160 ? '${raw.substring(0, 157)}...' : raw;
  }
}

class _ApiAnalyticsInterceptor extends Interceptor {
  _ApiAnalyticsInterceptor(this.analytics, this.provider);

  final ApiAnalyticsService analytics;
  final String provider;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['xene_monitor_started_at'] = DateTime.now()
        .toUtc()
        .microsecondsSinceEpoch;
    analytics._onRequest(provider);
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    analytics._onResponse(
      provider: provider,
      options: response.requestOptions,
      statusCode: response.statusCode,
      durationMs: _durationMs(response.requestOptions),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    analytics._onError(
      provider: provider,
      options: err.requestOptions,
      statusCode: err.response?.statusCode,
      durationMs: _durationMs(err.requestOptions),
      error: err,
    );
    handler.next(err);
  }

  int _durationMs(RequestOptions options) {
    final started = options.extra['xene_monitor_started_at'] as int?;
    if (started == null) return 0;
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    return ((now - started) / 1000).round();
  }
}

class _ProviderStats {
  int calls = 0;
  int successes = 0;
  int failures = 0;
  int throttles = 0;
  int transientErrors = 0;
  int inFlight = 0;
  int completedHttpCalls = 0;
  int totalLatencyMs = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  int groundedCalls = 0;
  int? lastStatusCode;
  String? lastError;
  DateTime? lastSeenAt;
  final statusCodes = <int, int>{};
}

class _ApiCallEntry {
  const _ApiCallEntry({
    required this.timestamp,
    required this.provider,
    required this.method,
    required this.path,
    required this.statusCode,
    required this.durationMs,
    required this.throttled,
    required this.transient,
    required this.error,
    required this.inputTokens,
    required this.outputTokens,
    required this.grounded,
    required this.keyIndex,
  });

  final DateTime timestamp;
  final String provider;
  final String method;
  final String path;
  final int? statusCode;
  final int? durationMs;
  final bool throttled;
  final bool transient;
  final String? error;
  final int? inputTokens;
  final int? outputTokens;
  final bool? grounded;
  final int? keyIndex;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'provider': provider,
    'method': method,
    'path': path,
    'statusCode': statusCode,
    'durationMs': durationMs,
    'throttled': throttled,
    'transient': transient,
    'error': error,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'grounded': grounded,
    'keyIndex': keyIndex,
  };
}
